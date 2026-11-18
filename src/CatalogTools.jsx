import React,{useState,useRef,useEffect} from 'react';
import {catalogFindings,catalogRows,catalogSample,previewCatalogImport,readCatalogCsv} from './adminCatalogTools.js';
import {uiText as label} from './systemLocale.js';
const status = {create:'إضافة', update:'تحديث السعر', unchanged:'بلا تغيير'};
const fieldLabels = {name:'الاسم', barcode:'الباركود', active_ingredient:'المادة الفعالة', strength:'التركيز', dosage_form:'الشكل الدوائي'};
function downloadFile(name, content, type) {
 const url = URL.createObjectURL(new Blob([content], {type}));
 const anchor = document.createElement('a');
 anchor.href = url;
 anchor.download = name;
 anchor.click();
 setTimeout(() => URL.revokeObjectURL(url), 1000);
}

async function matchCatalog(client,rows){
 const codes=[...new Set(rows.map(row=>row.barcode).filter(code=>/^[A-Za-z0-9_-]{1,80}$/.test(code)))];
 const matches=[];
 for(let start=0;start<codes.length;start+=30){
   const part=codes.slice(start,start+30);
   const [products,aliases]=await Promise.all([client.from('products').select('id,barcode,name,sale_price,sale_currency,active').in('barcode',part),client.from('product_barcodes').select('barcode').in('barcode',part)]);
   if(products.error||aliases.error)throw Error('تعذّرت مطابقة الباركودات مع الدليل.');
   matches.push(...products.data,...aliases.data.map(row=>({...row,alias:true})));
 }
 return matches;
}
async function fetchCatalog(client){
 const rows=[];let cursor=null;
 while(true){
   let query=client.from('products').select('id,name,barcode,active_ingredient,strength,dosage_form').eq('active',true).order('id').limit(500);
   if(cursor)query=query.gt('id',cursor);
   const {data,error}=await query;
   if(error)throw Error('تعذّر فحص دليل الأدوية.');
   rows.push(...data);
   if(!data.length)break;
   cursor=data[data.length-1].id;
 }
 return rows;
}
export function CatalogImport({client}) {
 const [preview, setPreview] = useState([]);
 const [selected, setSelected] = useState(new Set());
 const [busy, setBusy] = useState(false);
 const [confirm, setConfirm] = useState(false);
 const [message, setMessage] = useState('');
 const request = useRef(null);
 const lock = useRef(false);
 const active = useRef(true);
 useEffect(()=>{active.current=true;return()=>{active.current=false;};},[]);
 async function load(file) {
  if (!file || lock.current) return;
  lock.current=true;setBusy(true);setMessage('');setPreview([]);setConfirm(false);request.current=null;
  try {
   if (file.size>1024*1024) throw Error('حجم الملف يتجاوز 1 ميغابايت.');
   let rows;
   if (/\.xlsx$/i.test(file.name)) {
    const {readSheet}=await import('read-excel-file/browser');
    rows=catalogRows(await readSheet(file,1));
   } else if (/\.csv$/i.test(file.name)) rows=readCatalogCsv(await file.text());
   else throw Error('اختر ملف CSV أو XLSX.');
   if (!active.current) return;
   const next=previewCatalogImport(rows,await matchCatalog(client,rows));
   setPreview(next);
   setSelected(new Set(next.filter(row=>!row.errors.length&&row.mode!=='unchanged').map(row=>row.row)));
  } catch(error) {setMessage(error.message || 'تعذرت معاينة الملف.');}
  finally {lock.current=false;setBusy(false);}
 }
 async function apply() {
  if (!confirm || !selected.size || lock.current) return;
  lock.current=true;setBusy(true);setMessage('');
  try {
   const rows=preview.filter(row=>selected.has(row.row)&&!row.errors.length&&row.mode!=='unchanged').map(row=>({
    mode:row.mode, barcode:row.barcode, name:row.name, price:row.price, currency:row.currency,
    ...(row.previous ? {id:row.previous.id,previousPrice:String(row.previous.sale_price)} : {}),
   }));
   request.current ??= crypto.randomUUID();
   const {data,error}=await client.rpc('manager_catalog_apply',{p_request_id:request.current,p_rows:rows});
   if(error?.code==='40001'){setConfirm(false);setPreview([]);setSelected(new Set());throw Error('تغيّر الدليل بعد المعاينة. افتح الملف مجدداً.');}
   if (error || data!==rows.length) throw Error('تعذر تأكيد الاستيراد. أعد المحاولة بنفس الاختيار للتحقق من النتيجة.');
   setMessage('تم تطبيق الصفوف المحددة وتسجيلها في سجل الإدارة.');setPreview([]);setSelected(new Set());setConfirm(false);request.current=null;
  } catch(error){setMessage(error.message || 'تعذر تطبيق الاستيراد.');}
  finally {lock.current=false;setBusy(false);}
 }
 return <div className="adminSettingsCard adminToolsPanel">
  <h4>{label('استيراد الأصناف والأسعار')}</h4>
  <p>{label('اختر ملف CSV أو أول ورقة في XLSX. اعرض التغييرات وحدّد الصفوف قبل الحفظ.')}</p>
  <button type="button" className="secondaryAction" onClick={()=>downloadFile('pharmacy-catalog.csv',catalogSample,'text/csv;charset=utf-8')}>{label('تنزيل قالب CSV')}</button>
  <label>{label('ملف الأصناف')}<input type="file" accept=".csv,.xlsx" disabled={busy} onChange={event=>{const file=event.target.files?.[0];event.target.value='';load(file);}}/></label>
  {preview.length>0 && <>
   <div className="adminToolsTable"><table><thead><tr>{['تطبيق','الصف','الباركود','الاسم','قبل','بعد','العملة','النتيجة'].map(title=><th key={title}>{label(title)}</th>)}</tr></thead>
    <tbody>{preview.map(row=><tr key={row.row}>
     <td><input type="checkbox" aria-label={label('تطبيق')+' '+row.row} disabled={busy||confirm||!!row.errors.length||row.mode==='unchanged'} checked={selected.has(row.row)} onChange={event=>{const next=new Set(selected);if(event.target.checked)next.add(row.row);else next.delete(row.row);setSelected(next);}}/></td>
     <td>{row.row}</td><td dir="ltr">{row.barcode}</td><td>{row.previous?.name||row.name}</td><td>{row.previous?.sale_price??'—'}</td><td>{row.price}</td><td>{row.currency}</td>
     <td>{row.errors.length?row.errors.map(label).join(' · '):label(status[row.mode])}</td>
    </tr>)}</tbody></table></div>
   {confirm ? <div className="adminToolsActions"><p>{label('عدد الصفوف المحددة')} {selected.size}</p>
    <button type="button" disabled={busy} onClick={apply}>{label('تأكيد تطبيق الاستيراد')}</button>
    <button type="button" className="secondaryAction" disabled={busy||!!request.current} onClick={()=>setConfirm(false)}>{label('رجوع للمعاينة')}</button>
   </div> : <button type="button" disabled={busy||!selected.size} onClick={()=>setConfirm(true)}>{label('مراجعة التطبيق')} ({selected.size})</button>}
  </>}
  {busy && <p role="status">{label('جارٍ المعالجة…')}</p>}
  {message && <p role="status">{label(message)}</p>}
 </div>;
}

export function CatalogCleanup({client,openProduct}) {
 const [issues,setIssues]=useState(null),[busy,setBusy]=useState(false),[filter,setFilter]=useState('all'),[error,setError]=useState('');
 async function scan() {
  if (busy) return;
  setBusy(true);setError('');setIssues(null);setPage(0);
  try {setIssues(catalogFindings(await fetchCatalog(client)));}
  catch(error){setError(error.message);}
  finally{setBusy(false);}
 }
 const [page,setPage]=useState(0);
 const visible=(issues||[]).filter(issue=>filter==='all'||filter===issue.kind);
 const titles={barcode:'باركود متضارب',similar:'أسماء متشابهة',missing:'حقول ناقصة'};
 return <div className="adminSettingsCard adminToolsPanel">
  <h4>{label('مراجعة جودة دليل الأدوية')}</h4>
  <p>{label('افحص الدليل ثم افتح بطاقة الصنف لمراجعة التصحيح.')}</p>
  <button type="button" onClick={scan} disabled={busy}>{label(busy?'جارٍ المعالجة…':'فحص الدليل')}</button>
  {error && <p role="alert">{label(error)}</p>}
  {issues && <>
   <label>{label('نوع الملاحظة')}<select value={filter} onChange={e=>{setPage(0);setFilter(e.target.value);}}><option value="all">{label('الكل')}</option>{Object.entries(titles).map(([id,title])=><option value={id} key={id}>{label(title)}</option>)}</select></label>
   <p>{label('عدد الملاحظات')} {visible.length}</p>
   <button disabled={!page} onClick={()=>setPage(page-1)}>السابق</button><button disabled={(page+1)*60>=visible.length} onClick={()=>setPage(page+1)}>التالي</button>
   <ul className="adminToolsFindings">{visible.slice(page*60,(page+1)*60).map((issue,index)=><li key={issue.kind+':'+index}>
    <strong>{label(titles[issue.kind])}</strong>{issue.missing && <p>{issue.missing.map(field=>label(fieldLabels[field])).join(' · ')}</p>}
    {issue.items.map(item=><button type="button" className="secondaryAction" key={item.id} onClick={()=>openProduct(item)}>{item.name||'—'} · <bdi>{item.barcode}</bdi></button>)}
   </li>)}</ul>
  </>}
 </div>;
}
