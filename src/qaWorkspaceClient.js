import {ISOLATED_QA_PROJECT_URL} from './stagingAuthGuard.js';
const denied=()=>({data:null,error:{code:'42501',message:'هذه العملية غير متاحة لصلاحيات الحساب أو لم تُربط بعد ببيئة QA.'}});
const ok=data=>({data,error:null});
const privileged=r=>['system_admin','system_owner'].includes(r);
const syntheticSupplier={id:'00000000-0000-4000-8000-000000009001',name:'مورد QA اصطناعي',phone:null,address:null,notes:null};
function query(run){
 const filters=[];let limit=null,offset=0,single=false,count=false,head=false,sort=null,mutation=false;
 const q={then(resolve,reject){return Promise.resolve().then(()=>mutation?denied():run()).then(r=>{
  if(mutation||r.error)return mutation?denied():r;
  if(!Array.isArray(r.data))return r;
  let rows=r.data.filter(x=>filters.every(fn=>fn(x)));
  const n=rows.length;if(sort)rows=[...rows].sort((a,b)=>String(a[sort.key]??'').localeCompare(String(b[sort.key]??''))*(sort.asc?1:-1));
  rows=rows.slice(offset,limit==null?undefined:offset+limit);
  return {data:head?null:single?(rows[0]||null):rows,error:null,...(count?{count:n}:{})};
 }).then(resolve,reject)},catch(fn){return q.then(x=>x,fn)},finally(fn){return q.then(x=>x).finally(fn)},
 select(_fields,options={}){count=options.count==='exact';head=options.head===true;return q},
 eq(k,v){filters.push(x=>x[k]===v);return q},neq(k,v){filters.push(x=>x[k]!==v);return q},in(k,v){filters.push(x=>v.includes(x[k]));return q},is(k,v){filters.push(x=>(x[k]??null)===v);return q},
 gt(k,v){filters.push(x=>x[k]>v);return q},gte(k,v){filters.push(x=>x[k]>=v);return q},lt(k,v){filters.push(x=>x[k]<v);return q},lte(k,v){filters.push(x=>x[k]<=v);return q},
 ilike(k,v){filters.push(x=>String(x[k]||'').toLowerCase().includes(v.replaceAll('%','').toLowerCase()));return q},or(){return q},
 order(key,options={}){sort={key,asc:options.ascending!==false};return q},range(a,b){offset=a;limit=b-a+1;return q},limit(n){limit=n;return q},maybeSingle(){single=true;return q},single(){single=true;return q},
 insert(){mutation=true;return q},update(){mutation=true;return q},upsert(){mutation=true;return q},delete(){mutation=true;return q}};return q;
}
export function createQaWorkspaceClient(raw,{url,getRole,getIdentity=()=>null,isRedacted=()=>false}){
 if(!raw)return null;
 let pending=null;const counts=new Map();
 const snapshot=()=>{
  const identity=String(getIdentity())+':'+getRole();
  if(!pending||pending.identity!==identity){
   const request={identity,promise:null};
   request.promise=Promise.resolve(raw.rpc('qa_workspace_snapshot')).then(r=>identity===String(getIdentity())+':'+getRole()?r:denied()).finally(()=>{if(pending===request)pending=null});
   pending=request;
  }
  return pending.promise;
 };
 const view=async(fn)=>{const r=await snapshot();if(r.error)return r;return ok(fn(r.data||{}))};
 const products=s=>(s.products||[]).map(p=>({...p,total_count:(s.products||[]).length,stock:Number(p.stock||0),sale_price_syp:Number(p.sale_price||0)*(p.sale_currency==='USD'?Number(s.fx_rate):1),current_fx_rate:s.fx_rate}));
 const batches=s=>(s.batches||[]).map(b=>{const p=products(s).find(p=>p.id===b.product_id)||{};return {...p,...b,products:p,name:p.name,barcode:p.barcode,sale_price:p.sale_price,sale_currency:p.sale_currency}});
 const docs=(s,kind)=>(s.documents||[]).filter(d=>!kind||d.kind===kind).map(d=>({...d,product_name:products(s).find(p=>p.id===d.product_id)?.name||'صنف QA',unit_price:Number(d.total)/Math.max(Number(d.quantity),0.0001),unit_cost:d.cost==null?null:Number(d.cost)/Math.max(Number(d.quantity),0.0001),payment_method:'cash',paid_amount:d.total,due_amount:0,sale_id:d.id,sale_item_id:d.id}));
 const toSyp=(d,s)=>Number(d.total||0)*(d.currency==='USD'?s.fx_rate:1);
 const report=(s,args={})=>{
  const list=docs(s).filter(d=>(!args.p_start||d.created_at>=args.p_start)&&(!args.p_end||d.created_at<args.p_end));
  const sales=list.filter(d=>d.kind==='sale'),returns=list.filter(d=>d.kind==='return_request'),purchases=list.filter(d=>d.kind==='purchase_draft');
  const sum=a=>a.reduce((n,d)=>n+toSyp(d,s),0),cost=a=>a.reduce((n,d)=>n+Number(d.cost||0)*(d.currency==='USD'?s.fx_rate:1),0);
  return {summary:{sales:sum(sales),net_sales:sum(sales)-sum(returns),profit:sum(sales)-sum(returns)-cost(sales)+cost(returns),purchases:sum(purchases),sales_count:sales.length},sales_rows:sales,purchase_rows:purchases,return_rows:returns,debt_rows:[],comparison:{},checks:{}};
 };
 const mapRead=(name,args={})=>view(s=>{
  const rows=products(s),search=String(args.p_query||'').toLowerCase();const match=p=>[p.name,p.barcode,p.id].some(x=>String(x).toLowerCase().includes(search));
  if(['admin_get_products','admin_get_products_page','admin_product_catalog_currency','admin_search_purchase_products_currency','admin_search_inventory_products','admin_search_pos_products_currency'].includes(name))return rows.filter(match).slice(Number(args.p_offset||0),Number(args.p_offset||0)+Number(args.p_limit||500));
  if(name==='admin_get_inventory')return batches(s);
  if(name==='admin_products_count')return rows.length;
  if(name==='admin_cashbox_reconcile')return {qa_read_only:true};
  if(name==='admin_get_currency_settings')return {usd_to_syp:s.fx_rate};
  if(name==='admin_resolve_product_barcode')return rows.find(p=>p.barcode===args.p_barcode)?.id||null;
  if(name==='admin_product_search_key_for_barcode')return rows.find(p=>p.barcode===args.p_barcode)?.name||null;
  if(name==='admin_get_product_barcodes')return [];
  if(name==='admin_pos_stock_unavailable_reason')return 'لا يوجد رصيد تجريبي صالح متاح لهذا الصنف.';
  if(name==='admin_smart_summary')return {low_stock:rows.filter(p=>p.stock<=1).length,expired:batches(s).filter(b=>b.expiry_date<new Date().toISOString().slice(0,10)).length,expiring_30:0,dead_stock:0};
  if(name==='admin_inventory_count_items')return counts.get(args.p_count_id)?.owner===getIdentity()?counts.get(args.p_count_id).items:[];
  if(['admin_reorder_recommendations','admin_latest_inventory_count_result','admin_inventory_count_sales_summary'].includes(name))return [];
  if(name==='admin_inventory_count_result')return null;
  if(name==='admin_list_suppliers')return [syntheticSupplier];
  if(name==='admin_list_sales')return docs(s,'sale');
  if(name==='admin_list_sale_items')return docs(s,'sale');
  if(name==='admin_return_list')return docs(s,'return_request').map(d=>({...d,type:'customer',amount:d.total}));
  if(name==='admin_supplier_return_options')return [];
  if(name==='get_admin_orders')return (s.requests||[]).filter(r=>r.operation==='order_process').map(r=>({...r,status:r.status==='pending'?'new':'completed',customer_name:'طلب QA اصطناعي'}));
  if(name==='admin_list_purchases_currency_v1')return docs(s,'purchase_draft').map(d=>({...d,invoice_number:d.id.slice(0,8),supplier_id:syntheticSupplier.id,supplier_name:syntheticSupplier.name,invoice_date:d.created_at.slice(0,10),item_count:1,paid_amount:0,due_amount:d.total,payment_status:'unpaid'}));
  if(name==='admin_currency_purchase_detail_v1'){const d=docs(s,'purchase_draft').find(x=>x.id===args.p_purchase_id);return d?{...d,items:[{...d,product_id:d.product_id,purchase_price:d.unit_price,expiry_date:null}],supplier_name:syntheticSupplier.name}:null}
  if(['admin_dashboard_day_details','admin_dashboard_sales_day','admin_accounting_report'].includes(name))return report(s,args);
  if(name==='admin_cashbox_summary_v2'){const cash=(s.report?.balances||[]).filter(x=>x.kind==='cash').reduce((n,x)=>n+Number(x.amount)*(x.currency==='USD'?s.fx_rate:1),0);return {cash_in:cash,cash_out:0,net:cash,balance:cash,entries:[]}}
  if(name==='admin_currency_supplier_debt_list_v1')return (s.report?.balances||[]).filter(b=>b.kind==='supplier_debt').map(b=>({...syntheticSupplier,currency:b.currency,balance:b.amount,invoice_total:b.amount,paid_total:0,invoice_count:docs(s,'purchase_draft').filter(d=>d.currency===b.currency).length,last_payment:null}));
  if(name==='admin_currency_supplier_ledger_v1'){const invoices=docs(s,'purchase_draft').filter(d=>d.currency===args.p_currency).map(d=>({...d,invoice_number:d.id.slice(0,8),invoice_date:d.created_at.slice(0,10),due_amount:d.total,paid_amount:0}));return {supplier:syntheticSupplier,summary:{currency:args.p_currency,balance:invoices.reduce((n,d)=>n+Number(d.total),0)},invoices,payments:[]}}
  if(['admin_list_debtors','admin_search_debtors','admin_customer_profiles','admin_cashbox_count_history','admin_currency_supplier_debt_list_v1'].includes(name))return [];
  return null;
 });
 const reads=new Set(['admin_get_products','admin_get_products_page','admin_product_catalog_currency','admin_search_purchase_products_currency','admin_search_inventory_products','admin_search_pos_products_currency','admin_get_inventory','admin_products_count','admin_get_currency_settings','admin_cashbox_reconcile','admin_currency_supplier_ledger_v1','admin_resolve_product_barcode','admin_product_search_key_for_barcode','admin_get_product_barcodes','admin_pos_stock_unavailable_reason','admin_smart_summary','admin_inventory_count_items','admin_reorder_recommendations','admin_latest_inventory_count_result','admin_inventory_count_sales_summary','admin_inventory_count_result','admin_list_suppliers','admin_list_sales','admin_list_sale_items','admin_return_list','admin_supplier_return_options','get_admin_orders','admin_list_purchases_currency_v1','admin_currency_purchase_detail_v1','admin_dashboard_day_details','admin_dashboard_sales_day','admin_accounting_report','admin_cashbox_summary_v2','admin_list_debtors','admin_search_debtors','admin_customer_profiles','admin_cashbox_count_history','admin_currency_supplier_debt_list_v1','admin_currency_supplier_ledger_v1']);
 const finance=new Set(['admin_accounting_report','admin_dashboard_day_details','admin_dashboard_sales_day','admin_cashbox_summary_v2','admin_cashbox_count_history','admin_currency_supplier_debt_list_v1','admin_currency_supplier_ledger_v1']);
 async function write(name,args){
  if(!['employee','system_admin','system_owner'].includes(getRole()))return denied();
  const execute=privileged(getRole());
  const command=execute?'qa_manager_execute_workspace':'qa_submit_workspace_bundle';
  const response=r=>r.error?r:ok({qa_pending:!execute,qa_executed:execute,request_id:r.data});
  if(['admin_start_inventory_count','admin_start_product_inventory_count'].includes(name)){
   const s=await snapshot();if(s.error)return s;
   const id=crypto.randomUUID();counts.set(id,{owner:getIdentity(),items:products(s.data).filter(p=>!args.p_product_id||p.id===args.p_product_id).map(p=>({id:crypto.randomUUID(),product_id:p.id,product_name:p.name,barcode:p.barcode,expected_quantity:p.stock,actual_quantity:null}))});return ok(id);
  }
  if(name==='admin_set_inventory_count_actual'){
   const item=[...counts.values()].filter(x=>x.owner===getIdentity()).flatMap(x=>x.items).find(x=>x.id===args.p_item_id);
   if(!item||!Number.isFinite(Number(args.p_actual))||Number(args.p_actual)<0)return denied();item.actual_quantity=Number(args.p_actual);return ok(true);
  }
  if(name==='admin_complete_inventory_count'){
   const draft=counts.get(args.p_count_id);if(!draft||draft.owner!==getIdentity()||draft.items.some(x=>x.actual_quantity==null))return denied();
   const r=await raw.rpc(command,{p_operation:'inventory_count',p_payloads:draft.items.map(x=>({product_id:x.product_id,quantity:x.actual_quantity,expected_quantity:x.expected_quantity}))});if(!r.error)counts.delete(args.p_count_id);return response(r);
  }
  if(name==='complete_sale_accounting_currency'){
   if(args.p_payment_method!=='cash'||args.p_debtor_id)return {data:null,error:{code:'QA_PENDING',message:'البيع الآجل غير مفعّل في QA؛ لم يتم حفظ أي جزء من الفاتورة.'}};
   const payloads=(args.p_items||[]).map(i=>({product_id:i.product_id,quantity:i.quantity}));
   const r=await raw.rpc(command,{p_operation:'sale',p_payloads:payloads});return response(r);
  }
  if(name==='admin_create_purchase_usd_v1'||name==='admin_create_purchase_syp_v1'){
   if(Number(args.p_payment_amount||0)>0||args.p_new_supplier)return {data:null,error:{code:'QA_PENDING',message:'تدعم QA مسودة شراء آجلة للمورد الاصطناعي فقط؛ لم يُحفظ أي جزء من الفاتورة.'}};
   const payloads=(args.p_items||[]).map(i=>({product_id:i.product_id,quantity:Number(i.quantity),bonus:Number(i.bonus_quantity||0),unit_cost:Number(i.purchase_price)*(1-Number(i.line_discount||0)/100),discount:0,expiry:i.expiry_date}));
   const subtotal=payloads.reduce((n,x)=>n+x.quantity*x.unit_cost,0);
   const discount=args.p_discount_type==='percent'?subtotal*Number(args.p_discount_value||0)/100:args.p_discount_type==='amount'?Number(args.p_discount_value||0):0;
   if(!Number.isFinite(discount)||discount<0||discount>subtotal)return denied();
   let allocated=0;payloads.forEach((x,i)=>{const share=i===payloads.length-1?discount-allocated:subtotal>0?Math.round(discount*(x.quantity*x.unit_cost)/subtotal*10000)/10000:0;x.discount=share;allocated+=share});
   const r=await raw.rpc(command,{p_operation:'purchase_draft',p_payloads:payloads,p_currency:name.includes('_usd_')?'USD':'SYP'});return response(r);
  }
  if(name==='admin_customer_return'){const r=await raw.rpc(command,{p_operation:'return_request',p_payloads:[{sale_id:args.p_sale_item_id,quantity:Number(args.p_quantity)}]});return response(r)}
  if(name==='admin_update_order_status'){const r=await raw.rpc(command,{p_operation:'order_process',p_payloads:[{}]});return response(r)}
  return denied();
 }
 return new Proxy(raw,{get(target,prop){
  if(prop==='rpc')return (name,args={})=>{
   const role=getRole();
   if(isRedacted())return query(async()=>!reads.has(name)&&name!=='admin_cashbox_reconcile'?denied():ok(['admin_accounting_report','admin_dashboard_day_details','admin_dashboard_sales_day'].includes(name)?{summary:{},comparison:{},checks:{},sales_rows:[],purchase_rows:[],return_rows:[],debt_rows:[]}:name==='admin_get_currency_settings'?{usd_to_syp:null}:name==='admin_cashbox_summary_v2'?{entries:[]}:name==='admin_products_count'?0:[]));
   if(url!==ISOLATED_QA_PROJECT_URL)return role&&!privileged(role)?query(async()=>denied()):target.rpc(name,args);
   if(name.startsWith('qa_')||name==='is_admin'||name==='get_public_catalog_v1')return target.rpc(name,args);
   if(!role)return query(async()=>denied());
   if(role==='technical_support'||(finance.has(name)&&!privileged(role)))return query(async()=>denied());
   return query(()=>reads.has(name)?mapRead(name,args):write(name,args));
  };
  if(prop==='from')return name=>{
   const role=getRole();if(isRedacted())return query(async()=>ok([]));if(url!==ISOLATED_QA_PROJECT_URL)return role&&!privileged(role)?query(async()=>denied()):target.from(name);
   if(!role)return target.from(name);
   return query(()=>role==='technical_support'?Promise.resolve(denied()):view(s=>{
    if(name==='products')return products(s);if(name==='batches')return batches(s);if(name==='sale_items')return docs(s,'sale');
    if(['orders','prescriptions','medicine_requests','offers','audit_logs','pos_shortcut_preferences'].includes(name))return [];
    return [];
   }));
  };
  const value=Reflect.get(target,prop);return typeof value==='function'?value.bind(target):value;
 }});
}
