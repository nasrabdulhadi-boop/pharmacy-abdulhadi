import React,{useEffect,useMemo,useState} from 'react';
import './DAILY_ACTIVITY_CENTER.css';
const sources=[
 ['sales_rows','sale','فواتير البيع'],['purchase_rows','purchase','فواتير الشراء'],['return_rows','return','المرتجعات'],['debt_rows','debt','حركات المتدينين'],['cashbox_rows','cash','حركات الصندوق'],['supplier_payment_rows','supplier','دفعات الموردين'],['supplier_payments_rows','supplier','دفعات الموردين'],['inventory_rows','stock','حركات المخزون'],['audit_rows','audit','سجل التدقيق']
];
const label={sale:'بيع',purchase:'شراء',return:'مرتجع',debt:'حركة دين',cash:'حركة صندوق',supplier:'دفعة مورد',stock:'مخزون',audit:'تدقيق'};
const fmt=n=>new Intl.NumberFormat('en-US',{maximumFractionDigits:2}).format(Number(n)||0);
const when=x=>{const d=new Date(x);return Number.isNaN(d.getTime())?'غير مسجل':new Intl.DateTimeFormat('en-GB',{dateStyle:'short',timeStyle:'medium'}).format(d)};
const scalar=x=>x==null?'—':typeof x==='boolean'?(x?'نعم':'لا'):typeof x==='object'?JSON.stringify(x):String(x);
export default function DailyActivityCenter({supabase}){
 const [date,setDate]=useState(()=>{const d=new Date();return [d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-')});
 const [detailLoading,setDetailLoading]=useState(false),[detailError,setDetailError]=useState(''),[detailData,setDetailData]=useState(null); const [loaded,setLoaded]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[type,setType]=useState('all'),[search,setSearch]=useState(''),[detail,setDetail]=useState(null);
 const load=async()=>{if(!/^\\d{4}-\\d{2}-\\d{2}$/.test(date))return setError('اختر تاريخاً صحيحاً');setBusy(true);setError('');setDetail(null);try{const start=new Date(date+'T00:00:00');if(Number.isNaN(start.getTime())||start.getFullYear()!==Number(date.slice(0,4))||start.getMonth()+1!==Number(date.slice(5,7))||start.getDate()!==Number(date.slice(8,10)))throw Error('التاريخ غير صالح');const end=new Date(start);end.setDate(end.getDate()+1);const {data,error:e}=await supabase.rpc('admin_accounting_report',{p_start:start.toISOString(),p_end:end.toISOString(),p_compare_start:null,p_compare_end:null});if(e)throw e;if(!data||typeof data!=='object')throw Error('لا توجد استجابة صحيحة من التقرير');setLoaded({date,data})}catch(e){setError(e.message||'تعذر تحميل الحركة');setLoaded(null)}finally{setBusy(false)}};
 useEffect(()=>{load()},[]);
 const rows=useMemo(()=>{if(!loaded)return [];return sources.flatMap(([key,kind])=>(Array.isArray(loaded.data[key])?loaded.data[key]:[]).map((item,index)=>({key:kind+':'+key+':'+(item.id??index),kind,source:key,item,at:item.created_at||item.transaction_date||item.date||item.invoice_date||null}))).sort((a,b)=>new Date(b.at||0)-new Date(a.at||0))},[loaded]);
 const openDetail=async row=>{
 setDetail(row);setDetailData(null);setDetailError('');setDetailLoading(true);
 try{
  if(row.kind==='purchase'){
   const id=row.item.id||row.item.purchase_id;
   if(!id)throw Error('لا يوجد معرف فاتورة شراء موثوق');
   const {data,error}=await supabase.rpc('admin_get_purchase_detail_currency',{p_purchase_id:id});
   if(error)throw error;if(!data)throw Error('تعذر قراءة تفاصيل فاتورة الشراء بهذه الصلاحيات');
   setDetailData({kind:'purchase',header:data,items:Array.isArray(data.items)?data.items:[]});
  }else if(row.kind==='sale'){
   const id=row.item.id||row.item.sale_id;
   if(!id)throw Error('لا يوجد معرف فاتورة بيع موثوق');
   const start=new Date(loaded.date+'T00:00:00').toISOString();
   const [sr,ir]=await Promise.all([supabase.rpc('admin_list_sales',{p_start:start}),supabase.rpc('admin_list_sale_items',{p_start:start})]);
   if(sr.error)throw sr.error;if(ir.error)throw ir.error;
   const sale=(sr.data||[]).find(x=>x.id===id);
   if(!sale)throw Error('لم تظهر الفاتورة ضمن قائمة المبيعات المصرح بها (الحد 1000 فاتورة)');
   setDetailData({kind:'sale',header:sale,items:(ir.data||[]).filter(x=>x.sale_id===id),notice:'كميات الأصناف هنا هي الكميات المتبقية بعد المرتجعات، وقد لا تمثل الكميات الأصلية المباعة. التقرير محدود إلى 5000 بند.'});
  }else{
   setDetailData({kind:row.kind,header:row.item,items:Array.isArray(row.item.items)?row.item.items:[],notice:'تفاصيل هذه الحركة متاحة فقط بالحقول التي يعيدها التقرير المحاسبي.'});
  }
 }catch(e){setDetailError(e.message||'تعذر جلب تفاصيل الحركة')}finally{setDetailLoading(false)}
 };
 const visible=rows.filter(x=>(type==='all'||x.kind===type)&&(!search||JSON.stringify(x.item).toLowerCase().includes(search.toLowerCase())));
 const summary=loaded?.data?.summary||{};
 return <section className="dailyActivity" dir="rtl"><header className="dailyActivityHead"><div><h1>مركز الحركة اليومية</h1><p>عرض للقراءة فقط من التقرير المحاسبي المعتمد، دون تعديل أي فاتورة أو رصيد.</p></div><div className="dailyActivityDate"><label>تاريخ الحركة<input type="date" value={date} onChange={e=>setDate(e.target.value)}/></label><button className="primary" disabled={busy} onClick={load}>{busy?'جارٍ التحميل…':'عرض الحركة'}</button></div></header>
 {error&&<div className="error">{error}</div>}
 {loaded&&<><div className="dailyActivityCards">{[['المبيعات',summary.sales,'SYP'],['المشتريات',summary.purchases,'SYP'],['المقبوضات النقدية',summary.cash_in,'SYP'],['المدفوعات النقدية',summary.cash_out,'SYP']].map(([name,value,currency])=><div className="card" key={name}><small>{name}</small><strong>{value==null?'غير متاح':fmt(value)+' '+currency}</strong></div>)}</div>
 <div className="card dailyActivityControls"><select aria-label="نوع الحركة" value={type} onChange={e=>setType(e.target.value)}><option value="all">جميع الحركات</option>{[...new Set(sources.map(x=>x[1]))].map(k=><option value={k} key={k}>{label[k]}</option>)}</select><input placeholder="بحث برقم الفاتورة أو الاسم أو المرجع" value={search} onChange={e=>setSearch(e.target.value)}/><span>{visible.length} حركة معروضة</span></div>
 <p className="dailyActivityNotice">تُعرض الحركات التي يعيدها التقرير الحالي فقط. بعض العمليات (مثل الجرد والتدقيق ودفعات الموردين) قد لا تكون متاحة ضمن مصدر التقرير؛ عدم ظهورها لا يعني عدم حدوثها. تُعرض العملة بحسب بيانات السجل، ولا يُفترض أن كل مبلغ بالليرة.</p>
 <div className="card dailyActivityTable"><table><thead><tr><th>التاريخ والساعة</th><th>نوع الحركة</th><th>المرجع</th><th>القيمة</th><th>الإجراء</th></tr></thead><tbody>{visible.map(x=><tr key={x.key}><td>{when(x.at)}</td><td>{label[x.kind]}</td><td>{scalar(x.item.invoice_number||x.item.sale_id||x.item.purchase_id||x.item.id||x.item.description)}</td><td>{x.item.total!=null||x.item.amount!=null?fmt(x.item.total??x.item.amount)+' '+scalar(x.item.currency||'عملة غير محددة'):'—'}</td><td><button type="button" onClick={()=>openDetail(x)}>تفاصيل</button></td></tr>)}</tbody></table>{!visible.length&&<p>لا توجد حركات ضمن البيانات المتاحة للتاريخ والتصفية المحددين.</p>}</div></>}
 {detail&&<div className="dailyActivityModal" role="dialog" aria-modal="true" aria-label="تفاصيل الحركة"><div className="dailyActivityDialog card"><header><h2>تفاصيل {label[detail.kind]}</h2><button onClick={()=>setDetail(null)} aria-label="إغلاق">×</button></header><p>التاريخ والساعة: {when(detail.at)}</p><p>المصدر: {detail.source}</p>{detailLoading&&<p>جارٍ تحميل التفاصيل الأصلية…</p>}{detailError&&<p className="error">{detailError}</p>}{detailData&&<><h3>بيانات العملية الأصلية</h3><dl>{Object.entries(detailData.header||{}).filter(([k])=>k!=='items').map(([k,v])=><React.Fragment key={k}><dt>{k}</dt><dd>{scalar(v)}</dd></React.Fragment>)}</dl><h3>الأصناف المرتبطة ({detailData.items.length})</h3>{detailData.items.length?<div className="dailyActivityTable"><table><thead><tr><th>الصنف</th><th>الكمية</th><th>السعر</th><th>الدفعة / الصلاحية</th></tr></thead><tbody>{detailData.items.map((item,i)=><tr key={item.id||i}><td>{scalar(item.product_name||item.name||item.product_id)}</td><td>{scalar(item.quantity)}</td><td>{scalar(item.unit_price??item.purchase_price)}</td><td>{scalar(item.batch_number||item.expiry_date)}</td></tr>)}</tbody></table></div>:<p>لا توجد أصناف مفصلة متاحة من المصدر.</p>}{detailData.notice&&<p className="dailyActivityNotice">{detailData.notice}</p>}</>}<dl>{Object.entries(detail.item).map(([key,value])=><React.Fragment key={key}><dt>{key}</dt><dd>{scalar(value)}</dd></React.Fragment>)}</dl><p className="dailyActivityNotice">هذه هي التفاصيل المتاحة من مصدر التقرير فقط؛ أي أصناف أو أحداث غير مرجعة من المصدر لا يمكن عرضها هنا.</p><button onClick={()=>setDetail(null)}>إغلاق</button></div></div>}
 </section>
}