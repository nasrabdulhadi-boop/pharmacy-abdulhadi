import{readFileSync,writeFileSync}from'node:fs';import assert from'node:assert/strict';
const url='https://vpjxdsprfcpqclnhbeoh.supabase.co',key=process.env.QA_PUBLISHABLE_KEY;
assert.ok(key);const token=JSON.parse(readFileSync('/tmp/pharmacy-qa-sessions.json')).support;
const id=crypto.randomUUID(),results=[];
const cases=[
 ['admin_get_products_page',{p_limit:5,p_offset:0}],['qa_sandbox_catalog',{}],['qa_sandbox_documents',{}],['qa_sandbox_report',{}],['qa_sandbox_requests',{}],['qa_list_employee_operations',{}],['qa_my_staff_approvals',{}],
 ['qa_list_debtors',{}],['qa_debtor_ledger',{p_debtor_id:id}],['qa_security_audit',{}],
 ['qa_create_debtor',{p_name:'FORBIDDEN SUPPORT FIXTURE',p_phone:null,p_address:null,p_notes:null,p_request_id:id}],
 ['qa_record_debtor_payment',{p_debtor_id:id,p_amount:1,p_notes:null,p_payment_method:'cash',p_request_id:id}],
 ['qa_submit_staff_approval',{p_action:'inventory_count'}],['qa_decide_staff_approval',{p_id:id,p_approve:true}],
 ['qa_submit_employee_operation',{p_operation:'sale',p_payload:{}}],['qa_review_employee_operation',{p_id:id,p_approve:true}],
 ['qa_employee_execute_workspace',{p_operation:'sale',p_payloads:[],p_currency:null,p_request_id:id}],
 ['qa_employee_create_purchase',{p_payloads:[],p_currency:'USD',p_request_id:id,p_header:{}}],
 ['qa_submit_workspace_bundle',{p_operation:'sale',p_payloads:[],p_currency:null}],
 ['qa_manager_execute_workspace',{p_operation:'sale',p_payloads:[],p_currency:null}],
 ['qa_submit_sandbox_operation',{p_operation:'sale',p_payload:{}}],
 ['qa_save_workspace_product',{p_product_id:null,p_payload:{},p_barcodes:[],p_request_id:id}],
 ['qa_record_workspace_access',{p_section:'dashboard',p_request_id:id}],
 ['qa_supplier_currency_list_v2',{}],['qa_supplier_currency_cashbox_v2',{}],['qa_supplier_currency_fx_v2',{}],
 ['qa_supplier_currency_ledger_v2',{p_supplier_id:id,p_currency:'USD'}],
 ['qa_supplier_payment_currency_v2',{p_supplier_id:id,p_amount:1,p_debt_currency:'USD',p_tender_currency:'USD',p_fx_rate:140,p_request_id:id,p_purchase_id:null,p_payment_method:'cash',p_notes:null}]
];
const headers={apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'};
try{
 const user=await fetch(url+'/auth/v1/user',{headers,signal:AbortSignal.timeout(15000)});assert.equal(user.status,200);assert.equal((await user.json()).app_metadata?.system_role,'technical_support');
 for(const[name,body]of cases){const r=await fetch(url+'/rest/v1/rpc/'+name,{method:'POST',headers,body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});const data=await r.json();const passed=r.status===403||(r.status===200&&Array.isArray(data)&&data.length===0);results.push({name,passed,status:r.status});assert.ok(passed,name+' did not prove denial (HTTP '+r.status+')');}
 for(const table of ['products','qa_employee_operations','qa_staff_approval_requests']){const r=await fetch(url+'/rest/v1/'+table+'?select=*&limit=1',{headers,signal:AbortSignal.timeout(15000)});const data=await r.json();const passed=r.status===403||(r.status===200&&Array.isArray(data)&&!data.length);results.push({name:'direct '+table,passed,status:r.status});assert.ok(passed,'direct table '+table);}
 const r=await fetch(url+'/rest/v1/debtors?select=*&limit=1',{headers:{...headers,'Accept-Profile':'pharmacy_qa_private'},signal:AbortSignal.timeout(15000)});assert.equal(r.status,406);results.push({name:'private schema is not exposed through REST',passed:true,status:r.status});
}catch(error){results.push({name:'matrix completed',passed:false,error:error.name});process.exitCode=1;}
finally{writeFileSync('/tmp/pharmacy-qa-support-matrix.json',JSON.stringify(results,null,2));console.log({passed:results.filter(x=>x.passed).length,failed:results.filter(x=>!x.passed)});}
