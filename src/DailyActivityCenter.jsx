import React,{useEffect,useMemo,useState} from 'react';
import './DAILY_ACTIVITY_CENTER.css';
const sources=[
 ['sales_rows','sale','فواتير البيع'],['purchase_rows','purchase','فواتير الشراء'],['return_rows','return','المرتجعات'],['debt_rows','debt','حركات المتدينين'],['cashbox_rows','cash','حركات الصندوق'],['supplier_payment_rows','supplier','دفعات الموردين'],['supplier_payments_rows','supplier','دفعات الموردين'],['inventory_rows','stock','حركات المخزون'],['audit_rows','audit','سجل التدقيق']
];
const label={sale:'بيع',purchase:'شراء',return:'مرتجع',debt:'حركة دين',cash:'حركة صندوق',supplier:'دفعة مورد',stock:'مخزون',audit:'تدقيق',inventory_count:'جرد',cash_count:'مطابقة صندوق',order:'طلب',prescription:'وصفة',medicine_request:'طلب دواء'};
const fmt=n=>new Intl.NumberFormat('en-US',{maximumFractionDigits:2}).format(Number(n)||0);
const when=x=>{const d=new Date(x);return Number.isNaN(d.getTime())?'غير مسجل':new Intl.DateTimeFormat('en-GB',{dateStyle:'short',timeStyle:'medium'}).format(d)};
const scalar=x=>x==null?'—':typeof x==='boolean'?(x?'نعم':'لا'):typeof x==='object'?JSON.stringify(x):String(x);
export default function DailyActivityCenter({supabase}){
 const [date,setDate]=useState(()=>{const d=new Date();return [d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-')});
 const [detailData,setDetailData]=useState(null); const [loaded,setLoaded]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[type,setType]=useState('all'),[search,setSearch]=useState(''),[detail,setDetail]=useState(null);
 const [offset,setOffset]=useState(0),[total,setTotal]=useState(0),[partial,setPartial]=useState(false);
 const load=async(more=false)=>{
 if(!/^\d{4}-\d{2}-\d{2}$/.test(date))return setError('اختر تاريخاً صحيحاً');
 setBusy(true);setError('');if(!more){setDetail(null);setOffset(0)}
 try{
 const start=new Date(date+'T00:00:00');
 if(Number.isNaN(start.getTime())||start.getFullYear()!==Number(date.slice(0,4))||start.getMonth()+1!==Number(date.slice(5,7))||start.getDate()!==Number(date.slice(8,10)))throw Error('التاريخ غير صالح');
 const end=new Date(start);end.setDate(end.getDate()+1);
 const nextOffset=more?offset:0;
 setPartial(false);
 const {data,error:e}=await supabase.rpc('admin_daily_activity_v1',{p_start:start.toISOString(),p_end:end.toISOString(),p_limit:500,p_offset:nextOffset});
 if(e){
 if(e.code==='PGRST202'||/schema cache|Could not find the function/i.test(e.message||'')){
  if(more)return;
  const fallback=await supabase.rpc('admin_accounting_report',{p_start:start.toISOString(),p_end:end.toISOString(),p_compare_start:null,p_compare_end:null});
  if(fallback.error)throw new Error('تعذر تحميل التقرير الاحتياطي: '+fallback.error.message);
  const report=fallback.data||{};
  const events=sources.flatMap(([field,kind])=>(Array.isArray(report[field])?report[field]:[]).map((item,i)=>({key:field+':'+(item.id||i),kind,source:field,item,at:item.created_at||item.invoice_date||item.sale_date||item.date||null})));
  events.sort((a,b)=>String(b.at||'').localeCompare(String(a.at||'')));
  setLoaded({date,events});setTotal(events.length);setOffset(events.length);setPartial(true);
  return;
 }
 throw e;
}
 if(!data||!Array.isArray(data.events))throw Error('استجابة غير صحيحة من مركز الحركة');
 const newEvents=data.events.map((x,i)=>({key:x.kind+':'+x.id+':'+(nextOffset+i),kind:x.kind,source:x.kind,item:x.details||{},at:x.occurred_at}));
 setLoaded(old=>({date,events:more&&old?.date===date?[...old.events,...newEvents]:newEvents}));
 setOffset(nextOffset+newEvents.length);setTotal(Number(data.total)||0);
 }catch(e){setError(e.message||'تعذر تحميل الحركة');if(!more)setLoaded(null)}finally{setBusy(false)}
 };
 useEffect(()=>{load()},[]);
 const rows=useMemo(()=>loaded?.events||[],[loaded]);
 const [detailBusy,setDetailBusy]=useState(false),[detailWarning,setDetailWarning]=useState('');
 const openDetail=async row=>{
  setDetail(row);setDetailWarning('');setDetailBusy(true);
  const raw=row.item||{};
  setDetailData({header:raw,items:Array.isArray(raw.items)?raw.items:[]});
  const id=raw.id||raw.sale_id||raw.purchase_id;
  try{
   if(row.kind==='purchase'&&id){
    const {data,error}=await supabase.rpc('admin_get_purchase_detail_currency',{p_purchase_id:id});
    if(error)throw error;
    if(data){
     const header=data.purchase||data.invoice||data;
     const items=data.items||data.purchase_items||header.items||[];
     setDetailData({header:{...raw,...header},items:Array.isArray(items)?items:[]});
    }
   }else if(row.kind==='sale'&&id){
    const start=new Date(date+'T00:00:00').toISOString();
    const [sales,lines]=await Promise.all([supabase.rpc('admin_list_sales',{p_start:start}),supabase.rpc('admin_list_sale_items',{p_start:start})]);
    if(sales.error)throw sales.error;if(lines.error)throw lines.error;
    const full=(Array.isArray(sales.data)?sales.data:[]).find(x=>String(x.id)===String(id));
    const items=(Array.isArray(lines.data)?lines.data:[]).filter(x=>String(x.sale_id)===String(id));
    if(full||items.length)setDetailData({header:{...raw,...(full||{})},items});
    if(!full||!items.length)setDetailWarning('بعض تفاصيل الفاتورة غير متاحة من الدوال الحالية. لا تعتبر البيانات المعروضة كشفاً كاملاً.');
    else setDetailWarning('قد تعرض دالة أصناف البيع الكميات المتبقية بعد المرتجعات، وليس الكميات الأصلية وقت البيع.');
   }
  }catch(e){setDetailWarning('تعذّر استكمال تفاصيل الفاتورة من المصدر: '+(e.message||'خطأ غير معروف'))}
  finally{setDetailBusy(false)}
 };
 const money=(v,c)=>v==null?'غير مسجل':fmt(v)+' '+(c||'عملة غير محددة');
 const field=(obj,keys)=>keys.map(k=>obj?.[k]).find(v=>v!==undefined&&v!==null&&v!=='');
 const fields=[['رقم الفاتورة',['invoice_number','receipt_number','id']],['المورد / العميل',['supplier_name','debtor_name','customer_name']],['نوع الدفع',['payment_method','payment_type']],['حالة الفاتورة',['status']],['العملة',['currency','sale_currency']],['سعر الصرف',['fx_rate']],['المجموع قبل الخصم',['subtotal']],['خصم الفاتورة',['discount','discount_amount']],['الإجمالي النهائي',['total']],['المبلغ المدفوع',['paid_amount','amount_paid','paid']],['المبلغ المتبقي / الدين',['due_amount','remaining_amount','balance']],['الدفعة المقدمة / الزيادة',['advance_amount','overpayment','credit_amount']],['الملاحظات',['notes']]];
 const visible=rows.filter(x=>(type==='all'||x.kind===type)&&(!search||JSON.stringify(x.item).toLowerCase().includes(search.toLowerCase())));

 return <section className="dailyActivity" dir="rtl"><header className="dailyActivityHead"><div><h1>مركز الحركة اليومية</h1><p>سجل موحد للقراءة فقط: البيع والشراء والمرتجعات والصندوق والمخزون والجرد والتعديلات والحذف والطلبات.</p></div><div className="dailyActivityDate"><label>تاريخ الحركة<input type="date" value={date} onChange={e=>setDate(e.target.value)}/></label><button className="primary" disabled={busy} onClick={()=>load(false)}>{busy?'جارٍ التحميل…':'عرض الحركة'}</button></div></header>
 {error&&<div className="error">{error}</div>}
 {loaded&&<>{partial&&<div className="dailyActivityNotice" role="status"><strong>عرض جزئي فقط:</strong> الدالة الشاملة غير مثبتة على هذه القاعدة. يتم عرض الحركات المتاحة من التقرير المحاسبي الحالي؛ لا يشمل هذا العرض بالضرورة جميع عمليات التعديل والحذف والجرد أو تفاصيل الأصناف. لا تعتمد عليه كسجل تدقيق كامل.</div>}<div className="dailyActivityCards">{[['فواتير البيع',rows.filter(x=>x.kind==='sale').length,'حركة'],['فواتير الشراء',rows.filter(x=>x.kind==='purchase').length,'حركة'],['المرتجعات',rows.filter(x=>x.kind==='return').length,'حركة'],['حركات الصندوق',rows.filter(x=>x.kind==='cash').length,'حركة']].map(([name,value,currency])=><div className="card" key={name}><small>{name}</small><strong>{value==null?'غير متاح':fmt(value)+' '+currency}</strong></div>)}</div>
 <div className="card dailyActivityControls"><select aria-label="نوع الحركة" value={type} onChange={e=>setType(e.target.value)}><option value="all">جميع الحركات</option>{[...new Set([...sources.map(x=>x[1]),'inventory_count','cash_count','order','prescription','medicine_request'])].map(k=><option value={k} key={k}>{label[k]}</option>)}</select><input placeholder="بحث برقم الفاتورة أو الاسم أو المرجع" value={search} onChange={e=>setSearch(e.target.value)}/><span>{visible.length} حركة معروضة من أصل {total}</span></div>
 <p className="dailyActivityNotice">المصدر: {partial?'التقرير المحاسبي الجزئي':'السجلات الأصلية عبر دالة قراءة إدارية'}. المبالغ والعملات لا تُحوّل أو تُجمع بين العملات. الحركات القديمة غير المسجلة أصلاً لا يمكن استعادتها.</p>
 <div className="card dailyActivityTable"><table><thead><tr><th>التاريخ والساعة</th><th>نوع الحركة</th><th>المرجع</th><th>القيمة</th><th>الإجراء</th></tr></thead><tbody>{visible.map(x=><tr key={x.key}><td>{when(x.at)}</td><td>{label[x.kind]}</td><td>{scalar(x.item.invoice_number||x.item.sale_id||x.item.purchase_id||x.item.id||x.item.description)}</td><td>{x.item.total!=null||x.item.amount!=null?fmt(x.item.total??x.item.amount)+' '+scalar(x.item.currency||'عملة غير محددة'):'—'}</td><td><button type="button" onClick={()=>openDetail(x)}>تفاصيل</button></td></tr>)}</tbody></table>{!visible.length&&<p>لا توجد حركات ضمن البيانات المتاحة للتاريخ والتصفية المحددين.</p>}{offset<total&&<button type="button" disabled={busy} onClick={()=>load(true)}>{busy?'جارٍ التحميل…':'تحميل 500 حركة إضافية'}</button>}</div></>}
 {detail&&<div className="dailyActivityModal" role="dialog" aria-modal="true" aria-label="تفاصيل الحركة" onClick={e=>{if(e.target===e.currentTarget)setDetail(null)}}><div className="dailyActivityDialog card">
 <header className="dailyActivityDialogHead"><div><small>مركز الحركة اليومية / {label[detail.kind]||detail.kind}</small><h2>{detail.kind==='sale'?'تفاصيل فاتورة البيع':detail.kind==='purchase'?'تفاصيل فاتورة الشراء':'تفاصيل الحركة'}</h2><p>{when(detail.at)}</p></div><button type="button" onClick={()=>setDetail(null)} aria-label="إغلاق">×</button></header>
 {detailBusy&&<p role="status">جارٍ جلب تفاصيل العملية من سجلات النظام…</p>}
 {detailWarning&&<div className="dailyActivityNotice" role="status">{detailWarning}</div>}
 {detailData&&<><section className="dailyActivityDetailSection"><h3>بيانات العملية والدفع</h3><div className="dailyActivityFacts">{fields.map(([name,keys])=>{const value=field(detailData.header,keys);return <div className="dailyActivityFact" key={name}><small>{name}</small><strong>{value==null?'غير مسجل':scalar(value)}</strong></div>})}</div></section>
 <section className="dailyActivityDetailSection"><h3>أصناف {detail.kind==='sale'?'البيع':detail.kind==='purchase'?'الشراء':'الحركة'} ({detailData.items.length})</h3>{detailData.items.length?<div className="dailyActivityTable"><table><thead><tr><th>#</th><th>الصنف</th><th>الكمية</th><th>سعر الوحدة</th><th>الخصم</th><th>الإجمالي</th><th>الصلاحية / الدفعة</th></tr></thead><tbody>{detailData.items.map((item,i)=><tr key={item.id||i}><td>{i+1}</td><td>{scalar(field(item,['product_name','name_ar','name','product_id']))}</td><td>{scalar(field(item,['quantity','qty']))}</td><td>{scalar(field(item,['unit_price','purchase_price','price']))}</td><td>{scalar(field(item,['discount','discount_amount']))}</td><td>{scalar(field(item,['total','line_total','subtotal']))}</td><td>{scalar(field(item,['expiry_date','batch_number','batch_id']))}</td></tr>)}</tbody></table></div>:<p className="dailyActivityNotice">لا توجد أصناف مفصلة في البيانات المتاحة لهذه الحركة.</p>}</section>
 {detail.kind==='audit'&&detailData.header.details?.before&&<section className="dailyActivityDetailSection"><h3>التعديل: قبل وبعد</h3><div className="dailyActivityTable"><table><thead><tr><th>الحقل</th><th>قبل</th><th>بعد</th></tr></thead><tbody>{Object.keys(detailData.header.details.before).map(k=><tr key={k}><td>{k}</td><td>{scalar(detailData.header.details.before[k])}</td><td>{scalar(detailData.header.details.after?.[k])}</td></tr>)}</tbody></table></div></section>}
 <section className="dailyActivityDetailSection"><h3>معلومات إضافية مسجلة</h3><dl>{Object.entries(detailData.header).filter(([k])=>k!=='items'&&k!=='details').map(([k,v])=><React.Fragment key={k}><dt>{k}</dt><dd>{scalar(v)}</dd></React.Fragment>)}</dl></section></>}
 <footer className="dailyActivityDialogFooter"><button type="button" onClick={()=>setDetail(null)}>إغلاق التفاصيل</button></footer></div></div>}

 </section>
}