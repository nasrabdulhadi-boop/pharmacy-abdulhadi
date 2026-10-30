import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const URL='https://vpjxdsprfcpqclnhbeoh.supabase.co';
const key=process.env.QA_PUBLISHABLE_KEY;
assert.ok(key,'QA_PUBLISHABLE_KEY required');
const accounts=JSON.parse(readFileSync(process.env.QA_ACCOUNTS_FILE||'/tmp/pharmacy-qa-accounts.json','utf8')).users;
const results=[];
const sessions={};
async function request(path,token,body,method='POST'){
 const r=await fetch(URL+path,{method,headers:{apikey:key,...(token?{Authorization:`Bearer ${token}`}:{ normal:'anonymous'}),'Content-Type':'application/json'},...(method!=='GET'?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)});
 const text=await r.text();let data;try{data=JSON.parse(text)}catch{data=null}
 return {status:r.status,ok:r.ok,data};
}
function check(name,fn){try{fn();results.push({name,passed:true})}catch(e){results.push({name,passed:false,error:e.message.slice(0,180)});throw e}}
for(const user of accounts){
 const r=await request('/auth/v1/token?grant_type=password',null,{email:user.email,password:user.password});
 check(`${user.label}: actual Auth password login`,()=>{assert.equal(r.status,200);assert.ok(r.data?.access_token)});
 sessions[user.label]=r.data.access_token;
 const role=await request('/rest/v1/rpc/qa_my_role',sessions[user.label],{});
 check(`${user.label}: server role`,()=>assert.equal(role.data,({manager:'system_admin',employee:'employee',support:'technical_support',unprivileged:null})[user.label]));
}
writeFileSync('/tmp/pharmacy-qa-sessions.json',JSON.stringify(sessions),{mode:0o600});
try{
 for(const label of ['support','unprivileged']){
  for(const [rpc,body] of [['qa_submit_employee_operation',{p_operation:'sale',p_payload:{}}],['qa_review_employee_operation',{p_id:crypto.randomUUID(),p_approve:true}],['qa_submit_staff_approval',{p_action:'inventory_count'}],['qa_decide_staff_approval',{p_id:crypto.randomUUID(),p_approve:true}]]){
   const r=await request('/rest/v1/rpc/'+rpc,sessions[label],body);check(`${label}: denied ${rpc}`,()=>assert.equal(r.status,403));
  }
 }
 for(const operation of ['sale','inventory_count','purchase_draft','order_process','return_request']){
  const r=await request('/rest/v1/rpc/qa_submit_employee_operation',sessions.employee,{p_operation:operation,p_payload:{}});
  check(`employee submits ${operation}`,()=>{assert.equal(r.status,200);assert.match(r.data,/^[a-f0-9-]{36}$/)});
  const id=r.data;
  const forbidden=await request('/rest/v1/rpc/qa_review_employee_operation',sessions.employee,{p_id:id,p_approve:true});check('employee cannot decide '+operation,()=>assert.equal(forbidden.status,403));
  const approve=operation!=='return_request';
  const decision=await request('/rest/v1/rpc/qa_review_employee_operation',sessions.manager,{p_id:id,p_approve:approve});check(`manager ${approve?'approves':'rejects'} ${operation}`,()=>assert.equal(decision.data,true));
  const again=await request('/rest/v1/rpc/qa_review_employee_operation',sessions.manager,{p_id:id,p_approve:!approve});check('decision immutable '+operation,()=>assert.equal(again.data,false));
 }
 for(const label of ['support','unprivileged']){
  const list=await request('/rest/v1/rpc/qa_list_employee_operations',sessions[label],{});check(label+' cannot see employee operations',()=>assert.deepEqual(list.data,[]));
  const products=await request('/rest/v1/products?select=id,purchase_price',sessions[label],null,'GET');check(label+' cannot read privileged products',()=>assert.ok(products.status===403||(products.ok&&products.data.length===0)));
 }
 const health=await request('/rest/v1/rpc/qa_support_health',sessions.support,{});check('support receives sanitized health only',()=>{assert.equal(health.status,200);assert.equal(health.data.length,4);assert.ok(health.data.every(x=>Object.keys(x).sort().join(',')==='component,status'))});
 for(const rpc of ['qa_my_role','qa_list_employee_operations','qa_support_health']){const r=await request('/rest/v1/rpc/'+rpc,null,{});check('anonymous denied '+rpc,()=>assert.ok([401,403].includes(r.status)))}
 const bad=await request('/rest/v1/rpc/qa_submit_employee_operation',sessions.employee,{p_operation:'price_change',p_payload:{}});check('invalid operation rejected',()=>assert.equal(bad.status,400));
 const spoof=await request('/auth/v1/user',sessions.unprivileged,{data:{system_role:'system_admin',role:'admin'}},'PUT');check('untrusted user metadata may be updated',()=>assert.equal(spoof.status,200));
 const role=await request('/rest/v1/rpc/qa_my_role',sessions.unprivileged,{});check('user metadata cannot grant server role',()=>assert.equal(role.data,null));
}finally{
 writeFileSync(process.env.QA_RESULTS_FILE||'/tmp/pharmacy-qa-auth-results.json',JSON.stringify({timestamp:new Date().toISOString(),project:'vpjxdsprfcpqclnhbeoh',results},null,2));
 console.log(JSON.stringify({passed:results.filter(x=>x.passed).length,failed:results.filter(x=>!x.passed),total:results.length}));
}
