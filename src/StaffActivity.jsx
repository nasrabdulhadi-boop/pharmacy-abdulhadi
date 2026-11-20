import React,{useEffect,useState} from 'react';
const metrics={invoices:'فواتير البيع',sales:'المبيعات',profit:'ربح البيع قبل المرتجعات',credit:'الدين المسجّل عند البيع',collections:'تحصيل الديون',refunds:'مرتجعات العملاء المنفذة',purchase_count:'فواتير الشراء',purchase_value:'قيمة المشتريات'};
const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Damascus',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
export default function StaffActivity({client,revision}){
 const [start,setStart]=useState(today),[end,setEnd]=useState(today),[rows,setRows]=useState(null),[error,message]=useState(''),[reload,refresh]=useState(0);
 useEffect(()=>{let live=true;setRows(null);message('');
 if(!start||!end||start>end){message('تحقق من تاريخ بداية الفترة ونهايتها.');return;}
 client.rpc('manager_employee_activity',{p_start:start,p_end:end}).then(({data,error})=>{if(live){if(error)message('تعذّر تحميل تقرير الفترة. اختر فترة أقصاها سنة وحدّث التقرير.');else setRows(data);}});return()=>{live=false;};
 },[start,end,client,revision,reload]);
 return <section className="adminSettingsCard"><h3>مقارنة أداء الموظفين</h3><p>المبالغ بالليرة السورية، بحسب الحساب الذي سجّل العملية وتاريخها بتوقيت دمشق.</p><label>من <input type="date" value={start} onChange={e=>setStart(e.target.value)}/></label><label>إلى <input type="date" value={end} onChange={e=>setEnd(e.target.value)}/></label><button onClick={()=>refresh(n=>n+1)}>تحديث التقرير</button>
 {error?<p role="alert">{error}</p>:rows===null?<p>جارٍ تحميل التقرير…</p>:!rows.length?<p>يظهر التقرير هنا بعد إنشاء أول حساب موظف.</p>:rows.map(r=><article className="adminSettingsCard" key={r.id}><h4>{r.name} · <bdi>{r.email}</bdi></h4><dl className="permissionGrid">{Object.entries(metrics).map(([key,label])=><div key={key}><dt>{label}</dt><dd>{r[key]==null?'التكلفة غير مكتملة':Number(r[key]).toLocaleString('ar-SY')}</dd></div>)}</dl><details><summary>آخر الحركات المسجّلة خلال الفترة</summary>{r.events.length?r.events.map((e,i)=><p key={i}>{new Date(e.created_at).toLocaleString('ar-SY',{timeZone:'Asia/Damascus'})} · {e.action} · {e.entity_type}</p>):<p>لا توجد حركات في سجل التدقيق لهذه الفترة.</p>}</details></article>)}</section>;
}
