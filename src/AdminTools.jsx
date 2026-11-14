import React, {useEffect, useRef, useState} from 'react';
import {catalogFindings, catalogRows, catalogSample, previewCatalogImport, readCatalogCsv} from './adminCatalogTools.js';
import {makeSetupPackage, normalizeDeviceSetup, printAdminDocument, printKinds, readDeviceSetup, readSetupPackage, saveDeviceSetup} from './adminPrintSettings.js';
import {uiText} from './systemLocale.js';
import './ADMIN_TOOLS.css';
import QaOperatingTools from './QaOperatingTools.jsx';

const sections = [
 ['import','الاستيراد الذكي'], ['print','قوالب الطباعة'], ['devices','إدارة الأجهزة'],
 ['cleanup','تنظيف دليل الأدوية'], ['package','حزم إعداد الصيدلية'],
];
const operatingSections=[
 ['policy','سياسات التشغيل'],['corrections','مراجعة أثر العمليات'],['emergency','وضع الطوارئ'],
 ['training','تمارين الموظفين'],['integrations','متابعة الطلبات'],['reports','تقارير المالك'],
];
const label = value => uiText(value);
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

export default function AdminTools({client, appearance, applyAppearance, openProduct}) {
 const [tab, setTab] = useState('import');
 const [setup, setSetup] = useState(readDeviceSetup);
 const [message, setMessage] = useState('');
 const save = next => {
  try {saveDeviceSetup(next); setSetup(readDeviceSetup()); setMessage('حُفظت إعدادات هذا المتصفح.');}
  catch {setMessage('تعذر حفظ إعدادات هذا المتصفح.');}
 };
 return <section className="adminTools">
  <nav aria-label={label('أدوات الإدارة')}>{[...sections,...operatingSections].map(([id,title]) =>
   <button type="button" key={id} className={tab===id?'primary':'secondaryAction'}
    aria-current={tab===id?'page':undefined} onClick={()=>{setTab(id);setMessage('');}}>{label(title)}</button>)}</nav>
  {tab==='import' && <CatalogImport client={client}/>}
  {tab==='print' && <PrintTemplates setup={setup} save={save}/>}
  {tab==='devices' && <DeviceSettings setup={setup} save={save}/>}
  {tab==='cleanup' && <CatalogCleanup client={client} openProduct={openProduct}/>}
  {tab==='package' && <SetupPackage setup={setup} appearance={appearance} applyAppearance={applyAppearance} setSetup={setSetup}/>}
  {operatingSections.some(([id])=>id===tab)&&<QaOperatingTools client={client} kind={tab}/>}
  {message && <p role="status">{label(message)}</p>}
 </section>;
}

async function fetchCatalog(client) {
 const {data,error} = await client.rpc('qa_workspace_snapshot');
 if (error || !Array.isArray(data?.products) || !['system_admin','system_owner'].includes(data.role)) {
  throw Error('تعذر قراءة دليل QA بحساب المدير.');
 }
 return data.products;
}

function CatalogImport({client}) {
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
   const next=previewCatalogImport(rows,await fetchCatalog(client));
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
   const {data,error}=await client.rpc('qa_apply_catalog_import',{p_request_id:request.current,p_rows:rows});
   if(error?.code==='40001'){setConfirm(false);setPreview([]);setSelected(new Set());throw Error('تغيّر الدليل بعد المعاينة. افتح الملف مجدداً.');}
   if (error || data!==rows.length) throw Error('تعذر تأكيد الاستيراد. أعد المحاولة بنفس الاختيار للتحقق من النتيجة.');
   setMessage('تم تطبيق الصفوف المحددة وتسجيلها في سجل الإدارة.');setPreview([]);setSelected(new Set());setConfirm(false);request.current=null;
  } catch(error){setMessage(error.message || 'تعذر تطبيق الاستيراد.');}
  finally {lock.current=false;setBusy(false);}
 }
 return <div className="adminSettingsCard adminToolsPanel">
  <h4>{label('استيراد الأصناف والأسعار')}</h4>
  <p>{label('QA فقط. اختر CSV أو أول ورقة في XLSX. الرموز التجريبية تبدأ بـ QA-IMPORT-.')}</p>
  <button type="button" className="secondaryAction" onClick={()=>downloadFile('pharmacy-qa-import.csv',catalogSample,'text/csv;charset=utf-8')}>{label('تنزيل قالب CSV')}</button>
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

const sampleDocument = kind => ({
 title:label(printKinds[kind].label), columns:[label('البيان'),label('القيمة')],
 rows:[[label('صنف تجريبي'),'12,500 SYP'],[label('الكمية'),'1']], sample:true,
});
function PrintTemplates({setup, save}) {
 const [kind,setKind]=useState('receipt');
 const [draft,setDraft]=useState(setup.templates);
 const edit=(field,value)=>setDraft({...draft,[kind]:{...draft[kind],[field]:value}});
 return <div className="adminSettingsCard adminToolsPanel">
  <h4>{label('قوالب الطباعة')}</h4>
  <label>{label('نوع المستند')}<select value={kind} onChange={e=>setKind(e.target.value)}>{Object.entries(printKinds).map(([id,item])=><option key={id} value={id}>{label(item.label)}</option>)}</select></label>
  <label>{label('عنوان المستند')}<input value={draft[kind].title} maxLength={90} placeholder={label(printKinds[kind].label)} onChange={e=>edit('title',e.target.value)}/></label>
  <label>{label('حجم الورق')}<select value={draft[kind].paper} onChange={e=>edit('paper',e.target.value)}><option>A4</option><option value="80mm">80 mm</option></select></label>
  <label className="adminToolsCheck"><input type="checkbox" checked={draft[kind].logo} onChange={e=>edit('logo',e.target.checked)}/>{label('إظهار الشعار')}</label>
  <label className="adminToolsCheck"><input type="checkbox" checked={draft[kind].date} onChange={e=>edit('date',e.target.checked)}/>{label('إظهار تاريخ الطباعة')}</label>
  <div className="adminToolsActions">
   <button type="button" onClick={()=>save({...setup,templates:draft})}>{label('حفظ القوالب')}</button>
   <button type="button" className="secondaryAction" onClick={()=>printAdminDocument(kind,sampleDocument(kind),{...setup,templates:draft})}>{label('معاينة الطباعة')}</button>
  </div>
 </div>;
}
function DeviceSettings({setup,save}) {
 const [device,setDevice]=useState(setup.device);
 const [barcode,setBarcode]=useState('');
 const [seen,setSeen]=useState('');
 return <div className="adminSettingsCard adminToolsPanel">
  <h4>{label('ملف محطة البيع')}</h4>
  <p>{label('هذه الإعدادات خاصة بهذا المتصفح. اختر الطابعة الفعلية من نافذة الطباعة.')}</p>
  {[['name','اسم المحطة'],['printer','اسم الطابعة'],['drawer','وصف درج النقد']].map(([id,title])=><label key={id}>{label(title)}<input maxLength={id==='name'?80:100} value={device[id]} onChange={e=>setDevice({...device,[id]:e.target.value})}/></label>)}
  <label>{label('اختبار قارئ الباركود')}<input dir="ltr" value={barcode} maxLength={128} onChange={e=>setBarcode(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'){e.preventDefault();setSeen(barcode.trim());setBarcode('');}}}/></label>
  {seen && <p role="status">{label('الرمز المقروء')} <bdi>{seen}</bdi></p>}
  <div className="adminToolsActions">
   <button type="button" onClick={()=>save({...setup,device})}>{label('حفظ المحطة')}</button>
   <button type="button" className="secondaryAction" onClick={()=>printAdminDocument('receipt',sampleDocument('receipt'),setup)}>{label('طباعة تجريبية')}</button>
  </div>
 </div>;
}
function CatalogCleanup({client,openProduct}) {
 const [issues,setIssues]=useState(null),[busy,setBusy]=useState(false),[filter,setFilter]=useState('all'),[error,setError]=useState('');
 async function scan() {
  if (busy) return;
  setBusy(true);setError('');setIssues(null);
  try {setIssues(catalogFindings(await fetchCatalog(client)));}
  catch(error){setError(error.message);}
  finally{setBusy(false);}
 }
 const visible=(issues||[]).filter(issue=>filter==='all'||filter===issue.kind);
 const titles={barcode:'باركود متضارب',similar:'أسماء متشابهة',missing:'حقول ناقصة'};
 return <div className="adminSettingsCard adminToolsPanel">
  <h4>{label('مراجعة جودة دليل الأدوية')}</h4>
  <p>{label('افحص الدليل ثم افتح بطاقة الصنف لمراجعة التصحيح.')}</p>
  <button type="button" onClick={scan} disabled={busy}>{label(busy?'جارٍ المعالجة…':'فحص الدليل')}</button>
  {error && <p role="alert">{label(error)}</p>}
  {issues && <>
   <label>{label('نوع الملاحظة')}<select value={filter} onChange={e=>setFilter(e.target.value)}><option value="all">{label('الكل')}</option>{Object.entries(titles).map(([id,title])=><option value={id} key={id}>{label(title)}</option>)}</select></label>
   <p>{label('عدد الملاحظات')} {visible.length}</p>
   <ul className="adminToolsFindings">{visible.map((issue,index)=><li key={issue.kind+':'+index}>
    <strong>{label(titles[issue.kind])}</strong>{issue.missing && <p>{issue.missing.map(field=>label(fieldLabels[field])).join(' · ')}</p>}
    {issue.items.map(item=><button type="button" className="secondaryAction" key={item.id} onClick={()=>openProduct(item.id)}>{item.name||'—'} · <bdi>{item.barcode}</bdi></button>)}
   </li>)}</ul>
  </>}
 </div>;
}
function SetupPackage({setup,appearance,applyAppearance,setSetup}) {
 const [preview,setPreview]=useState(null),[message,setMessage]=useState(''),[busy,setBusy]=useState(false);
 async function load(file) {
  setPreview(null);setMessage('');
  if (!file) return;
  try {
   if(file.size>32_000) throw Error('حزمة الإعدادات غير صالحة.');
   setPreview(readSetupPackage(await file.text()));
  } catch {setMessage('حزمة الإعدادات غير صالحة.');}
 }
 async function apply() {
  setBusy(true);setMessage('');
  try {
   await applyAppearance(preview.appearance);
   saveDeviceSetup({...setup,templates:preview.templates});
   setSetup(normalizeDeviceSetup({...setup,templates:preview.templates}));
   setPreview(null);setMessage('تم تطبيق حزمة الإعدادات على هذا المتصفح.');
  } catch {setMessage('تعذر إكمال تطبيق الحزمة. راجع إعدادات هذا المتصفح.');}
  finally {setBusy(false);}
 }
 return <div className="adminSettingsCard adminToolsPanel">
  <h4>{label('حزم إعداد الصيدلية')}</h4>
  <p>{label('الحزمة تشمل اللغة والمظهر وقوالب الطباعة. العملات والأرصدة تحتاج إعداداً منفصلاً.')}</p>
  <button type="button" className="secondaryAction" onClick={()=>downloadFile('pharmacy-setup.json',JSON.stringify(makeSetupPackage(setup,appearance),null,2),'application/json')}>{label('تنزيل حزمة الإعدادات')}</button>
  <label>{label('معاينة حزمة إعدادات')}<input type="file" accept=".json,application/json" disabled={busy} onChange={e=>{const file=e.target.files?.[0];e.target.value='';load(file);}}/></label>
  {preview&&<><p>{label('لغة النظام')} · {preview.appearance.language} · {label(preview.appearance.density==='compact'?'مضغوط':'مريح')}</p>
   <ul>{Object.entries(preview.templates).map(([id,item])=><li key={id}>{label(printKinds[id].label)} · {item.paper} · {item.title||'—'} · {label(item.logo?'مع شعار':'بدون شعار')} · {label(item.date?'مع تاريخ':'بدون تاريخ')}</li>)}</ul>
   <button type="button" disabled={busy} onClick={apply}>{label('اعتماد الحزمة')}</button>
  </>}
  {message && <p role="status">{label(message)}</p>}
 </div>;
}
