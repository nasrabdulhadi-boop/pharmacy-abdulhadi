// Read-only catalog loading. No patient data, writes or clinical approval.
export const CLINICAL_AUDIT_FIELDS=Object.freeze(['id','name','barcode','active_ingredient','strength','dosage_form','manufacturer','active']);
const problem=code=>Object.assign(new Error(code),{code});

async function boundedPage(fetchPage,args,signal,timeoutMs){
 if(signal?.aborted)throw problem('audit_cancelled');
 const controller=new AbortController();
 let timer,cancel;
 const boundary=new Promise((_,reject)=>{
  cancel=()=>{controller.abort();reject(problem('audit_cancelled'))};
  signal?.addEventListener('abort',cancel,{once:true});
  timer=setTimeout(()=>{controller.abort();reject(problem('audit_timeout'))},timeoutMs);
 });
 try{return await Promise.race([Promise.resolve().then(()=>{
  if(controller.signal.aborted)throw problem('audit_cancelled');
  return fetchPage({...args,signal:controller.signal});
 }),boundary])}
 finally{clearTimeout(timer);signal?.removeEventListener('abort',cancel)}
}

export async function loadClinicalAuditCatalog({fetchPage,onProgress=()=>{},signal,pageSize=500,maxRows=20000,timeoutMs=30000}={}){
 if(typeof fetchPage!=='function'||!Number.isInteger(pageSize)||pageSize<1||pageSize>500||
  !Number.isInteger(maxRows)||maxRows<1||maxRows>20000||!Number.isInteger(timeoutMs)||timeoutMs<1||timeoutMs>120000)
  throw problem('audit_invalid_options');
 const rows=[],ids=new Set();
 async function page(limit,offset){
  const result=await boundedPage(fetchPage,{limit,offset},signal,timeoutMs);
  if(signal?.aborted)throw problem('audit_cancelled');
  if(result?.error)throw problem('audit_request_failed');
  const data=result?.data;
  if(!Array.isArray(data)||data.length>limit)throw problem('audit_invalid_page');
  return data.map(row=>{
   if(!row||Array.isArray(row)||typeof row!=='object'||typeof row.id!=='string'||!row.id.trim()||row.id!==row.id.trim()||ids.has(row.id))
    throw problem('audit_invalid_page');
   for(const field of CLINICAL_AUDIT_FIELDS.filter(x=>x!=='id'&&x!=='active'))
    if(row[field]!=null&&typeof row[field]!=='string')throw problem('audit_invalid_page');
   if(row.active!=null&&row.active!==true)throw problem('audit_invalid_page');
   ids.add(row.id);
   return Object.fromEntries(CLINICAL_AUDIT_FIELDS.filter(field=>Object.hasOwn(row,field)).map(field=>[field,row[field]]));
  });
 }
 while(rows.length<maxRows){
  const limit=Math.min(pageSize,maxRows-rows.length);
  const data=await page(limit,rows.length);
  if(!data.length)return {rows,complete:true};
  rows.push(...data);onProgress(rows.length);
  // A server may clamp page sizes. A short page alone cannot prove completion.
 }
 // One sentinel record distinguishes an exact-size catalog from truncation.
 const sentinel=await page(1,rows.length);
 return {rows,complete:sentinel.length===0};
}

export function clinicalAuditErrorMessage(error){
 return ({
  audit_timeout:'انتهت مهلة تحميل صفحة المنتجات. تحقق من الاتصال وأعد المحاولة.',
  audit_cancelled:'تم إيقاف التدقيق. لم تُعتمد النتائج الجزئية.',
  audit_invalid_page:'استجابة المنتجات ناقصة أو مكررة أو غير صالحة. أعد التدقيق؛ وإذا تكرر الخطأ يلزم فحص خدمة البيانات.',
  audit_invalid_options:'إعدادات التدقيق غير صالحة.'
 })[error?.code]||'تعذر تحميل المنتجات. تحقق من الاتصال وصلاحية الدخول ثم أعد المحاولة.';
}
