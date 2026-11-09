import {decryptQaBackup} from './qaBackupCrypto.js';

const qi=s=>'"'+String(s).replaceAll('"','""')+'"';
const ql=s=>"'"+String(s).replaceAll("'","''")+"'";
const qualified=(s,n)=>qi(s)+'.'+qi(n);
const canonical=v=>v===null||typeof v!=='object'?JSON.stringify(v):Array.isArray(v)?'['+v.map(canonical).join(',')+']':'{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}';
const canonicalRows=rows=>JSON.stringify(rows.map(canonical).sort());
export async function restoreQaArchive(archive,phrase,{createDatabase,saveDatabase}={}){
 const {data,summary}=await decryptQaBackup(archive,phrase);
 if(data.numeric_encoding!=='decimal-string-v1')throw Error('archive_requires_exact_decimal_encoding');
 const db=await createDatabase();const result={tables:0,rows:0,constraints:0,indexes:0,functions:0,policies:0,triggers:0,sequences:0,allRowsMatch:false,applicationDatabaseRehearsal:false,authRuntimeRestored:false,storageServiceRestored:false,platformRestoreVerified:false};
 let phase='initialization';
 try{
  await db.exec(`create schema auth;create schema extensions;create role anon;create role authenticated;create role service_role;create role pharmacy_catalog_reader;
   create table auth.users(id uuid primary key,email text,raw_app_meta_data jsonb,raw_user_meta_data jsonb,created_at timestamptz,banned_until timestamptz);
   create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id),not_after timestamptz);
  `);
  // Minimal local helpers do not issue live Auth sessions.
  await db.exec(`create or replace function auth.uid() returns uuid language sql stable as $$select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
   create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)$$;
   create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
   set check_function_bodies=false;`);
  for(const schema of data.schemas||[...new Set(data.tables.map(t=>t.schema))])await db.exec('create schema if not exists '+qi(schema));
  const identities=new Set(data.tables.flatMap(t=>t.columns.filter(c=>c.identity).map(c=>t.schema+'.'+t.name+'_'+c.name+'_seq')));
  phase='sequence definitions';
  for(const seq of data.sequences||[]){if(identities.has(seq.schemaname+'.'+seq.sequencename))continue;await db.exec(`create sequence ${qualified(seq.schemaname,seq.sequencename)} as ${seq.data_type} increment by ${seq.increment_by} minvalue ${seq.min_value} maxvalue ${seq.max_value} start with ${seq.start_value} cache ${seq.cache_size}${seq.cycle?' cycle':''}`);}
  phase='table definitions';
  for(const table of data.tables){
   const columns=table.columns.map(c=>qi(c.name)+' '+c.type+(c.identity?' generated '+(c.identity==='a'?'always':'by default')+' as identity':c.generated?' generated always as ('+c.default+') stored':c.default?' default '+c.default:'')+(c.not_null?' not null':''));
   await db.exec('create table '+qualified(table.schema,table.name)+' ('+columns.join(',')+')');result.tables++;
  }
  phase='metadata and rows';
  if(data.auth_metadata?.length)await db.query(`insert into auth.users select id,email,app_metadata,user_metadata,created_at,banned_until from jsonb_to_recordset($1::jsonb) as u(id uuid,email text,app_metadata jsonb,user_metadata jsonb,created_at timestamptz,banned_until timestamptz)`,[JSON.stringify(data.auth_metadata)]);
  for(const table of data.tables){
   if(!table.rows.length)continue;
   const columns=table.columns.filter(c=>!c.generated).map(c=>qi(c.name)).join(',');
   await db.query(`insert into ${qualified(table.schema,table.name)} (${columns}) overriding system value select ${columns} from jsonb_populate_recordset(null::${qualified(table.schema,table.name)},$1::jsonb)`,[JSON.stringify(table.rows)]);result.rows+=table.rows.length;
  }
  phase='constraints';
  for(const foreign of [false,true])for(const table of data.tables)for(const constraint of table.constraints){if(constraint.definition.startsWith('FOREIGN KEY')!==foreign)continue;await db.exec(`alter table ${qualified(table.schema,table.name)} add constraint ${qi(constraint.name)} ${constraint.definition}`);result.constraints++;}
  phase='indexes';
  for(const table of data.tables)for(const index of table.indexes){await db.exec(index.replace(/^CREATE (UNIQUE )?INDEX /,'CREATE $1INDEX IF NOT EXISTS '));result.indexes++;}
  phase='functions';
  for(const f of data.functions){await db.exec(f.definition);result.functions++;}
  phase='policies and triggers';
  for(const table of data.tables){
   for(const p of table.policies){await db.exec(`create policy ${qi(p.policyname)} on ${qualified(table.schema,table.name)} as ${p.permissive} for ${p.cmd} to ${p.roles.map(qi).join(',')}${p.qual?' using ('+p.qual+')':''}${p.with_check?' with check ('+p.with_check+')':''}`);result.policies++;}
   for(const trigger of table.triggers){await db.exec(trigger);result.triggers++;}
   if(table.rls)await db.exec(`alter table ${qualified(table.schema,table.name)} enable row level security`);
   if(table.force_rls)await db.exec(`alter table ${qualified(table.schema,table.name)} force row level security`);
  }
  phase='table and function grants';
  let aclEntries=0;
  const restoreAcl=async(kind,target,acl)=>{
   if(acl===null||acl===undefined)return;
   await db.exec('revoke all on '+kind+' '+target+' from public,anon,authenticated,service_role,pharmacy_catalog_reader');
   const entries=await db.query("select case when a.grantee=0 then 'PUBLIC' else r.rolname end as role,a.privilege_type,a.is_grantable from aclexplode($1::aclitem[]) a left join pg_roles r on r.oid=a.grantee",[acl]);
   for(const a of entries.rows){if(!a.role)throw Error('missing_acl_role');await db.exec('grant '+a.privilege_type+' on '+kind+' '+target+' to '+(a.role==='PUBLIC'?'PUBLIC':qi(a.role))+(a.is_grantable?' with grant option':''));aclEntries++;}
  };
  for(const table of data.tables)await restoreAcl('table',qualified(table.schema,table.name),table.grants);
  for(const f of data.functions)await restoreAcl('function',qualified(f.schema,f.name)+'('+f.arguments+')',f.grants);
  result.tableAndFunctionGrantsRestored=true;result.aclEntries=aclEntries;
  phase='sequence state';
  for(const seq of data.sequences||[]){if(seq.last_value!==null)await db.query('select setval($1::regclass,$2::bigint,true)',[qualified(seq.schemaname,seq.sequencename),seq.last_value]);result.sequences++;}
  phase='row comparison';
  for(const table of data.tables){const precise=table.columns.filter(c=>c.type==='bigint'||c.type.startsWith('numeric')).map(c=>ql(c.name)+',case when r.'+qi(c.name)+' is null then \'null\'::jsonb else to_jsonb(r.'+qi(c.name)+'::text) end').join(',');const row='to_jsonb(r)'+(precise?'||jsonb_build_object('+precise+')':'');const r=await db.query(`select coalesce(jsonb_agg(${row} order by to_jsonb(r)::text),'[]'::jsonb) as rows from ${qualified(table.schema,table.name)} r`);if(canonicalRows(r.rows[0].rows)!==canonicalRows(table.rows))throw Error('row_digest_mismatch');}
  result.allRowsMatch=true;result.applicationDatabaseRehearsal=true;result.archiveSummary=summary;
  // Functions are installed, but not executed; Auth is metadata-only. Schema/sequence ACLs are outside this archive.
  result.grantsRestored=false;result.applicationRpcExecutionVerified=false;
  if(saveDatabase){
   phase='database archive';
   return {result,database:await db.dumpDataDir('gzip')};
  }
  return result;
 }catch(error){const e=new Error('local_restore_failed_at_'+phase,{cause:error});e.safeSummary={...result,failedAt:phase,sqlState:error.code};throw e;}
 finally{await db.close();}
}
