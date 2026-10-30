import {readFileSync,writeFileSync} from 'node:fs';import assert from 'node:assert/strict';
const sessions=JSON.parse(readFileSync('/tmp/pharmacy-qa-sessions.json'));const key=process.env.QA_PUBLISHABLE_KEY;assert.ok(key);const results=[];
async function rpc(role,name,body={}){const r=await fetch('https://vpjxdsprfcpqclnhbeoh.supabase.co/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+sessions[role],'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(60000)});return {status:r.status,data:await r.json()}}
function check(name,fn){try{fn();results.push({name,passed:true});console.log('PASS '+name)}catch(e){results.push({name,passed:false,error:e.message});throw e}}
async function submit(op,p){const r=await rpc('employee','qa_submit_sandbox_operation',{p_operation:op,p_payload:p});assert.equal(r.status,200,JSON.stringify(r.data));return r.data}
const decide=(id,yes=true)=>rpc('manager','qa_review_employee_operation',{p_id:id,p_approve:yes});
try{
 const c=(await rpc('employee','qa_sandbox_catalog')).data;const usd=c.find(x=>x.code==='QA-USD'),syp=c.find(x=>x.code==='QA-SYP');
 for(const approved of [true,false]){
  const r=await rpc('employee','qa_submit_staff_approval',{p_action:'inventory_count'});assert.equal(r.status,200);
  const d=await rpc('manager','qa_decide_staff_approval',{p_id:r.data,p_approve:approved});check('legacy staff approval decision '+approved,()=>assert.equal(d.data,true));
  const again=await rpc('manager','qa_decide_staff_approval',{p_id:r.data,p_approve:!approved});check('legacy staff decision immutable '+approved,()=>assert.equal(again.data,false));
 }
 const id=await submit('sale',{product_id:syp.id,quantity:1});const concurrent=await Promise.all([decide(id),decide(id)]);check('simultaneous decisions execute exactly once',()=>{assert.deepEqual(concurrent.map(x=>x.data).sort(),[false,true])});
 const before=(await rpc('manager','qa_sandbox_report')).data;const bonus=await submit('purchase_draft',{product_id:usd.id,quantity:0,bonus:2,unit_cost:0,discount:0,expiry:'2027-12-31'});const d=await decide(bonus);check('bonus-only purchase accepted',()=>assert.equal(d.data,true));
 const after=(await rpc('manager','qa_sandbox_report')).data;check('bonus-only creates no supplier charge',()=>assert.deepEqual(after.balances.filter(x=>x.kind==='supplier_debt'),before.balances.filter(x=>x.kind==='supplier_debt')));
 const empty=await rpc('employee','qa_submit_sandbox_operation',{p_operation:'purchase_draft',p_payload:{product_id:usd.id,quantity:0,bonus:0,unit_cost:0,discount:0,expiry:'2027-12-31'}});check('zero purchase and zero bonus rejected',()=>assert.equal(empty.status,400));
 const have=Number((await rpc('employee','qa_sandbox_catalog')).data.find(x=>x.id===syp.id).available);const qty=Math.floor(have*0.75)+1;
 const [a,b]=await Promise.all([submit('sale',{product_id:syp.id,quantity:qty}),submit('sale',{product_id:syp.id,quantity:qty})]);
 const sold=await Promise.all([decide(a),decide(b)]);check('concurrent oversell blocked by product serialization',()=>assert.deepEqual(sold.map(x=>x.status).sort(),[200,400]));
 const failed=sold[0].status===400?a:b;await decide(failed,false);
 const left=Number((await rpc('employee','qa_sandbox_catalog')).data.find(x=>x.id===syp.id).available);check('stock matches one winning concurrent sale',()=>assert.equal(left,have-qty));
 const expired=await submit('sale',{product_id:syp.id,quantity:left+1});const ex=await decide(expired);check('expired batch cannot fill unavailable sale',()=>assert.equal(ex.status,400));await decide(expired,false);
 const forbidden=await rpc('manager','qa_submit_sandbox_operation',{p_operation:'order_process',p_payload:{}});check('manager cannot impersonate employee submitter',()=>assert.equal(forbidden.status,403));
 await Promise.all(['support','employee','manager'].flatMap(role=>['qa_employee_operations','qa_staff_approval_requests'].map(async table=>{const r=await fetch('https://vpjxdsprfcpqclnhbeoh.supabase.co/rest/v1/'+table,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+sessions[role],'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(60000)});check(role+' direct queue insert denied '+table,()=>assert.ok([401,403].includes(r.status)))})));
 const docs=(await rpc('employee','qa_sandbox_documents')).data;check('concurrent request produced exactly one document',()=>assert.equal(docs.filter(x=>x.request_id===id).length,1));
} catch(error){results.push({name:'adversarial run completed',passed:false,error:error.message});throw error}finally{writeFileSync('/tmp/pharmacy-qa-adversarial-results.json',JSON.stringify({results},null,2));console.log({passed:results.filter(x=>x.passed).length,failed:results.filter(x=>!x.passed)})}
