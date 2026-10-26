// Opt-in remote integration tests for ONE disposable synthetic project. Never production.
// Private input JSON is generated outside git; no passwords/JWTs are printed or committed.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {createClient} from '@supabase/supabase-js';
import {loadPublicCatalog} from '../../src/publicCatalogAccess.js';
import {loadClinicalAuditCatalog,CLINICAL_AUDIT_FIELDS} from '../../src/clinicalAuditLoader.js';
const [input,phase,output]=process.argv.slice(2);
if(!input||!['baseline','hardened'].includes(phase))throw Error('Expected private-input.json baseline|hardened [sanitized-output.json]');
const config=JSON.parse(readFileSync(input,'utf8'));
const EXPECTED_PROJECT='vpjxdsprfcpqclnhbeoh';
assert.equal(config.project_ref,EXPECTED_PROJECT,'Wrong isolated project');
assert.equal(config.base_url,'https://'+EXPECTED_PROJECT+'.supabase.co','Wrong isolated origin');
assert.equal(typeof config.public_key,'string');
assert.ok(!config.public_key.startsWith('sb_secret_'),'Only a public API key is allowed');
if(!config.public_key.startsWith('sb_publishable_'))assert.equal(JSON.parse(Buffer.from(config.public_key.split('.')[1],'base64url')).role,'anon');
const makeClient=()=>createClient(config.base_url,config.public_key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:(url,options)=>fetch(url,{...options,signal:options?.signal||AbortSignal.timeout(20000)})}});
const anon=makeClient(),admin=makeClient(),user=makeClient();
const results=[];
async function check(name,work){try{await work();results.push({name,status:'pass'})}catch(error){results.push({name,status:'fail',reason:String(error.message).slice(0,500)})}}
const expectedIds=[1,2,3,4].map(n=>'00000000-0000-4000-8000-00000000000'+n);
const ok=result=>{assert.equal(result.error,null,result.error?.code);return result.data};
function publicRows(data){assert.equal(data.length,2);assert.deepEqual(data.map(x=>x.id).sort(),expectedIds.slice(0,2));for(const p of data)assert.deepEqual(Object.keys(p).sort(),['id','name','active_ingredient','dosage_form','strength','manufacturer','category','unit','sale_price','sale_currency','barcode'].sort())}
try{
 for(const [role,client] of [['admin',admin],['user',user]]){
  const account=config.accounts[role];
  assert.ok(account.email.endsWith('@example.invalid'),'Only synthetic accounts are allowed');
  const signed=ok(await client.auth.signInWithPassword({email:account.email,password:account.password}));
  assert.equal(signed.user.id,account.id);
  const verified=ok(await client.auth.getUser());
  assert.equal(verified.user.id,account.id);assert.equal(verified.user.app_metadata.role,role);
  results.push({name:'real_auth_'+role,status:'pass'});
 }
 const snapshot=ok(await admin.from('products').select('*').order('id'));
 assert.deepEqual(snapshot.map(x=>x.id),phase==='baseline'?[expectedIds[0],expectedIds[1],expectedIds[3]]:expectedIds,'Synthetic fixture must match before any write checks');
 assert.ok(snapshot.every(x=>x.name.startsWith('QA ')),'Synthetic names required');
 if(phase==='baseline'){
  await check('baseline_reproduces_anon_cost_exposure',async()=>{const rows=ok(await anon.from('products').select('purchase_price'));assert.equal(rows.length,3);assert.ok(rows.some(x=>Number(x.purchase_price)>0))});
  await check('baseline_reproduces_non_admin_cost_exposure',async()=>{assert.equal(ok(await user.from('products').select('purchase_price')).length,3)});
 }else{
  await check('no_api_key_rejected',async()=>{const r=await fetch(config.base_url+'/rest/v1/products?select=id&limit=1',{signal:AbortSignal.timeout(20000)});assert.equal(r.status,401)});
  await check('anon_direct_cost_denied',async()=>{const r=await anon.from('products').select('purchase_price');assert.equal(r.error?.code,'42501');assert.equal(r.data,null)});
  await check('anon_cost_filter_denied',async()=>{const r=await anon.from('products').select('name').gt('purchase_price',0);assert.equal(r.error?.code,'42501')});
  await check('non_admin_direct_cost_has_no_rows',async()=>{assert.deepEqual(ok(await user.from('products').select('id,purchase_price')),[])});
  for(const [role,client] of [['anon',anon],['user',user]]){
   await check(role+'_admin_page_empty',async()=>assert.deepEqual(ok(await client.rpc('admin_get_products_page',{p_limit:1,p_offset:0})),[]));
   await check(role+'_public_catalog_safe',async()=>publicRows(ok(await client.rpc('get_public_catalog_v1',{p_limit:500,p_offset:0}))));
  }
  await check('admin_direct_cost_and_all_products_preserved',async()=>{const data=ok(await admin.from('products').select('*').order('id'));assert.deepEqual(data,snapshot)});
  await check('admin_audit_loader_real_api',async()=>{const data=await loadClinicalAuditCatalog({pageSize:1,fetchPage:({limit,offset,signal})=>admin.rpc('admin_get_products_page',{p_limit:limit,p_offset:offset}).select(CLINICAL_AUDIT_FIELDS.join(',')).abortSignal(signal)});assert.equal(data.complete,true);assert.equal(data.rows.length,3);assert.ok(data.rows.every(x=>!Object.hasOwn(x,'purchase_price')))});
  await check('public_frontend_loader_real_api',async()=>{const r=await loadPublicCatalog(anon,{hardened:true,pageSize:1});assert.equal(r.error,null);publicRows(r.data);assert.equal(r.data.find(x=>x.id===expectedIds[0]).sale_currency,'USD');assert.equal(Number(r.data.find(x=>x.id===expectedIds[0]).sale_price),9)});
  await check('legacy_public_query_fails_without_fallback',async()=>{const r=await loadPublicCatalog(anon);assert.equal(r.error?.code,'42501');assert.equal(r.data,null)});
  for(const [name,query] of [['projection',()=>anon.rpc('get_public_catalog_v1').select('purchase_price')],['filter',()=>anon.rpc('get_public_catalog_v1').gt('purchase_price',0)],['order',()=>anon.rpc('get_public_catalog_v1').order('purchase_price')]])await check('public_rpc_cost_'+name+'_denied',async()=>{const r=await query();assert.ok(r.error);assert.equal(r.data,null)});
  await check('private_schema_not_exposed_by_data_api',async()=>{const r=await anon.schema('pharmacy_catalog_private').rpc('read_catalog',{p_limit:1,p_offset:0});assert.equal(r.error?.code,'PGRST106')});
  await check('user_metadata_admin_cannot_elevate',async()=>{const info=ok(await user.auth.getUser());assert.equal(info.user.user_metadata.role,'admin');assert.equal(ok(await user.rpc('is_admin')),false)});
  await check('tampered_real_jwt_rejected',async()=>{const session=ok(await user.auth.getSession()).session;const parts=session.access_token.split('.');const body=JSON.parse(Buffer.from(parts[1],'base64url'));body.app_metadata.role='admin';parts[1]=Buffer.from(JSON.stringify(body)).toString('base64url');const r=await fetch(config.base_url+'/rest/v1/rpc/admin_get_products_page?p_limit=1',{headers:{apikey:config.public_key,Authorization:'Bearer '+parts.join('.')},signal:AbortSignal.timeout(20000)});assert.equal(r.status,401)});
  for(const [role,client] of [['anon',anon],['user',user]]){
   await check(role+'_insert_denied',async()=>{const r=await client.from('products').insert({id:'00000000-0000-4000-8000-000000000990',name:'QA forbidden',customer_visible:true});assert.ok(r.error)});
   await check(role+'_update_denied_or_zero_rows',async()=>{const r=await client.from('products').update({purchase_price:777}).eq('id',expectedIds[0]).select('id');assert.ok(r.error||r.data.length===0)});
   await check(role+'_delete_denied_or_zero_rows',async()=>{const r=await client.from('products').delete().eq('id',expectedIds[0]).select('id');assert.ok(r.error||r.data.length===0)});
  }
  await check('admin_price_update_and_restore_on_synthetic_row',async()=>{
   const original=snapshot[0].purchase_price;
   try{const data=ok(await admin.from('products').update({purchase_price:4.5}).eq('id',expectedIds[0]).select('purchase_price'));assert.equal(data.length,1);assert.equal(Number(data[0].purchase_price),4.5)}
   finally{ok(await admin.from('products').update({purchase_price:original}).eq('id',expectedIds[0]))}
  });
  await check('synthetic_fixture_unchanged_after_all_checks',async()=>{assert.deepEqual(ok(await admin.from('products').select('*').order('id')),snapshot)});
 }
}catch(error){results.push({name:'setup_or_fixture_guard',status:'fail',reason:String(error.message).slice(0,500)})}
finally{await Promise.allSettled([admin.auth.signOut(),user.auth.signOut()])}
const report={project_ref:EXPECTED_PROJECT,phase,synthetic_only:true,production_project_touched:false,passed:results.filter(x=>x.status==='pass').length,failed:results.filter(x=>x.status==='fail').length,results};
if(output)writeFileSync(output,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
if(report.failed)process.exitCode=1;
