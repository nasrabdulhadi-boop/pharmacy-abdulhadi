import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const URL='https://vpjxdsprfcpqclnhbeoh.supabase.co',key=process.env.QA_PUBLISHABLE_KEY;
assert.ok(key);
const sessions=JSON.parse(readFileSync('/tmp/pharmacy-qa-sessions.json','utf8'));
const results=[];
async function rpc(role,name,body={}){const r=await fetch(URL+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,...(sessions[role]?{Authorization:'Bearer '+sessions[role]}:{}),'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(60000)});const text=await r.text();let data;try{data=JSON.parse(text)}catch{data=null}return {status:r.status,data}}
function check(name,fn){try{fn();results.push({name,passed:true});console.log('PASS '+name)}catch(e){results.push({name,passed:false,error:e.message});throw e}}
async function submit(op,payload){const r=await rpc('employee','qa_submit_sandbox_operation',{p_operation:op,p_payload:payload});check('submit '+op,()=>assert.equal(r.status,200,JSON.stringify(r.data)));return r.data}
async function decide(id,yes=true){return rpc('manager','qa_review_employee_operation',{p_id:id,p_approve:yes})}
async function catalog(){const r=await rpc('employee','qa_sandbox_catalog');assert.equal(r.status,200);return r.data}
async function report(){const r=await rpc('manager','qa_sandbox_report');assert.equal(r.status,200);return r.data}
try{
 const suffix=process.env.QA_FIXTURE_SUFFIX||'';const initial=await catalog(),usd=initial.find(x=>x.code==='QA-USD'+suffix),syp=initial.find(x=>x.code==='QA-SYP'+suffix);
 const baseline=await report();const balance=(kind,currency)=>Number(baseline.balances.find(x=>x.kind===kind&&x.currency===currency)?.amount||0);const profit=currency=>Number(baseline.profit.find(x=>x.currency===currency)?.amount||0);
 check('synthetic QA catalog supports USD/SYP and parts',()=>{assert.ok(usd&&syp);assert.equal(usd.parts,10);assert.equal(Number(usd.available),30)});
 await Promise.all(['support','unprivileged','anonymous'].flatMap(role=>['qa_sandbox_catalog','qa_sandbox_documents','qa_sandbox_requests','qa_sandbox_report'].map(async name=>{const r=await rpc(role,name);check(role+' isolated from '+name,()=>assert.ok([401,403].includes(r.status)||(r.status===200&&Array.isArray(r.data)&&r.data.length===0)))})));
 const purchase=await submit('purchase_draft',{product_id:usd.id,quantity:2,bonus:1,unit_cost:1.2,discount:0.4,expiry:'2027-12-31'});
 let r=await decide(purchase);check('purchase approved',()=>{assert.equal(r.status,200,JSON.stringify(r.data));assert.equal(r.data,true)});
 let c=await catalog();check('bonus increases stock without invoice charge',()=>assert.equal(Number(c.find(x=>x.id===usd.id).available),33));
 let rep=await report();check('USD supplier debt is 2.00',()=>assert.equal(Number(rep.balances.find(x=>x.kind==='supplier_debt'&&x.currency==='USD').amount),balance('supplier_debt','USD')+2));
 const ps=await submit('purchase_draft',{product_id:syp.id,quantity:1,bonus:0,unit_cost:150,discount:10,expiry:'2027-12-31'});
 r=await decide(ps);check('SYP purchase approved separately',()=>assert.equal(r.data,true));
 rep=await report();check('supplier currencies separated',()=>{assert.equal(Number(rep.balances.find(x=>x.kind==='supplier_debt'&&x.currency==='USD').amount),balance('supplier_debt','USD')+2);assert.equal(Number(rep.balances.find(x=>x.kind==='supplier_debt'&&x.currency==='SYP').amount),balance('supplier_debt','SYP')+140)});
 const sale=await submit('sale',{product_id:usd.id,quantity:10.5});r=await decide(sale);check('partial sale across FEFO batches',()=>assert.equal(r.data,true,JSON.stringify(r.data)));
 rep=await report();check('cash uses server price and profit uses batch cost',()=>{assert.equal(Number(rep.balances.find(x=>x.kind==='cash'&&x.currency==='USD').amount),balance('cash','USD')+21);assert.equal(Number(rep.profit.find(x=>x.currency==='USD').amount),profit('USD')+10.25)});
 const before=JSON.stringify(rep);r=await decide(sale);check('repeated approval returns false',()=>assert.equal(r.data,false));check('repeated approval has no accounting effects',()=>{});assert.equal(JSON.stringify(await report()),before);
 const oversized=await submit('sale',{product_id:usd.id,quantity:10000});r=await decide(oversized);check('oversell rejected atomically',()=>{assert.equal(r.status,400);assert.equal(r.data.message,'insufficient_stock')});assert.equal(JSON.stringify(await report()),before);
 r=await decide(oversized,false);check('manager can reject failed oversell',()=>assert.equal(r.data,true));
 const docs=await rpc('employee','qa_sandbox_documents');const original=docs.data.find(x=>x.request_id===sale);assert.ok(original);
 const ret=await submit('return_request',{sale_id:original.id,quantity:0.5});r=await decide(ret);check('return restores original batch at original price',()=>assert.equal(r.data,true));
 rep=await report();check('return reverses revenue and actual cost',()=>{assert.equal(Number(rep.balances.find(x=>x.kind==='cash'&&x.currency==='USD').amount),balance('cash','USD')+20);assert.equal(Number(rep.profit.find(x=>x.currency==='USD').amount),profit('USD')+9.75)});
 const excessReturn=await submit('return_request',{sale_id:original.id,quantity:10.1});r=await decide(excessReturn);check('cumulative return cannot exceed sale',()=>assert.equal(r.status,400));await decide(excessReturn,false);
 c=await catalog();const available=Number(c.find(x=>x.id===usd.id).available);
 const count=await submit('inventory_count',{product_id:usd.id,quantity:available-1,expected_quantity:available});r=await decide(count);check('inventory count approved',()=>assert.equal(r.data,true));
 const stale=await submit('inventory_count',{product_id:usd.id,quantity:available,expected_quantity:available});r=await decide(stale);check('stale inventory snapshot blocked',()=>{assert.equal(r.status,400);assert.equal(r.data.message,'inventory_snapshot_stale')});await decide(stale,false);
 const invalid=[['sale',{product_id:usd.id,quantity:0.01}],['sale',{product_id:usd.id,quantity:-1}],['sale',{product_id:usd.id,quantity:1,unit_price:0}],['purchase_draft',{product_id:usd.id,quantity:1,bonus:0,unit_cost:1,discount:2,expiry:'2027-12-31'}],['purchase_draft',{product_id:usd.id,quantity:1,bonus:0,unit_cost:null,discount:0,expiry:'2027-12-31'}]];
 await Promise.all(invalid.map(async([op,payload],i)=>{const x=await rpc('employee','qa_submit_sandbox_operation',{p_operation:op,p_payload:payload});check('invalid payload '+i+' rejected',()=>assert.equal(x.status,400))}));
 const rejected=await submit('sale',{product_id:syp.id,quantity:1});const prev=JSON.stringify(await report());await decide(rejected,false);check('rejection leaves stock and accounting unchanged',()=>{});assert.equal(JSON.stringify(await report()),prev);
 const order=await submit('order_process',{});r=await decide(order);check('order workflow metadata only, no financial entry',()=>assert.equal(r.data,true));
}catch(error){results.push({name:'acceptance run completed',passed:false,error:error.message});throw error}finally{writeFileSync('/tmp/pharmacy-qa-operational-results.json',JSON.stringify({timestamp:new Date().toISOString(),project:'vpjxdsprfcpqclnhbeoh',results},null,2));console.log(JSON.stringify({passed:results.filter(x=>x.passed).length,failed:results.filter(x=>!x.passed)}))}
