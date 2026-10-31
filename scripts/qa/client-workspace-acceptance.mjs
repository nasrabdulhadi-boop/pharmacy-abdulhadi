import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {createQaWorkspaceClient} from '../../src/qaWorkspaceClient.js';
import {employeeRequestRows} from '../../src/qaEmployeeRequests.js';
const url='https://vpjxdsprfcpqclnhbeoh.supabase.co';
const key=process.env.QA_PUBLISHABLE_KEY;assert.ok(key);
const sessions=JSON.parse(readFileSync('/tmp/pharmacy-qa-sessions.json','utf8'));
const results=[];
const raw=role=>({rpc:async(name,args={})=>{const r=await fetch(url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,...(sessions[role]?{Authorization:'Bearer '+sessions[role]}:{}),'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(30000)});const data=await r.json();return r.ok?{data,error:null}:{data:null,error:data}}});
const client=role=>createQaWorkspaceClient(raw(role),{url,getRole:()=>({manager:'system_admin',support:'technical_support'})[role]||role,getIdentity:()=>role});
const employee=client('employee'),support=client('support'),manager=client('manager');
const check=(name,fn)=>{fn();results.push({name,passed:true});console.log('PASS '+name)};
let pending=null;
try{
 const catalog=await employee.rpc('admin_get_products_page',{p_limit:100});assert.ifError(catalog.error);const product=catalog.data.find(p=>p.barcode==='QA-USD');assert.ok(product);
 check('original employee catalog omits purchase prices',()=>assert.ok(catalog.data.every(p=>!('purchase_price' in p))));
 const inventory=await employee.rpc('admin_get_inventory');check('original inventory omits batch costs',()=>assert.ok(inventory.data.every(b=>!('purchase_price' in b)&&!('original_purchase_price' in b))));
 for(const rpc of ['admin_get_products_page','admin_get_inventory','admin_accounting_report','admin_cashbox_summary_v2']){const r=await support.rpc(rpc);check('support adapter denies '+rpc,()=>assert.equal(r.error?.code,'42501'))}
 const health=await support.rpc('qa_workspace_snapshot');check('server support response contains only role and health',()=>assert.deepEqual(Object.keys(health.data).sort(),['health','role']));
 const denied=await raw('support').rpc('qa_manager_execute_workspace',{p_operation:'sale',p_payloads:[{product_id:product.id,quantity:0.1}]});check('server denies manager execution bypass by support',()=>assert.equal(denied.error?.code,'42501'));
 const before=product.stock;
 const submitted=await employee.rpc('complete_sale_accounting_currency',{p_payment_method:'cash',p_discount:0,p_items:[{product_id:product.id,quantity:0.1}]});assert.ifError(submitted.error);pending=submitted.data.request_id;
 check('original POS adapter queues employee sale',()=>assert.equal(submitted.data.qa_pending,true));
 const stock=await employee.rpc('admin_get_products_page');check('pending original POS sale does not change stock',()=>assert.equal(stock.data.find(p=>p.id===product.id).stock,before));
 const requests=await employee.rpc('qa_sandbox_requests');const row=employeeRequestRows(requests.data).find(r=>r.id===pending);check('new employee tracking lists pending own request',()=>assert.equal(row?.status,'pending'));
 const decision=await raw('manager').rpc('qa_review_employee_operation',{p_id:pending,p_approve:false});assert.ifError(decision.error);assert.equal(decision.data,true);
 const final=await employee.rpc('qa_sandbox_requests');check('tracking shows manager rejection',()=>assert.equal(employeeRequestRows(final.data).find(r=>r.id===pending)?.status,'rejected'));pending=null;
 const after=await employee.rpc('admin_get_products_page');check('rejected original POS sale leaves stock unchanged',()=>assert.equal(after.data.find(p=>p.id===product.id).stock,before));
 const attempt=await employee.rpc('complete_sale_accounting_currency',{p_payment_method:'cash',p_discount:1,p_items:[{product_id:product.id,quantity:0.1}]});check('unsupported discount cannot silently change total',()=>assert.equal(attempt.error?.code,'QA_PENDING'));
 const credit=await employee.rpc('complete_sale_accounting_currency',{p_payment_method:'credit',p_items:[{product_id:product.id,quantity:0.1}]});check('unsupported credit sale fails before queuing',()=>assert.equal(credit.error?.code,'QA_PENDING'));
 const all=await manager.rpc('qa_sandbox_requests');check('manager queue includes employee request',()=>assert.ok(all.data.some(r=>r.id===submitted.data.request_id)));
 check('request tracking never exposes payload fields',()=>assert.ok(employeeRequestRows(final.data).every(r=>!('payload' in r)&&!('decided_by' in r))));
}catch(e){results.push({name:'client workspace acceptance',passed:false,error:e.message});throw e}
finally{if(pending)await raw('manager').rpc('qa_review_employee_operation',{p_id:pending,p_approve:false});writeFileSync('/tmp/pharmacy-client-workspace-results.json',JSON.stringify({project:'vpjxdsprfcpqclnhbeoh',timestamp:new Date().toISOString(),results},null,2));console.log({passed:results.filter(r=>r.passed).length,failed:results.filter(r=>!r.passed).length})}
