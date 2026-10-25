// Entirely in-memory PostgreSQL, with synthetic accounts/products. No pharmacy URLs or credentials.
import test,{before,after} from 'node:test';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
const db=new PGlite();
before(async()=>{
 await db.exec(`
  CREATE ROLE anon NOLOGIN;
  CREATE ROLE authenticated NOLOGIN;
  CREATE SCHEMA clinical_lab;
  GRANT USAGE ON SCHEMA clinical_lab TO anon, authenticated;
  CREATE TABLE clinical_lab.accounts(id text PRIMARY KEY, role text NOT NULL);
  INSERT INTO clinical_lab.accounts VALUES ('synthetic-admin','admin'),('synthetic-user','user');
  CREATE TABLE clinical_lab.products(id text PRIMARY KEY,name text,purchase_price numeric,customer_visible boolean);
  INSERT INTO clinical_lab.products VALUES ('visible','Synthetic visible',4.25,true),('hidden','Synthetic hidden',8.5,false);
  CREATE FUNCTION clinical_lab.is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
   SET search_path=pg_catalog,clinical_lab AS $fn$
    SELECT EXISTS(SELECT 1 FROM clinical_lab.accounts WHERE id=(COALESCE(NULLIF(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'sub') AND role='admin');
   $fn$;
  REVOKE ALL ON FUNCTION clinical_lab.is_admin() FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION clinical_lab.is_admin() TO anon,authenticated;
  ALTER TABLE clinical_lab.products ENABLE ROW LEVEL SECURITY;
  CREATE POLICY synthetic_catalog_rows ON clinical_lab.products FOR SELECT TO anon,authenticated
   USING (customer_visible OR clinical_lab.is_admin());
  GRANT SELECT(id,name,customer_visible) ON clinical_lab.products TO anon,authenticated;
  CREATE VIEW clinical_lab.public_catalog WITH(security_invoker=true) AS
   SELECT id,name FROM clinical_lab.products WHERE customer_visible;
  GRANT SELECT ON clinical_lab.public_catalog TO anon,authenticated;
  CREATE FUNCTION clinical_lab.admin_products() RETURNS TABLE(id text,name text,purchase_price numeric)
   LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,clinical_lab AS $fn$
   BEGIN
    IF NOT clinical_lab.is_admin() THEN RAISE EXCEPTION 'admin required' USING ERRCODE='42501'; END IF;
    RETURN QUERY SELECT p.id,p.name,p.purchase_price FROM clinical_lab.products p;
   END;$fn$;
  REVOKE ALL ON FUNCTION clinical_lab.admin_products() FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION clinical_lab.admin_products() TO authenticated;
 `);
});
after(async()=>db.close());
async function asActor(role,claims,operation){
 assert.ok(['anon','authenticated'].includes(role));
 await db.exec('SET ROLE '+role);
 await db.query("SELECT set_config('request.jwt.claims',$1,false)",[JSON.stringify(claims)]);
 try{return await operation()}finally{await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claims','',false)")}
}
const denied=operation=>assert.rejects(operation,e=>e.code==='42501');
test('anonymous catalog shows only public fields and visible synthetic products',async()=>{
 const result=await asActor('anon',{},()=>db.query('SELECT * FROM clinical_lab.public_catalog'));
 assert.deepEqual(result.rows,[{id:'visible',name:'Synthetic visible'}]);
});
test('anonymous direct purchase cost read is denied',async()=>{
 await denied(()=>asActor('anon',{},()=>db.query('SELECT purchase_price FROM clinical_lab.products')));
});
test('authenticated non-admin direct purchase cost read is denied',async()=>{
 await denied(()=>asActor('authenticated',{sub:'synthetic-user'},()=>db.query('SELECT purchase_price FROM clinical_lab.products')));
});
test('anonymous execution of admin function is denied by grants',async()=>{
 await denied(()=>asActor('anon',{},()=>db.query('SELECT * FROM clinical_lab.admin_products()')));
});
test('authenticated non-admin admin function call is denied by actor check',async()=>{
 await denied(()=>asActor('authenticated',{sub:'synthetic-user'},()=>db.query('SELECT * FROM clinical_lab.admin_products()')));
});
test('admin function retains private-cost and hidden-product access for synthetic admin',async()=>{
 const result=await asActor('authenticated',{sub:'synthetic-admin'},()=>db.query('SELECT * FROM clinical_lab.admin_products() ORDER BY id'));
 assert.equal(result.rows.length,2);assert.equal(Number(result.rows[0].purchase_price),8.5);
});
test('user-editable metadata cannot elevate a synthetic non-admin',async()=>{
 await denied(()=>asActor('authenticated',{sub:'synthetic-user',user_metadata:{role:'admin'},app_metadata:{role:'admin'}},()=>db.query('SELECT * FROM clinical_lab.admin_products()')));
});
test('non-admin cannot insert, change or delete even a public synthetic product',async()=>{
 for(const sql of ["INSERT INTO clinical_lab.products VALUES('bad','bad',1,true)","UPDATE clinical_lab.products SET purchase_price=0 WHERE id='visible'","DELETE FROM clinical_lab.products WHERE id='visible'"]){
  await denied(()=>asActor('authenticated',{sub:'synthetic-user'},()=>db.query(sql)));
 }
 assert.equal((await db.query('SELECT count(*)::int AS n FROM clinical_lab.products')).rows[0].n,2);
});
test('public view stays narrow even for a synthetic admin',async()=>{
 const result=await asActor('authenticated',{sub:'synthetic-admin'},()=>db.query('SELECT * FROM clinical_lab.public_catalog'));
 assert.equal(result.rows.length,1);assert.deepEqual(Object.keys(result.rows[0]).sort(),['id','name']);
});
