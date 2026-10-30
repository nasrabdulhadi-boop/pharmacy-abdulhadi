import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import assert from 'node:assert/strict';
const key=process.env.QA_PUBLISHABLE_KEY,url='https://vpjxdsprfcpqclnhbeoh.supabase.co';
const token=JSON.parse(readFileSync('/tmp/pharmacy-qa-sessions.json')).unprivileged;
const phase=process.argv[2];const path='/tmp/pharmacy-qa-revocation-results.json';
const results=existsSync(path)?JSON.parse(readFileSync(path)):[];
async function call(name,body={}){const r=await fetch(url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});return {status:r.status,data:await r.json()}}
try{
 const role=await call('qa_my_role');assert.equal(role.status,200);
 if(phase==='promoted'){
  assert.equal(role.data,'employee');
  const r=await call('qa_submit_employee_operation',{p_operation:'order_process',p_payload:{}});assert.equal(r.status,200);results.push({name:'current server role overrides stale JWT after promotion',passed:true});
 }else if(phase==='demoted'){
  assert.equal(role.data,'technical_support');const list=await call('qa_list_employee_operations');assert.deepEqual(list.data,[]);
  const r=await call('qa_submit_employee_operation',{p_operation:'sale',p_payload:{}});assert.equal(r.status,403);results.push({name:'demotion denies writes and hides formerly owned requests without JWT refresh',passed:true});
 }else if(phase==='signed-out'){
  assert.equal(role.data,'system_admin');
  const r=await fetch(url+'/auth/v1/logout?scope=global',{method:'POST',headers:{apikey:key,Authorization:'Bearer '+token},signal:AbortSignal.timeout(30000)});assert.equal(r.status,204);
  const after=await call('qa_my_role');assert.equal(after.data,null);
  const admin=await call('is_admin');assert.equal(admin.data,false);
  const denied=await call('qa_sandbox_report');assert.equal(denied.status,403);results.push({name:'global signout immediately rejects old signed manager JWT at database boundary',passed:true});
 }
 console.log({phase,passed:true});
}catch(e){results.push({name:phase,passed:false,error:e.message});throw e}finally{writeFileSync(path,JSON.stringify(results,null,2))}
