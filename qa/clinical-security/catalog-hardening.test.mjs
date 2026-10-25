// Applies the exact proposal to a fresh synthetic database. Never connects to Supabase.
import test,{before,after} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
import {loadPublicCatalog} from '../../src/publicCatalogAccess.js';
const db=new PGlite();
const proposal=readFileSync(new URL('./catalog-hardening.proposal.sql',import.meta.url),'utf8');
let beforeRows;
before(async()=>{
 await db.exec(`
 CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;
 CREATE ROLE qa_migration_operator NOLOGIN CREATEROLE;
 GRANT USAGE ON SCHEMA public TO anon,authenticated;
 CREATE SCHEMA auth;
 GRANT USAGE ON SCHEMA auth TO anon,authenticated;
 CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $jwt$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb;$jwt$;
 CREATE TABLE auth.users(id text PRIMARY KEY,role text);
 INSERT INTO auth.users VALUES('synthetic-admin','admin'),('synthetic-user','user');
 CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT EXISTS(SELECT 1 FROM auth.users WHERE id=(COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'sub') AND role='admin');$fn$;
 CREATE TABLE public.products(id uuid PRIMARY KEY,barcode text,name text,active_ingredient text,dosage_form text,strength text,manufacturer text,category text,unit text,reorder_level numeric,customer_visible boolean,created_at timestamptz,updated_at timestamptz,sale_price numeric,parts_per_unit numeric,purchase_price numeric,active boolean,sale_currency text);
 INSERT INTO public.products(id,name,customer_visible,active,purchase_price,sale_price,sale_currency,barcode) VALUES
 ('00000000-0000-0000-0000-000000000001','Visible',true,true,4.25,9,'USD','001'),
 ('00000000-0000-0000-0000-000000000002','Hidden',false,true,8.5,15,'SYP','002'),
 ('00000000-0000-0000-0000-000000000003','Archived',true,false,3,7,'SYP','003');
 ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
 CREATE POLICY "public products read" ON public.products FOR SELECT TO anon,authenticated USING(customer_visible=true);
 CREATE POLICY "Admins can insert products" ON public.products FOR INSERT TO authenticated WITH CHECK((auth.jwt()->'app_metadata'->>'role')='admin');
 CREATE POLICY "Admins can update products" ON public.products FOR UPDATE TO authenticated USING((auth.jwt()->'app_metadata'->>'role')='admin') WITH CHECK((auth.jwt()->'app_metadata'->>'role')='admin');
 CREATE POLICY "Admins can delete products" ON public.products FOR DELETE TO authenticated USING((auth.jwt()->'app_metadata'->>'role')='admin');
 GRANT SELECT,INSERT,UPDATE,DELETE ON public.products TO anon,authenticated;
 ALTER TABLE public.products OWNER TO qa_migration_operator;
 ALTER SCHEMA public OWNER TO qa_migration_operator;
 `);
 const database=(await db.query('SELECT current_database() AS name')).rows[0].name;
 await db.exec('GRANT CREATE ON DATABASE "'+database.replaceAll('"','""')+'" TO qa_migration_operator');
 // Establish the original leak before applying the candidate, using only synthetic values.
 const exposed=await asActor('anon',{},()=>db.query('SELECT purchase_price FROM public.products'));
 assert.equal(exposed.rows.length,2);
 beforeRows=(await db.query('SELECT to_jsonb(p) AS row FROM public.products p ORDER BY id')).rows;
 // Guard must refuse ordinary execution and roll back without changing the baseline.
 await assert.rejects(()=>db.exec(proposal),/opt-in/);await db.exec('ROLLBACK');
 await db.query("SELECT set_config('pharmacy.catalog_hardening_test','isolated-only',false)");
 await db.exec('SET ROLE qa_migration_operator');
 try{await db.exec(proposal)}catch(error){await db.exec('ROLLBACK');throw error}finally{await db.exec('RESET ROLE')}
});
after(async()=>db.close());
async function asActor(role,claims,operation){
 assert.ok(['anon','authenticated','pharmacy_catalog_reader'].includes(role));
 await db.exec('SET ROLE '+role);
 await db.query("SELECT set_config('request.jwt.claims',$1,false)",[JSON.stringify(claims)]);
 try{return await operation()}finally{await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claims','',false)")}
}
const denied=fn=>assert.rejects(fn,error=>error.code==='42501');
test('exact proposal preserves all synthetic records and cost/currency values',async()=>{
 assert.deepEqual((await db.query('SELECT to_jsonb(p) AS row FROM public.products p ORDER BY id')).rows,beforeRows);
});
test('anonymous direct table reads and cost filters are denied after proposal',async()=>{
 for(const query of ['SELECT * FROM public.products','SELECT purchase_price FROM public.products','SELECT name FROM public.products WHERE purchase_price>0'])await denied(()=>asActor('anon',{},()=>db.query(query)));
});
test('ordinary authenticated direct cost reads return no rows under RLS',async()=>{
 const result=await asActor('authenticated',{sub:'synthetic-user'},()=>db.query('SELECT id,purchase_price FROM public.products'));
 assert.deepEqual(result.rows,[]);
});
test('public RPC preserves safe sale currency/price and excludes hidden or archived products',async()=>{
 for(const role of ['anon','authenticated']){
  const result=await asActor(role,{sub:'synthetic-user'},()=>db.query('SELECT * FROM public.get_public_catalog_v1(500,0)'));
  assert.equal(result.rows.length,1);assert.equal(result.rows[0].name,'Visible');
  assert.equal(result.rows[0].sale_currency,'USD');assert.equal(Number(result.rows[0].sale_price),9);
  assert.deepEqual(Object.keys(result.rows[0]).sort(),['id','name','active_ingredient','dosage_form','strength','manufacturer','category','unit','sale_price','sale_currency','barcode'].sort());
 }
});
test('existing administrator direct SELECT retains cost and hidden/archived products',async()=>{
 const result=await asActor('authenticated',{sub:'synthetic-admin'},()=>db.query('SELECT * FROM public.products ORDER BY id'));
 assert.equal(result.rows.length,3);assert.equal(Number(result.rows[1].purchase_price),8.5);
});
test('restricted routine owner has no cost grant, login, bypass-RLS, or table ownership',async()=>{
 const result=await db.query("SELECT r.rolcanlogin,r.rolbypassrls,has_column_privilege(r.rolname,'public.products','purchase_price','SELECT') AS cost_grant,c.relowner=r.oid AS owns_table FROM pg_roles r CROSS JOIN pg_class c WHERE r.rolname='pharmacy_catalog_reader' AND c.oid='public.products'::regclass");
 assert.deepEqual(result.rows[0],{rolcanlogin:false,rolbypassrls:false,cost_grant:false,owns_table:false});
 await denied(()=>asActor('pharmacy_catalog_reader',{},()=>db.query('SELECT purchase_price FROM public.products')));
});
test('user-supplied metadata cannot bypass authenticated RLS',async()=>{
 const result=await asActor('authenticated',{sub:'synthetic-user',user_metadata:{role:'admin'}},()=>db.query('SELECT purchase_price FROM public.products'));
 assert.deepEqual(result.rows,[]);
});
test('anonymous public RPC cannot select a cost column even by changing SQL projection',async()=>{
 await assert.rejects(()=>asActor('anon',{},()=>db.query('SELECT purchase_price FROM public.get_public_catalog_v1(500,0)')),error=>error.code==='42703');
});
test('public pagination is bounded and offsets clamp safely',async()=>{
 const first=await asActor('anon',{},()=>db.query('SELECT * FROM public.get_public_catalog_v1(-1,-5)'));
 const rest=await asActor('anon',{},()=>db.query('SELECT * FROM public.get_public_catalog_v1(500,1)'));
 assert.equal(first.rows.length,1);assert.equal(rest.rows.length,0);
});
test('reader cannot create schema objects or mutate products',async()=>{
 await denied(()=>asActor('pharmacy_catalog_reader',{},()=>db.exec('CREATE TABLE pharmacy_catalog_private.unexpected(id int)')));
 await denied(()=>asActor('pharmacy_catalog_reader',{},()=>db.exec("UPDATE public.products SET name='bad'")));
});
test('reserved objects prevent accidental reapplication without weakening the installed proposal',async()=>{
 await assert.rejects(()=>db.exec(proposal),/SELECT policies|already exist/);await db.exec('ROLLBACK');
 await denied(()=>asActor('anon',{},()=>db.query('SELECT purchase_price FROM public.products')));
});
test('non-superuser schema owner retains management but does not inherit or SET the reader role',async()=>{
 const result=await db.query("SELECT rolsuper,pg_has_role('qa_migration_operator','pharmacy_catalog_reader','USAGE') AS inherits_reader,pg_has_role('qa_migration_operator','pharmacy_catalog_reader','SET') AS can_set_reader FROM pg_roles WHERE rolname='qa_migration_operator'");
 assert.deepEqual(result.rows[0],{rolsuper:false,inherits_reader:false,can_set_reader:false});
});
test('existing synthetic admin update policy still works, with the test transaction rolled back',async()=>{
 await asActor('authenticated',{sub:'synthetic-admin',app_metadata:{role:'admin'}},async()=>{
  await db.exec('BEGIN');
  try{const result=await db.query("UPDATE public.products SET purchase_price=99 WHERE name='Hidden' RETURNING purchase_price");assert.equal(Number(result.rows[0].purchase_price),99)}
  finally{await db.exec('ROLLBACK')}
 });
 assert.deepEqual((await db.query('SELECT to_jsonb(p) AS row FROM public.products p ORDER BY id')).rows,beforeRows);
});
test('hardened client loader integrates with the exact SQL proposal through paginated synthetic calls',async()=>{
 const client={
  from(){assert.fail('insecure fallback is forbidden')},
  async rpc(name,args){
   assert.equal(name,'get_public_catalog_v1');
   try{return {data:(await asActor('anon',{},()=>db.query('SELECT * FROM public.get_public_catalog_v1($1,$2)',[args.p_limit,args.p_offset]))).rows,error:null}}
   catch(error){return {data:null,error}}
  }
 };
 const result=await loadPublicCatalog(client,{hardened:true,pageSize:1});
 assert.equal(result.error,null);assert.equal(result.data.length,1);
 assert.equal(result.data[0].name,'Visible');assert.equal(Object.hasOwn(result.data[0],'purchase_price'),false);
});
