import React,{useEffect,useMemo,useState} from 'react';
import './DAILY_ACTIVITY_CENTER.css';
const sources=[['sales_rows','sale','فواتير البيع'],['purchase_rows','purchase','فواتير الشراء'],['supplier_payment_rows','supplier','دفعات الموردين'],['debt_rows','debt','تحصيل الديون'],['cashbox_rows','cash','السحب والإيداع'],['audit_rows','audit','التعديلات والحذف']];
const label={sale:'فاتورة بيع',purchase:'فاتورة شراء',return:'مرتجع',debt:'تحصيل دين',cash:'حركة صندوق مهمة',supplier:'دفعة مورد',audit:'تعديل أو حذف',inventory_count:'جرد معتمد'};
const actionNames={admin_update_product_price:'تعديل سعر منتج',admin_update_purchase_sale_currency:'تعديل عملة مبيع',admin_delete_purchase:'حذف فاتورة شراء',admin_delete_batch:'حذف دفعة مخزون',admin_delete_order:'حذف طلب',adjust_stock:'تعديل كمية مخزون',correct_usd_product_prices:'تصحيح أسعار',correct_erroneous_purchase_fx:'تصحيح سعر صرف',admin_dispose_stock:'إتلاف مخزون',supplier_credit_note:'إشعار دائن للمورد'};
const cashNames={withdrawal:'سحب من الصندوق',deposit:'إيداع في الصندوق',expense:'مصروف',income:'إيراد يدوي',adjustment:'تسوية صندوق'};
const movementName=x=>x.kind==='audit'?(actionNames[x.item.action]||'تعديل أو حذف: '+(x.item.action||'عملية')):x.kind==='cash'?(cashNames[x.item.entry_type]||'حركة صندوق مهمة'):label[x.kind]||'عملية مهمة';
const movementRef=x=>{
 const i=x.item||{};
 if(x.kind==='sale')return i.invoice_number!=null?'فاتورة بيع رقم '+String(i.invoice_number).padStart(2,'0'):'رقم فاتورة البيع غير متاح';
 if(x.kind==='purchase')return i.invoice_number||i.receipt_number?'فاتورة شراء رقم '+(i.invoice_number||i.receipt_number):'فاتورة شراء';
 if(x.kind==='audit')return actionNames[i.action]||'تغيير مسجل في '+(i.entity_type||'النظام');
 if(x.kind==='cash')return cashNames[i.entry_type]||'حركة صندوق';
 if(x.kind==='supplier')return 'دفعة مورد'+(i.supplier_name?' — '+i.supplier_name:'');
 if(x.kind==='debt')return 'تحصيل دين'+(i.debtor_name?' — '+i.debtor_name:'');
 if(x.kind==='inventory_count')return 'جرد مخزون';
 return label[x.kind]||'حركة';
};
const fmt=n=>new Intl.NumberFormat('en-US',{maximumFractionDigits:2}).format(Number(n)||0);
const when=x=>{const d=new Date(x);return Number.isNaN(d.getTime())?'غير مسجل':new Intl.DateTimeFormat('en-GB',{dateStyle:'short',timeStyle:'medium'}).format(d)};
const scalar=x=>x==null?'—':typeof x==='boolean'?(x?'نعم':'لا'):typeof x==='object'?JSON.stringify(x):String(x);
export default function DailyActivityCenter({supabase}){
 const [date,setDate]=useState(()=>{const d=new Date();return [d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-')});
 const [detailData,setDetailData]=useState(null); const [loaded,setLoaded]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[type,setType]=useState('all'),[search,setSearch]=useState(''),[detail,setDetail]=useState(null);
 const [offset,setOffset]=useState(0),[total,setTotal]=useState(0),[partial,setPartial]=useState(false);
 const [finance,setFinance]=useState(null),[financeError,setFinanceError]=useState(''),[invoiceNumberMap,setInvoiceNumberMap]=useState({}),[previousFinance,setPreviousFinance]=useState(null);
 const enrichSaleNumbers=async events=>{
  const ids=[...new Set(events.filter(e=>e.kind==='sale').map(e=>e.id||e.item?.sale_id||e.item?.id).filter(Boolean))];
  if(!ids.length)return events;
  const {data,error}=await supabase.rpc('admin_sale_invoice_numbers_v1',{p_sale_ids:ids});
  if(error||!data)throw new Error('تعذر التحقق من أرقام الفواتير: '+(error?.message||'استجابة فارغة'));
  const seen=new Set();
  for(const id of ids){const number=data[id];if(number==null)throw new Error('فاتورة بيع بلا رقم موثّق: '+id);if(seen.has(String(number)))throw new Error('تكرار رقم الفاتورة '+number+' لعدة فواتير؛ أُوقف العرض لحماية دقة البيانات');seen.add(String(number));}
  return events.map(e=>{const id=e.id||e.item?.sale_id||e.item?.id;return e.kind==='sale'?{...e,item:{...e.item,invoice_number:data[id]}}:e});
 };
 const load=async(more=false)=>{
 if(!/^\d{4}-\d{2}-\d{2}$/.test(date))return setError('اختر تاريخاً صحيحاً');
 setBusy(true);setError('');if(!more){setDetail(null);setOffset(0)}
 try{
 const start=new Date(date+'T00:00:00');
 if(Number.isNaN(start.getTime())||start.getFullYear()!==Number(date.slice(0,4))||start.getMonth()+1!==Number(date.slice(5,7))||start.getDate()!==Number(date.slice(8,10)))throw Error('التاريخ غير صالح');
 const end=new Date(start);end.setDate(end.getDate()+1);
 const nextOffset=more?offset:0;
 if(!more){setFinance(null);setFinanceError('');const fr=await supabase.rpc('admin_daily_financial_summary_v1',{p_start:start.toISOString(),p_end:end.toISOString()});if(fr.error)setFinanceError(fr.error.message);else {setFinance(fr.data);const previousStart=new Date(start.getTime()-86400000);const previous=await supabase.rpc('admin_daily_financial_summary_v1',{p_start:previousStart.toISOString(),p_end:start.toISOString()});setPreviousFinance(previous.error?null:previous.data);const ids=(fr.data?.sales_invoices||[]).map(x=>x.id).filter(Boolean);setInvoiceNumberMap({});if(ids.length){const nr=await supabase.rpc('admin_sale_invoice_numbers_v1',{p_sale_ids:ids});if(!nr.error&&nr.data)setInvoiceNumberMap(nr.data);else setFinanceError('تعذر جلب أرقام فواتير البيع: '+(nr.error?.message||'خطأ'));}}}
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
  setLoaded({date,events:await enrichSaleNumbers(events)});setTotal(events.length);setOffset(events.length);setPartial(true);
  return;
 }
 throw e;
}
 if(!data||!Array.isArray(data.events))throw Error('استجابة غير صحيحة من مركز الحركة');
 const newEvents=data.events.map((x,i)=>({key:x.kind+':'+x.id+':'+(nextOffset+i),id:x.id,kind:x.kind,source:x.kind,item:{...(x.details||{}),...(x.kind==='sale'?{sale_id:x.id,invoice_number:null}:{})},at:x.occurred_at}));
 const numberedEvents=await enrichSaleNumbers(newEvents);
 setLoaded(old=>({date,events:more&&old?.date===date?[...old.events,...numberedEvents]:numberedEvents}));
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
  const id=row.kind==='sale'?(row.id||raw.sale_id||raw.id):(raw.id||raw.sale_id||raw.purchase_id);
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
    const direct=await supabase.rpc('admin_sale_detail_daily_v1',{p_sale_id:id});
    if(!direct.error&&direct.data?.header){
      setDetailData({header:{...raw,...direct.data.header},items:Array.isArray(direct.data.items)?direct.data.items:[]});
      setDetailWarning('الأصناف المعروضة هي السجلات الحالية؛ قد تختلف الكميات عن وقت البيع إذا سبق تعديلها بعد مرتجعات.');
      return;
    }
    if(direct.error&&!['PGRST202','42883'].includes(direct.error.code)&&!/schema cache|Could not find the function/i.test(direct.error.message||''))throw direct.error;
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
 const money=(v,c)=>v==null?'غير مسجل':fmt(v)+' '+(c==='SYP'?'ل.س':c==='USD'?'USD':c||'عملة غير محددة');
 const field=(obj,keys)=>keys.map(k=>obj?.[k]).find(v=>v!==undefined&&v!==null&&v!=='');
 const fields=[['رقم الفاتورة',['invoice_number','receipt_number','id']],['المورد / العميل',['supplier_name','debtor_name','customer_name']],['نوع الدفع',['payment_method','payment_type']],['حالة الفاتورة',['status']],['العملة',['currency','sale_currency']],['سعر الصرف',['fx_rate']],['المجموع قبل الخصم',['subtotal']],['خصم الفاتورة',['discount','discount_amount']],['الإجمالي النهائي',['total']],['المبلغ المدفوع',['paid_amount','amount_paid','paid']],['المبلغ المتبقي / الدين',['due_amount','remaining_amount','balance']],['الدفعة المقدمة / الزيادة',['advance_amount','overpayment','credit_amount']],['الملاحظات',['notes']]];
 const visible=rows.filter(x=>(type==='all'||x.kind===type)&&(!search||JSON.stringify(x.item).toLowerCase().includes(search.toLowerCase())));

 return <section className="dailyActivity" dir="rtl"><header className="dailyActivityHead"><div><h1>مركز الحركة اليومية</h1><p>سجل للعمليات المهمة فقط: فواتير البيع والشراء، السحب والإيداع، التعديلات والحذف والجرد المعتمد، دون الحركات التلقائية المكررة.</p></div><div className="dailyActivityDate"><label>تاريخ الحركة<input type="date" value={date} onChange={e=>setDate(e.target.value)}/></label><button className="primary" disabled={busy} onClick={()=>load(false)}>{busy?'جارٍ التحميل…':'عرض الحركة'}</button></div></header>
 {error&&<div className="error">{error}</div>}
 {financeError&&<p className="dailyActivityNotice">الملخص المالي غير متاح: {financeError}</p>}
 {finance&&<section className="card" style={{padding:16,marginBottom:16}}><h2>الملخص المالي والتشغيلي لليوم</h2><div className="dailyActivityCards">{[
 ['عدد فواتير البيع',finance.sales?.sale_count,'فاتورة'],['عدد فواتير الشراء',finance.purchases?.purchase_count,'فاتورة'],
 ['إجمالي المبيعات',finance.sales?.sales_total,'ل.س'],['مبيعات نقدية',finance.sales?.cash_sales,'ل.س'],['مبيعات بالدين',finance.sales?.credit_sales,'ل.س'],
 ['ديون جديدة',finance.sales?.new_due,'ل.س'],['تحصيل ديون',finance.cash?.debt_collected,'ل.س'],
 ['تكلفة الأصناف المباعة',finance.sales?.cost_of_goods,'ل.س'],['الربح الإجمالي التقديري',finance.sales?.gross_profit,'ل.س'],
 ['المصروفات التشغيلية',finance.cash?.operating_expenses,'ل.س'],['صافي الربح التقديري',finance.net_profit_estimate,'ل.س'],
 ['صافي حركة الصندوق',finance.cash?.net_cash_change,'ل.س'],['رصيد الصندوق الافتتاحي المحسوب',finance.opening_cash,'ل.س'],['رصيد الصندوق الختامي المحسوب',finance.closing_cash,'ل.س'],
 ['مشتريات بالليرة',finance.purchases?.purchases_syp,'ل.س'],['مشتريات بالدولار',finance.purchases?.purchases_usd,'USD']
 ].map(([name,value,currency])=><div className="card" key={name}><small>{name}</small><strong>{value==null?'غير متاح':fmt(value)+' '+currency}</strong></div>)}</div>
 <p className="dailyActivityNotice">الربح تقديري بناءً على تكلفة الأصناف المسجلة. رصيد الصندوق محسوب من الحركات المسجلة وليس النقد المعدود. السحوبات الشخصية لا تُخصم من الربح. العملات منفصلة.</p>
 <div className="dailyActivityCards">{[['مرتجعات العملاء (عدد)',finance.return_summary?.customer_count,'حركة'],['قيمة مرتجعات العملاء',finance.return_summary?.customer_total_syp,'ل.س'],['مرتجعات الموردين (عدد)',finance.return_summary?.supplier_count,'حركة'],['قيمة مرتجعات الموردين',finance.return_summary?.supplier_total_syp,'ل.س'],['فرق قبض البيع المسجل عن فواتير النقد',finance.cash_sale_difference,'ل.س'],['سطور بيع بتكلفة صفرية',finance.cost_quality?.zero_cost_lines,'سطر']].map(([name,value,currency])=><div className="card" key={name}><small>{name}</small><strong>{value==null?'غير متاح':fmt(value)+' '+currency}</strong></div>)}</div>
 <p className="dailyActivityNotice">تنبيه تدقيقي: توجد {finance.cash_missing_amount_entries||0} قيود صندوق بلا قيمة محوّلة موثوقة. يُمنع اعتماد الرصيد النهائي عند وجود قيود ناقصة. المرتجعات معروضة مستقلة، ولم تُخصم مرة ثانية من المبيعات أو الأرباح لتجنب تكرار أثرها قبل التأكد من طريقة تحديث الفواتير الأصلية. فرق القبض مؤشر للمراجعة وليس إثباتاً لوجود خطأ؛ قد يتأثر بتوقيت تسجيل القيود والدفعات الجزئية. أي تكلفة صفرية تستدعي تدقيق الربح.</p>
 <button type="button" onClick={()=>window.print()}>طباعة التقرير / حفظ PDF</button>
 <button type="button" onClick={()=>{const records=[['النوع','الرقم','التاريخ','القيمة','العملة','المدفوع','المتبقي']];for(const x of finance.sales_invoices||[])records.push(['بيع',invoiceNumberMap[x.id]??'',x.date,x.total,x.currency,x.paid,x.due]);for(const x of finance.purchase_invoices||[])records.push(['شراء',x.invoice_number,x.date,x.total,x.currency,x.paid,x.due]);const content=records.map(row=>row.map(v=>'"'+String(v??'').replaceAll('"','""')+'"').join(',')).join(String.fromCharCode(13,10));const blob=new Blob([String.fromCharCode(65279),content],{type:'text/csv;charset=utf-8'});const url=URL.createObjectURL(blob);const link=document.createElement('a');link.href=url;link.download='daily-invoices-'+date+'.csv';link.click();URL.revokeObjectURL(url)}}>تصدير فواتير اليوم CSV / Excel</button>
 <h3>مقارنة مع اليوم السابق</h3><div className="dailyActivityCards">{[['المبيعات',finance.sales?.sales_total,previousFinance?.sales?.sales_total],['الربح الإجمالي',finance.sales?.gross_profit,previousFinance?.sales?.gross_profit],['الديون الجديدة',finance.sales?.new_due,previousFinance?.sales?.new_due],['صافي الصندوق',finance.cash?.net_cash_change,previousFinance?.cash?.net_cash_change]].map(([title,today,yesterday])=><div className="card" key={title}><small>{title}</small><strong>{fmt(today)} ل.س</strong><small>اليوم السابق: {yesterday==null?'غير متاح':fmt(yesterday)+' ل.س'} | الفرق: {yesterday==null?'—':fmt(Number(today||0)-Number(yesterday||0))+' ل.س'}</small></div>)}</div>
 <h3>فواتير البيع اليومية</h3><div className="dailyActivityTable"><table><thead><tr><th>رقم الفاتورة</th><th>التاريخ</th><th>القيمة</th><th>نقدي / دين</th><th>المدفوع</th><th>المتبقي</th></tr></thead><tbody>{(finance.sales_invoices||[]).map(x=><tr key={x.id}><td><button type="button" onClick={()=>openDetail({kind:'sale',id:x.id,at:x.date,item:{...x,invoice_number:invoiceNumberMap[x.id]}})}>{invoiceNumberMap[x.id]==null?'تفاصيل':String(invoiceNumberMap[x.id]).padStart(2,'0')}</button></td><td>{when(x.date)}</td><td>{fmt(x.total)} {x.currency}</td><td>{x.payment_method==='cash'?'نقدي':'دين'}</td><td>{fmt(x.paid)}</td><td>{fmt(x.due)}</td></tr>)}</tbody></table></div>
 <h3>فواتير الشراء اليومية</h3><div className="dailyActivityTable"><table><thead><tr><th>رقم الفاتورة</th><th>التاريخ</th><th>القيمة</th><th>المدفوع</th><th>المتبقي</th></tr></thead><tbody>{(finance.purchase_invoices||[]).map(x=><tr key={x.id}><td><button type="button" onClick={()=>openDetail({kind:'purchase',id:x.id,at:x.date,item:{...x}})}>{x.invoice_number||'تفاصيل'}</button></td><td>{when(x.date)}</td><td>{fmt(x.total)} {x.currency}</td><td>{fmt(x.paid)}</td><td>{fmt(x.due)}</td></tr>)}</tbody></table></div></section>}

 {loaded&&<>{partial&&<div className="dailyActivityNotice" role="status"><strong>عرض جزئي فقط:</strong> الدالة الشاملة غير مثبتة على هذه القاعدة. يتم عرض الحركات المتاحة من التقرير المحاسبي الحالي؛ لا يشمل هذا العرض بالضرورة جميع عمليات التعديل والحذف والجرد أو تفاصيل الأصناف. لا تعتمد عليه كسجل تدقيق كامل.</div>}<div className="dailyActivityCards">{[['فواتير البيع',rows.filter(x=>x.kind==='sale').length,'حركة'],['فواتير الشراء',rows.filter(x=>x.kind==='purchase').length,'حركة'],['المرتجعات',rows.filter(x=>x.kind==='return').length,'حركة'],['سحب وإيداع الصندوق',rows.filter(x=>x.kind==='cash').length,'حركة']].map(([name,value,currency])=><div className="card" key={name}><small>{name}</small><strong>{value==null?'غير متاح':fmt(value)+' '+currency}</strong></div>)}</div>
 <div className="card dailyActivityControls"><select aria-label="نوع الحركة" value={type} onChange={e=>setType(e.target.value)}><option value="all">جميع الحركات</option>{[...new Set([...sources.map(x=>x[1]),'return','inventory_count'])].map(k=><option value={k} key={k}>{label[k]}</option>)}</select><input placeholder="بحث برقم الفاتورة أو الاسم أو المرجع" value={search} onChange={e=>setSearch(e.target.value)}/><span>{visible.length} حركة معروضة من أصل {total}</span></div>
 <p className="dailyActivityNotice">المصدر: {partial?'التقرير المحاسبي الجزئي':'سجلات العمليات المهمة'}. تُستبعد حركات المخزون الناتجة تلقائياً عن البيع وقبض الفواتير المكرر. لا يمكن استعادة تعديل لم يُسجّل أصلاً.</p>
 <div className="card dailyActivityTable"><table><thead><tr><th>التاريخ والساعة</th><th>نوع الحركة</th><th>المرجع</th><th>القيمة</th><th>الإجراء</th></tr></thead><tbody>{visible.map(x=><tr key={x.key}><td>{when(x.at)}</td><td>{movementName(x)}</td><td>{movementRef(x)}</td><td>{x.item.total!=null||x.item.amount!=null?fmt(x.item.total??x.item.amount)+' '+scalar(x.item.currency||(x.kind==='sale'?'SYP':'عملة غير محددة')):'—'}</td><td><button type="button" onClick={()=>openDetail(x)}>تفاصيل</button></td></tr>)}</tbody></table>{!visible.length&&<p>لا توجد حركات ضمن البيانات المتاحة للتاريخ والتصفية المحددين.</p>}{offset<total&&<button type="button" disabled={busy} onClick={()=>load(true)}>{busy?'جارٍ التحميل…':'تحميل 500 حركة إضافية'}</button>}</div></>}
 {detail&&<div className="dailyActivityModal" role="dialog" aria-modal="true" aria-label="تفاصيل الحركة" onClick={e=>{if(e.target===e.currentTarget)setDetail(null)}}><div className="dailyActivityDialog card">
 <header className="dailyActivityDialogHead"><div><small>مركز الحركة اليومية</small><h2>{detail.kind==='sale'?'فاتورة بيع':detail.kind==='purchase'?'فاتورة شراء':label[detail.kind]||'تفاصيل الحركة'}</h2><p>{when(detail.at)}</p></div><button type="button" onClick={()=>setDetail(null)} aria-label="إغلاق">×</button></header>
 {detailBusy&&<p className="dailyActivityNotice" role="status">جارٍ تحميل تفاصيل الفاتورة…</p>}
 {detailWarning&&<p className="dailyActivityNotice" role="status">{detailWarning}</p>}
 {detailData&&(()=>{
 const h=detailData.header||{},isInvoice=detail.kind==='sale'||detail.kind==='purchase';
 const c=field(h,['currency','sale_currency','purchase_currency'])||(detail.kind==='sale'?'SYP':null);
 const invoiceNo=field(h,['invoice_number','daily_sale_number','sale_number','purchase_number','receipt_number']);
 const displayedInvoiceNo=detail.kind==='sale'&&invoiceNo!=null?String(invoiceNo).padStart(2,'0'):invoiceNo;
 const customer=field(h,['supplier_name','debtor_name','customer_name']);
 const total=field(h,['total','grand_total','net_total']);
 const paid=field(h,['paid_amount','amount_paid','paid']);
 const due=field(h,['due_amount','remaining_amount','balance']);
 const payment=field(h,['payment_method','payment_type']);
 const info=[['رقم الفاتورة',displayedInvoiceNo],['الجهة',customer],['طريقة الدفع',payment],['حالة الفاتورة',field(h,['status'])],['العملة',c],['سعر الصرف',field(h,['fx_rate'])],['رقم الإيصال',field(h,['receipt_number'])],['الملاحظات',field(h,['notes'])]];
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