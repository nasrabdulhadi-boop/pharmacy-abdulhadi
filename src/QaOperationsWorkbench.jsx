import React,{useCallback,useEffect,useRef,useState} from 'react';
import './QA_WORKBENCH.css';
import {updateOwnQaPassword} from './qaAccountActions.js';
const names={sale:'بيع تجريبي',purchase_draft:'شراء آجل تجريبي',inventory_count:'جرد تجريبي',return_request:'مرتجع تجريبي',order_process:'معالجة طلب تجريبي'};
const errors={insufficient_stock:'الرصيد المتاح غير كافٍ. لم تُنفّذ العملية.',inventory_snapshot_stale:'تغيّر المخزون بعد إرسال الجرد. ارفض الطلب وأرسل جرداً جديداً.',return_exceeds_sale:'كمية المرتجع تتجاوز المتبقي من الفاتورة.',invalid_product_or_part:'اختر صنفاً وكمية توافق أجزاء العبوة.',invalid_password:'استخدم 12 محرفاً على الأقل وأعد إدخال الكلمة نفسها.',password_update_failed:'تعذر تغيير كلمة المرور. افتح رابط الاسترداد الأحدث أو أعد تسجيل الدخول.',not_authorized:'انتهت صلاحية هذه الجلسة أو لا يسمح دورك بهذه العملية.',invalid_quantity:'أدخل كمية صحيحة موجبة.',unexpected_field:'يتضمن الطلب حقولاً غير مسموحة.'};
const format=n=>new Intl.NumberFormat('ar-SY',{maximumFractionDigits:4}).format(Number(n||0));
export default function QaOperationsWorkbench({client,manager=false,allowPasswordChange=false,projectUrl='',onLogout}){
 const [catalog,setCatalog]=useState([]),[requests,setRequests]=useState([]),[documents,setDocuments]=useState([]),[report,setReport]=useState(null);
 const [operation,setOperation]=useState('sale'),[product,setProduct]=useState(''),[quantity,setQuantity]=useState('1'),[unitCost,setUnitCost]=useState('1'),[bonus,setBonus]=useState('0'),[discount,setDiscount]=useState('0'),[expiry,setExpiry]=useState('2027-12-31'),[saleId,setSaleId]=useState('');
 const [password,setPassword]=useState(''),[confirmation,setConfirmation]=useState('');
 const [busy,setBusy]=useState(false),[loading,setLoading]=useState(true),[notice,setNotice]=useState(''),[failed,setFailed]=useState(false);const lock=useRef(false),epoch=useRef(0);
 const load=useCallback(async()=>{
  const version=++epoch.current;setLoading(true);
  try{
   const responses=await Promise.all([client.rpc('qa_sandbox_catalog'),client.rpc('qa_sandbox_requests'),client.rpc('qa_sandbox_documents'),...(manager?[client.rpc('qa_sandbox_report')]:[])]);
   if(version!==epoch.current)return;
   const error=responses.find(x=>x.error)?.error;if(error)throw error;
   setCatalog(responses[0].data||[]);setRequests(responses[1].data||[]);setDocuments(responses[2].data||[]);setReport(manager?responses[3].data:null);
   setProduct(p=>p||responses[0].data?.[0]?.id||'');
  }catch{if(version===epoch.current){setCatalog([]);setRequests([]);setDocuments([]);setReport(null);setNotice('تعذر تحديث بيانات QA. أعد المحاولة.');setFailed(true)}}finally{if(version===epoch.current)setLoading(false)}
 },[client,manager]);
 useEffect(()=>{load();return()=>{epoch.current++}},[load]);
 const run=async action=>{
  if(lock.current)return;lock.current=true;setBusy(true);setNotice('');setFailed(false);
  try{await action();await load()}catch(e){setFailed(true);setNotice(errors[e?.message]||'تعذر تنفيذ الطلب في QA. تحقق من القيم والصلاحية ثم أعد المحاولة.')}finally{lock.current=false;setBusy(false)}
 };
 const changePassword=e=>{e.preventDefault();run(async()=>{
  try{await updateOwnQaPassword({client,previewEnabled:allowPasswordChange,projectUrl,password,confirmation});
   setNotice('تم تعيين كلمة مرور حساب QA الحالي. احتفظ بها في مدير كلمات مرور آمن.');
  }finally{setPassword('');setConfirmation('')}
 })};
 const chosen=catalog.find(x=>x.id===product);
 const submit=e=>{e.preventDefault();run(async()=>{
  let payload=operation==='order_process'?{}:operation==='return_request'?{sale_id:saleId,quantity:Number(quantity)}:{product_id:product,quantity:Number(quantity)};
  if(operation==='purchase_draft')payload={...payload,unit_cost:Number(unitCost),bonus:Number(bonus),discount:Number(discount),expiry};
  if(operation==='inventory_count')payload.expected_quantity=Number(chosen?.available);
  const {error}=await client.rpc('qa_submit_sandbox_operation',{p_operation:operation,p_payload:payload});if(error)throw error;
  setNotice('أُرسل الطلب. التنفيذ في المخزون التجريبي ينتظر قرار المدير.');
 })};
 const decide=(id,approve)=>run(async()=>{const {data,error}=await client.rpc('qa_review_employee_operation',{p_id:id,p_approve:approve});if(error)throw error;setNotice(data?(approve?'اعتمد الطلب ونُفّذت آثاره داخل QA فقط.':'رُفض الطلب دون تغيير المخزون أو الحسابات.'):'سبق البت بهذا الطلب. تم تحديث القائمة.');});
 const sales=documents.filter(x=>x.kind==='sale');
 return <main className="qaWorkbench" dir="rtl">
  <header className="qaHeader"><div><span className="qaBadge">QA • بيانات اصطناعية فقط</span><h1>{manager?'لوحة مدير QA المستقل':'بوابة موظف QA'}</h1><p>صيدلية عبدالهادي — مختبر الصلاحيات والعمليات</p></div><div className="qaActions"><button onClick={load} disabled={busy||loading}>تحديث</button><button onClick={onLogout}>تسجيل الخروج</button></div></header>
  <aside className="qaBoundary">هذه بيئة اختبار مستقلة. الموافقة على طلب من النموذج أدناه تنفّذ عملية على مخزون QA وحساباته الاصطناعية. الطلبات القديمة الخالية من التفاصيل تغيّر حالتها فقط. هذه التجربة لا تثبت توافق العمليات مع نسخة الإنتاج.</aside>
  {notice&&<p className={failed?'qaNotice error':'qaNotice'} role={failed?'alert':'status'}>{notice}</p>}
  <section className="qaPanel" aria-busy={loading}><h2>المخزون التجريبي القابل للبيع</h2><p>تُستبعد الدفعات المنتهية. أسعار البيع محفوظة على الخادم، وتُحسب التكلفة من الدفعة المصروفة.</p><div className="qaCatalog">{catalog.map(p=><article key={p.id}><span>{p.code}</span><h3>{p.title}</h3><strong>{format(p.available)} عبوة</strong><p>{format(p.sale_price)} {p.currency} / عبوة • {p.parts} أجزاء</p></article>)}</div>{!loading&&!catalog.length&&<p>لا توجد بيانات متاحة لهذا الحساب.</p>}</section>
  {!manager&&<section className="qaPanel"><h2>إرسال عملية للمراجعة</h2><form onSubmit={submit} className="qaForm">
   <label>نوع العملية<select value={operation} onChange={e=>setOperation(e.target.value)}>{Object.entries(names).map(([id,name])=><option key={id} value={id}>{name}</option>)}</select></label>
   {!['return_request','order_process'].includes(operation)&&<label>الصنف<select value={product} onChange={e=>setProduct(e.target.value)} required>{catalog.map(p=><option key={p.id} value={p.id}>{p.code} — {p.currency}</option>)}</select></label>}
   {operation==='return_request'&&<label>فاتورة البيع الأصلية<select value={saleId} onChange={e=>setSaleId(e.target.value)} required><option value="">اختر فاتورة من مبيعاتك</option>{sales.map(d=><option key={d.id} value={d.id}>{d.id.slice(0,8)} • {format(d.quantity)} عبوة • {d.currency}</option>)}</select></label>}
   {operation!=='order_process'&&<label>{operation==='inventory_count'?'الرصيد الفعلي المحسوب':'الكمية بالعبوة'}<input type="number" min={['inventory_count','purchase_draft'].includes(operation)?0:0.0001} max="10000" step="0.0001" value={quantity} onChange={e=>setQuantity(e.target.value)} required/></label>}
   {operation==='inventory_count'&&<p>لقطة الرصيد قبل الجرد: {format(chosen?.available)}. أي حركة لاحقة تستلزم إرسال جرد جديد.</p>}
   {operation==='purchase_draft'&&<><label>سعر شراء العبوة ({chosen?.currency})<input type="number" min="0" max="1000000" step="0.0001" required value={unitCost} onChange={e=>setUnitCost(e.target.value)}/></label><label>البونص<input type="number" min="0" max="10000" step="0.0001" required value={bonus} onChange={e=>setBonus(e.target.value)}/></label><label>خصم الفاتورة<input type="number" min="0" max={Number(quantity)*Number(unitCost)} step="0.0001" required value={discount} onChange={e=>setDiscount(e.target.value)}/></label><label>انتهاء الصلاحية<input type="date" required value={expiry} onChange={e=>setExpiry(e.target.value)}/></label><p>شراء آجل من مورد اصطناعي. البونص يزيد المخزون، والدين يُحفظ بعملة الصنف بصورة مستقلة.</p></>}
   <button className="qaPrimary" disabled={busy||loading||!catalog.length}>{busy?'جارٍ الإرسال…':'إرسال طلب للمدير'}</button>
  </form></section>}
  <section className="qaPanel"><h2>{manager?'قائمة قرارات المدير':'طلباتي ونتائجها'}</h2><p>آخر 100 طلب. كل طلب يقبل قراراً واحداً. فشل التنفيذ يبقيه معلّقاً دون أثر جزئي.</p><div className="qaTable"><table><thead><tr><th>الطلب</th><th>العملية والتفاصيل</th><th>الحالة</th><th>{manager?'القرار':'وقت القرار'}</th></tr></thead><tbody>{requests.map(r=><tr key={r.id}><td><code>{r.id.slice(0,8)}</code></td><td>{names[r.operation]||'عملية'}{r.payload?.bundle&&<p>فاتورة للمراجعة: {(r.payload.lines||[]).length} صنف • {r.payload.currency||'حسب العملية'}{(r.payload.lines||[]).map((line,i)=><span key={i} style={{display:'block'}}>{catalog.find(p=>p.id===line.product_id)?.code||'عملية'} — الكمية {format(line.quantity||0)}{line.unit_cost!=null?' — تكلفة الوحدة '+format(line.unit_cost):''}</span>)}</p>}{r.payload?.sandbox&&<dl>{Object.entries(r.payload.data||{}).map(([k,v])=><React.Fragment key={k}><dt>{{quantity:'الكمية',product_id:'الصنف',sale_id:'فاتورة البيع',unit_cost:'تكلفة العبوة',bonus:'البونص',discount:'الخصم',expiry:'الصلاحية',expected_quantity:'الرصيد السابق'}[k]||k}</dt><dd>{k==='product_id'?(catalog.find(p=>p.id===v)?.code||'صنف QA'):String(v)}</dd></React.Fragment>)}</dl>}</td><td>{({pending:'بانتظار القرار',approved:'موافق عليه',rejected:'مرفوض'})[r.status]||'غير معروفة'}</td><td>{manager&&r.status==='pending'?<div className="qaActions"><button disabled={busy||loading} onClick={()=>decide(r.id,true)}>موافقة وتنفيذ في QA</button><button disabled={busy||loading} onClick={()=>decide(r.id,false)}>رفض</button></div>:r.decided_at?new Date(r.decided_at).toLocaleString('ar-SY'):'—'}</td></tr>)}</tbody></table></div>{!loading&&!requests.length&&<p>لا توجد طلبات.</p>}</section>
  <section className="qaPanel"><h2>المستندات المنفّذة</h2><div className="qaTable"><table><thead><tr><th>رقم المستند</th><th>النوع</th><th>الكمية</th><th>القيمة</th></tr></thead><tbody>{documents.map(d=><tr key={d.id}><td><code>{d.id.slice(0,8)}</code></td><td>{names[d.kind]}</td><td>{format(d.quantity)}</td><td>{format(d.total)} {d.currency||''}</td></tr>)}</tbody></table></div></section>
  {allowPasswordChange&&<section className="qaPanel" id="qa-account"><h2>تعيين كلمة مرور حساب QA</h2><p>يخص الحساب التجريبي الذي سجّلت الدخول به. اختر كلمة فريدة من 12 محرفاً على الأقل.</p><form className="qaForm" onSubmit={changePassword}><label>كلمة المرور الجديدة<input type="password" autoComplete="new-password" minLength="12" maxLength="128" required value={password} onChange={e=>setPassword(e.target.value)}/></label><label>تأكيد كلمة المرور<input type="password" autoComplete="new-password" minLength="12" maxLength="128" required value={confirmation} onChange={e=>setConfirmation(e.target.value)}/></label><button disabled={busy} className="qaPrimary">تعيين كلمة المرور</button></form></section>}
  {manager&&report&&<section className="qaPanel"><h2>الحسابات الاصطناعية — فصل العملات</h2><div className="qaCatalog">{(report.balances||[]).map(b=><article key={b.kind+b.currency}><span>{b.kind==='cash'?'الصندوق النقدي':'دين المورد الاصطناعي'}</span><h3>{format(b.amount)} {b.currency}</h3></article>)}{(report.profit||[]).map(p=><article key={p.currency}><span>مجمل الربح من تكلفة الدفعات</span><h3>{format(p.amount)} {p.currency}</h3></article>)}</div><p>الزيادات اليدوية في الجرد تسجّل بتكلفة صفر داخل هذا المختبر؛ لذلك لا تُستخدم تقاريره لتقييم أرباح الصيدلية.</p></section>}
 </main>;
}
