import React,{useState,useEffect,useRef} from 'react';

const kinds={sale:'بيع',purchase_draft:'شراء',inventory_count:'جرد',return_request:'مرتجع',order_process:'معالجة طلب'};
const initial={return_days:30,return_behavior:'warn',paused_operation:'',minutes:30,reason:''};
const reportsKey='pharmacy_qa_custom_report_v1';
const permitted=role=>['system_owner','system_admin'].includes(role);
const safeDate=value=>/^\d{4}-\d{2}-\d{2}$/.test(value||'')?value:'';
const number=value=>new Intl.NumberFormat('en-US',{maximumFractionDigits:4}).format(value);

async function rpc(client, name, args) {
 const {data,error}=await client.rpc(name,args);
 if(error)throw error;
 return data;
}

function Settings({client, emergency=false}) {
 const [history,setHistory]=useState(null),[draft,setDraft]=useState(initial);
 const [message,setMessage]=useState(''),[busy,setBusy]=useState(false);
 const lock=useRef(false);
 async function load() {
  const rows=await rpc(client,'qa_operating_controls');
  setHistory(rows);
  setDraft({...initial,...rows[0],paused_operation:rows[0]?.paused_operation||'',reason:''});
 }
 useEffect(()=>{load().catch(()=>setMessage('تعذر تحميل إعدادات التشغيل.'));},[client]);
 const set=(key,value)=>setDraft(previous=>({...previous,[key]:value}));
 async function save(event) {
  event.preventDefault();
  if(!history||lock.current)return;
  lock.current=true;setBusy(true);setMessage('');
  try {
   const current=history[0];
   // Never extend an existing pause while editing the return policy.
   await rpc(client,'qa_save_operating_controls',{
    p_expected_version:current?.version??0,
    p_return_days:Number(draft.return_days),
    p_return_behavior:draft.return_behavior,
    p_paused_operation:emergency?(draft.paused_operation||null):null,
    p_minutes:emergency?(draft.paused_operation?Number(draft.minutes):null):-1,
    p_reason:draft.reason,
   });
   await load();setMessage('حُفظ إصدار جديد من الإعدادات.');
  } catch(error) {
   setMessage(error.code==='40001'?'تغيّرت الإعدادات. أعد تحميلها قبل الحفظ.':'تعذر تأكيد الحفظ. أعد تحميل الإعدادات.');
  } finally {lock.current=false;setBusy(false);}
 }
 const activePause=history?.[0]?.paused_operation&&Date.parse(history[0].paused_until)>Date.now();
 return <form className="adminSettingsCard adminToolsPanel" onSubmit={save}>
  <h4>{emergency?'وضع الطوارئ الانتقائي':'سياسات التشغيل'}</h4>
  {emergency?<><p>{activePause?('متوقف: '+kinds[history[0].paused_operation]+' حتى '+new Date(history[0].paused_until).toLocaleString('ar-SY')):'العمليات متاحة.'}</p>
   <label>العملية<select value={draft.paused_operation} onChange={e=>set('paused_operation',e.target.value)}><option value="">إتاحة جميع العمليات</option>{Object.entries(kinds).map(([key,name])=><option key={key} value={key}>{name}</option>)}</select></label>
   {draft.paused_operation&&<label>المدة بالدقائق<input type="number" required min={1} max={1440} value={draft.minutes} onChange={e=>set('minutes',e.target.value)}/></label>}
  </>:<><label>مهلة المرتجع بالأيام<input type="number" required min={0} max={365} value={draft.return_days} onChange={e=>set('return_days',e.target.value)}/></label>
   <label>الإجراء بعد المهلة<select value={draft.return_behavior} onChange={e=>set('return_behavior',e.target.value)}><option value="warn">تسجيل تنبيه في سجل العملية</option><option value="block">منع المرتجع</option><option value="approve">اعتماد المدير</option></select></label>
   <p>سقف الخصم والدين مرتبطان بتفعيل مساري الخصم والبيع الآجل على QA.</p>
  </>}
  <label>سبب التغيير<input required minLength={3} maxLength={400} value={draft.reason} onChange={e=>set('reason',e.target.value)}/></label>
  <div className="adminToolsActions"><button type="submit" disabled={busy||!history}>اعتماد الإعدادات</button>
   <button type="button" className="secondaryAction" disabled={busy} onClick={()=>load().catch(()=>setMessage('تعذر إعادة التحميل.'))}>إعادة التحميل</button></div>
  {message&&<p role="status">{message}</p>}
  {!!history?.length&&<details><summary>سجل الإصدارات</summary><ul>{history.map(row=><li key={row.version}>#{row.version} · {new Date(row.created_at).toLocaleString('ar-SY')} · {row.return_days} يوم · {row.return_behavior} · {kinds[row.paused_operation]||'متاح'} · {row.reason}{!emergency&&<button type="button" className="secondaryAction" onClick={()=>setDraft(current=>({...current,return_days:row.return_days,return_behavior:row.return_behavior,reason:''}))}>استرجاع الإعدادات للمعاينة</button>}</li>)}</ul></details>}
 </form>;
}

function SnapshotTool({client, kind}) {
 const [snapshot,setSnapshot]=useState(null),[error,setError]=useState(''),[busy,setBusy]=useState(false);
 const [id,setId]=useState(''),[impact,setImpact]=useState(null);
 const [filters,setFilters]=useState(()=>{
  try{const saved=JSON.parse(localStorage.getItem(reportsKey));return {currency:['USD','SYP'].includes(saved?.currency)?saved.currency:'',kind:kinds[saved?.kind]?saved.kind:'',from:safeDate(saved?.from),to:safeDate(saved?.to)};}
  catch{return {currency:'',kind:'',from:'',to:''};}
 });
 async function load() {
  setBusy(true);setError('');setImpact(null);
  try {
   const data=await rpc(client,'qa_workspace_snapshot');
   if(!permitted(data?.role)||!Array.isArray(data.documents)) throw Error();
   setSnapshot(data);
  } catch {setSnapshot(null);setError('تعذر قراءة سجل QA.');}
  finally{setBusy(false);}
 }
 async function inspect() {
  setBusy(true);setError('');setImpact(null);
  try{setImpact(await rpc(client,'qa_operation_impact',{p_document:id}));}
  catch{setError('تعذر عرض أثر العملية.');}
  finally{setBusy(false);}
 }
 const doc=(snapshot?.documents||[]).filter(row=>{
  if(kind!=='reports')return true;
  const date=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Damascus',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(row.created_at));
  return (!filters.currency||row.currency===filters.currency)&&(!filters.kind||row.kind===filters.kind)&&
   (!filters.from||date>=filters.from)&&(!filters.to||date<=filters.to);
 });
 const field=(name,value)=>setFilters(previous=>({...previous,[name]:value}));
 return <div className="adminSettingsCard adminToolsPanel">
  <button type="button" disabled={busy} onClick={load}>تحميل السجل</button>
  {error&&<p role="status">{error}</p>}
  {snapshot&&kind==='corrections'&&<>
   <label>العملية<select value={id} disabled={busy} onChange={e=>{setId(e.target.value);setImpact(null);}}>
    <option value="">اختر عملية</option>{doc.map(row=><option key={row.id} value={row.id}>{kinds[row.kind]||row.kind} · {row.id.slice(0,8)} · {row.total} {row.currency}</option>)}
   </select></label>
   <button type="button" disabled={busy||!id} onClick={inspect}>عرض الأثر والتبعيات</button>
   {impact&&<><p>الإجمالي {number(impact.total)} {impact.currency} · المرتجعات المرتبطة {impact.linked_returns}</p>
    {impact.ledger&&<p>{impact.ledger.kind==='cash'?'الصندوق':'دين المورد'} {number(impact.ledger.amount)} {impact.ledger.currency}</p>}
    <ul>{impact.movements.map(row=><li key={row.batch}>دفعة {row.batch.slice(0,8)} · حركة {row.quantity} · تكلفة الوحدة {row.cost} · حركات لاحقة {row.later_links}</li>)}</ul>
    <p>المراجعة للقراءة فقط. تنفيذ القيود التصحيحية يحتاج مساراً محاسبياً معتمداً.</p></>}
  </>}
  {snapshot&&kind==='integrations'&&<>
   <p>سجل معالجة الطلبات التجريبية</p>
   <ul>{(snapshot.requests||[]).filter(row=>row.operation==='order_process').map(row=><li key={row.id}>{row.id.slice(0,8)} · {({pending:'معلق',approved:'منفذ',rejected:'مرفوض'})[row.status]||row.status}</li>)}</ul>
   <p>ربط أخطاء الموقع وإعادة المعالجة يتطلبان سجل استقبال الطلبات.</p>
  </>}
  {snapshot&&kind==='reports'&&<>
   <label>العملة<select value={filters.currency} onChange={e=>field('currency',e.target.value)}><option value="">كل العملات</option><option>USD</option><option>SYP</option></select></label>
   <label>نوع العملية<select value={filters.kind} onChange={e=>field('kind',e.target.value)}><option value="">كل العمليات</option>{Object.entries(kinds).map(([key,name])=><option key={key} value={key}>{name}</option>)}</select></label>
   <label>من تاريخ<input type="date" value={filters.from} onChange={e=>field('from',e.target.value)}/></label>
   <label>إلى تاريخ<input type="date" value={filters.to} onChange={e=>field('to',e.target.value)}/></label>
   <button type="button" onClick={()=>{try{localStorage.setItem(reportsKey,JSON.stringify(filters));setError('حُفظت الفلاتر على هذا المتصفح.');}catch{setError('تعذر حفظ الفلاتر.');}}}>حفظ الفلاتر</button>
   {['USD','SYP'].map(currency=><section key={currency}><strong>{currency}</strong><ul>{Object.entries(kinds).map(([kind,name])=>{
    const rows=doc.filter(row=>row.currency===currency&&row.kind===kind);
    return <li key={kind}>{name} · {rows.length} · {number(rows.reduce((sum,row)=>sum+Number(row.total),0))}</li>;
   })}</ul></section>)}
   <details><summary>السجلات الداخلة في التقرير ({doc.length})</summary><ul>{doc.map(row=><li key={row.id}>{row.id.slice(0,8)} · {kinds[row.kind]||row.kind} · {row.total} {row.currency}</li>)}</ul></details>
  </>}
 </div>;
}

const exercises=[
 ['بيع آجل','ما نوع التسديد لفاتورة سيسددها الزبون لاحقاً؟','آجل','نقدي'],
 ['شراء','كيف تسجل 10 عبوات مدفوعة وعبوتين مجانيتين؟','10 كمية و2 بونص','12 عبوة مدفوعة'],
 ['جرد','وجدت 8 عبوات والسجل يقول 10. ماذا تسجّل في العد؟','8 عبوات','10 عبوات'],
 ['مرتجع','ما السجل الذي تربط به مرتجع الزبون؟','فاتورة البيع الأصلية','أحدث فاتورة شراء'],
];
function Training() {
 const [answers,setAnswers]=useState({});
 return <div className="adminSettingsCard adminToolsPanel">
  <p>تمارين قصيرة على بيانات اصطناعية.</p>
  {exercises.map(([name,question,right,wrong],i)=><fieldset key={name}>
   <legend>{name}</legend><p>{question}</p>
   {(i%2?[wrong,right]:[right,wrong]).map(answer=><button type="button" className="secondaryAction" key={answer} onClick={()=>setAnswers({...answers,[name]:answer===right})}>{answer}</button>)}
   {name in answers&&<p role="status">{answers[name]?'إجابة صحيحة.':'راجع الإجابة وحاول مرة ثانية.'}</p>}
  </fieldset>)}
  <p>الإجابات الصحيحة {Object.values(answers).filter(Boolean).length} / {exercises.length}</p>
 </div>;
}
export default function QaOperatingTools({client,kind}) {
 if(kind==='policy'||kind==='emergency')return <Settings key={kind} client={client} emergency={kind==='emergency'}/>;
 if(kind==='training')return <Training/>;
 return <SnapshotTool key={kind} client={client} kind={kind}/>;
}
