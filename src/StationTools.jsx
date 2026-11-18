import React,{useState} from 'react';
import {makeSetupPackage, normalizeDeviceSetup, printAdminDocument, printKinds, readDeviceSetup, readSetupPackage, saveDeviceSetup} from './adminPrintSettings.js';
import {uiText} from './systemLocale.js';
import './ADMIN_TOOLS.css';
const sections=[['print','قوالب الطباعة'],['devices','إدارة الأجهزة'],['package','حزم إعداد الصيدلية']];
const label = value => uiText(value);
function downloadFile(name, content, type) {
 const url = URL.createObjectURL(new Blob([content], {type}));
 const anchor = document.createElement('a');
 anchor.href = url;
 anchor.download = name;
 anchor.click();
 setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export default function StationTools({appearance, applyAppearance}) {
 const [tab, setTab] = useState('print');
 const [setup, setSetup] = useState(readDeviceSetup);
 const [message, setMessage] = useState('');
 const save = next => {
  try {saveDeviceSetup(next); setSetup(readDeviceSetup()); setMessage('حُفظت إعدادات هذا المتصفح.');}
  catch {setMessage('تعذر حفظ إعدادات هذا المتصفح.');}
 };
 return <section className="adminTools">
  <nav aria-label={label('أدوات الإدارة')}>{sections.map(([id,title]) =>
   <button type="button" key={id} className={tab===id?'primary':'secondaryAction'}
    aria-current={tab===id?'page':undefined} onClick={()=>{setTab(id);setMessage('');}}>{label(title)}</button>)}</nav>
  {tab==='print' && <PrintTemplates setup={setup} save={save}/>}
  {tab==='devices' && <DeviceSettings setup={setup} save={save}/>}
  {tab==='package' && <SetupPackage setup={setup} appearance={appearance} applyAppearance={applyAppearance} setSetup={setSetup}/>}
  {message && <p role="status">{label(message)}</p>}
 </section>;
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
