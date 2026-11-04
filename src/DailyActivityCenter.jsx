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
    const allSales=Array.isArray(sales.data)?sales.data:[];
    const full=allSales.find(x=>String(x.id)===String(id));
    const items=(Array.isArray(lines.data)?lines.data:[]).filter(x=>String(x.sale_id)===String(id));
    let assignedNumber=null;
    const numberResponse=await supabase.rpc('admin_get_sale_invoice_number_v1',{p_sale_id:id});
    if(!numberResponse.error)assignedNumber=numberResponse.data;
    if(full||items.length)setDetailData({header:{...raw,...(full||{}),currency:full?.currency||raw.currency||'SYP',daily_sale_number:assignedNumber||raw.daily_sale_number},items});
    if(!full||!items.length)setDetailWarning('بعض تفاصيل الفاتورة غير متاحة من الدوال الحالية. لا تعتبر البيانات المعروضة كشفاً كاملاً.');
    else setDetailWarning((assignedNumber?'':'رقم الفاتورة التسلسلي لم يُفعّل بعد على قاعدة البيانات الحالية. ')+'قد تعرض دالة أصناف البيع الكميات المتبقية بعد المرتجعات، وليس الكميات الأصلية وقت البيع.');
   }
  }catch(e){setDetailWarning('تعذّر استكمال تفاصيل الفاتورة من المصدر: '+(e.message||'خطأ غير معروف'))}
  finally{setDetailBusy(false)}
 };
 const money=(v,c)=>v==null?'غير مسجل':fmt(v)+' '+(c==='SYP'?'ل.س':c==='USD'?'
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
 <header className="dailyActivityDialogHead"><div><small>مركز الحركة اليومية</small><h2>{detail.kind==='sale'?'فاتورة بيع':detail.kind==='purchase'?'فاتورة شراء':label[detail.kind]||'تفاصيل الحركة'}</h2><p>{when(detail.at)}</p></div><button type="button" onClick={()=>setDetail(null)} aria-label="إغلاق">×</button></header>
 {detailBusy&&<p className="dailyActivityNotice" role="status">جارٍ تحميل تفاصيل الفاتورة…</p>}
 {detailWarning&&<p className="dailyActivityNotice" role="status">{detailWarning}</p>}
 {detailData&&(()=>{
 const h=detailData.header||{},isInvoice=detail.kind==='sale'||detail.kind==='purchase';
 const c=field(h,['currency','sale_currency','purchase_currency'])||(detail.kind==='sale'?'SYP':null);
 const invoiceNo=field(h,['invoice_number','sale_number','purchase_number','receipt_number','daily_sale_number']);
 const customer=field(h,['supplier_name','debtor_name','customer_name']);
 const total=field(h,['total','grand_total','net_total']);
 const paid=field(h,['paid_amount','amount_paid','paid']);
 const due=field(h,['due_amount','remaining_amount','balance']);
 const payment=field(h,['payment_method','payment_type']);
 const info=[['رقم الفاتورة',invoiceNo],['الجهة',customer],['طريقة الدفع',payment],['حالة الفاتورة',field(h,['status'])],['العملة',c],['سعر الصرف',field(h,['fx_rate'])],['رقم الإيصال',field(h,['receipt_number'])],['الملاحظات',field(h,['notes'])]];
 const financial=[['المجموع قبل الخصم',field(h,['subtotal','gross_total'])],['الخصم',field(h,['discount','discount_amount'])],['الإجمالي النهائي',total],['المدفوع',paid],['المتبقي / الدين',due],['رصيد دائن / زيادة',field(h,['advance_amount','overpayment','credit_amount'])]];
 return <><section className="dailyActivityDetailSection">
 <div className="dailyActivitySummary"><div><small>إجمالي {isInvoice?'الفاتورة':'الحركة'}</small><strong>{money(total??field(h,['amount']),c)}</strong></div>{paid!=null&&<div><small>المدفوع</small><strong>{money(paid,c)}</strong></div>}{due!=null&&<div><small>المتبقي</small><strong>{money(due,c)}</strong></div>}</div>
 <div className="dailyActivityCompactFacts">{info.filter(([,v])=>v!=null).map(([k,v])=><div key={k}><span>{k}</span><b>{scalar(v)}</b></div>)}</div>
 </section>
 {isInvoice&&<section className="dailyActivityDetailSection"><h3>الأصناف ({detailData.items.length})</h3>{detailData.items.length?<div className="dailyActivityTable"><table><thead><tr><th>#</th><th>الصنف</th><th>الكمية</th><th>سعر الوحدة</th><th>الخصم</th><th>الإجمالي</th></tr></thead><tbody>{detailData.items.map((item,i)=><tr key={item.id||i}><td>{i+1}</td><td>{scalar(field(item,['product_name','name_ar','name','product_id']))}</td><td>{scalar(field(item,['quantity','qty']))}</td><td>{scalar(field(item,['unit_price','purchase_price','price']))}</td><td>{scalar(field(item,['discount','discount_amount']))}</td><td>{scalar(field(item,['total','line_total','subtotal']))}</td></tr>)}</tbody></table></div>:<p className="dailyActivityNotice">تفاصيل الأصناف غير متاحة من المصدر الحالي.</p>}</section>}
 {financial.some(([,v])=>v!=null)&&<section className="dailyActivityDetailSection"><h3>الحساب والدفع</h3><div className="dailyActivityCompactFacts">{financial.filter(([,v])=>v!=null).map(([k,v])=><div key={k}><span>{k}</span><b>{money(v,c)}</b></div>)}</div></section>}
 {detail.kind==='audit'&&h.details?.before&&<section className="dailyActivityDetailSection"><h3>تفاصيل التعديل</h3><div className="dailyActivityCompactFacts"><div><span>نوع العملية</span><b>{scalar(h.action)}</b></div><div><span>القسم</span><b>{scalar(h.entity_type)}</b></div></div><div className="dailyActivityTable"><table><thead><tr><th>الحقل</th><th>قبل</th><th>بعد</th></tr></thead><tbody>{Object.keys(h.details.before).map(k=><tr key={k}><td>{k}</td><td>{scalar(h.details.before[k])}</td><td>{scalar(h.details.after?.[k])}</td></tr>)}</tbody></table></div></section>}
 {!isInvoice&&detail.kind!=='audit'&&<section className="dailyActivityDetailSection"><h3>بيانات الحركة</h3><div className="dailyActivityCompactFacts">{Object.entries(h).filter(([k,v])=>!['items','details','id','created_at','updated_at'].includes(k)&&v!=null&&typeof v!=='object').slice(0,16).map(([k,v])=><div key={k}><span>{k}</span><b>{scalar(v)}</b></div>)}</div></section>}
 </>})()}
 <footer className="dailyActivityDialogFooter"><button type="button" onClick={()=>setDetail(null)}>إغلاق</button></footer></div></div>}

 </section>
}:c||'عملة غير محددة');
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
 <header className="dailyActivityDialogHead"><div><small>مركز الحركة اليومية</small><h2>{detail.kind==='sale'?'فاتورة بيع':detail.kind==='purchase'?'فاتورة شراء':label[detail.kind]||'تفاصيل الحركة'}</h2><p>{when(detail.at)}</p></div><button type="button" onClick={()=>setDetail(null)} aria-label="إغلاق">×</button></header>
 {detailBusy&&<p className="dailyActivityNotice" role="status">جارٍ تحميل تفاصيل الفاتورة…</p>}
 {detailWarning&&<p className="dailyActivityNotice" role="status">{detailWarning}</p>}
 {detailData&&(()=>{
 const h=detailData.header||{},isInvoice=detail.kind==='sale'||detail.kind==='purchase';
 const c=field(h,['currency','sale_currency','purchase_currency'])||(detail.kind==='sale'?'SYP':null);
 const invoiceNo=field(h,['invoice_number','sale_number','purchase_number','receipt_number','daily_sale_number']);
 const customer=field(h,['supplier_name','debtor_name','customer_name']);
 const total=field(h,['total','grand_total','net_total']);
 const paid=field(h,['paid_amount','amount_paid','paid']);
 const due=field(h,['due_amount','remaining_amount','balance']);
 const payment=field(h,['payment_method','payment_type']);
 const info=[['رقم الفاتورة',invoiceNo],['الجهة',customer],['طريقة الدفع',payment],['حالة الفاتورة',field(h,['status'])],['العملة',c],['سعر الصرف',field(h,['fx_rate'])],['رقم الإيصال',field(h,['receipt_number'])],['الملاحظات',field(h,['notes'])]];
 const financial=[['المجموع قبل الخصم',field(h,['subtotal','gross_total'])],['الخصم',field(h,['discount','discount_amount'])],['الإجمالي النهائي',total],['المدفوع',paid],['المتبقي / الدين',due],['رصيد دائن / زيادة',field(h,['advance_amount','overpayment','credit_amount'])]];
 return <><section className="dailyActivityDetailSection">
 <div className="dailyActivitySummary"><div><small>إجمالي {isInvoice?'الفاتورة':'الحركة'}</small><strong>{money(total??field(h,['amount']),c)}</strong></div>{paid!=null&&<div><small>المدفوع</small><strong>{money(paid,c)}</strong></div>}{due!=null&&<div><small>المتبقي</small><strong>{money(due,c)}</strong></div>}</div>
 <div className="dailyActivityCompactFacts">{info.filter(([,v])=>v!=null).map(([k,v])=><div key={k}><span>{k}</span><b>{scalar(v)}</b></div>)}</div>
 </section>
 {isInvoice&&<section className="dailyActivityDetailSection"><h3>الأصناف ({detailData.items.length})</h3>{detailData.items.length?<div className="dailyActivityTable"><table><thead><tr><th>#</th><th>الصنف</th><th>الكمية</th><th>سعر الوحدة</th><th>الخصم</th><th>الإجمالي</th></tr></thead><tbody>{detailData.items.map((item,i)=><tr key={item.id||i}><td>{i+1}</td><td>{scalar(field(item,['product_name','name_ar','name','product_id']))}</td><td>{scalar(field(item,['quantity','qty']))}</td><td>{scalar(field(item,['unit_price','purchase_price','price']))}</td><td>{scalar(field(item,['discount','discount_amount']))}</td><td>{scalar(field(item,['total','line_total','subtotal']))}</td></tr>)}</tbody></table></div>:<p className="dailyActivityNotice">تفاصيل الأصناف غير متاحة من المصدر الحالي.</p>}</section>}
 {financial.some(([,v])=>v!=null)&&<section className="dailyActivityDetailSection"><h3>الحساب والدفع</h3><div className="dailyActivityCompactFacts">{financial.filter(([,v])=>v!=null).map(([k,v])=><div key={k}><span>{k}</span><b>{money(v,c)}</b></div>)}</div></section>}
 {detail.kind==='audit'&&h.details?.before&&<section className="dailyActivityDetailSection"><h3>تفاصيل التعديل</h3><div className="dailyActivityCompactFacts"><div><span>نوع العملية</span><b>{scalar(h.action)}</b></div><div><span>القسم</span><b>{scalar(h.entity_type)}</b></div></div><div className="dailyActivityTable"><table><thead><tr><th>الحقل</th><th>قبل</th><th>بعد</th></tr></thead><tbody>{Object.keys(h.details.before).map(k=><tr key={k}><td>{k}</td><td>{scalar(h.details.before[k])}</td><td>{scalar(h.details.after?.[k])}</td></tr>)}</tbody></table></div></section>}
 {!isInvoice&&detail.kind!=='audit'&&<section className="dailyActivityDetailSection"><h3>بيانات الحركة</h3><div className="dailyActivityCompactFacts">{Object.entries(h).filter(([k,v])=>!['items','details','id','created_at','updated_at'].includes(k)&&v!=null&&typeof v!=='object').slice(0,16).map(([k,v])=><div key={k}><span>{k}</span><b>{scalar(v)}</b></div>)}</div></section>}
 </>})()}
 <footer className="dailyActivityDialogFooter"><button type="button" onClick={()=>setDetail(null)}>إغلاق</button></footer></div></div>}

 </section>
}