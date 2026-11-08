import {uiText,uiTemplate} from './systemLocale.js';
import React,{useEffect,useRef,useState} from 'react';
import {ISOLATED_QA_PROJECT_URL} from './stagingAuthGuard.js';
import {encryptQaBackup,decryptQaBackup} from './qaBackupCrypto.js';
import {localizeAdminTree} from './systemAdminLocale.js';
export default function QaBackupExport({client,projectUrl,actorRole,actorId,language='ar'}){
 const [phrase,setPhrase]=useState(''),[confirmation,setConfirmation]=useState(''),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[download,setDownload]=useState(null),[file,setFile]=useState(null);
 const current=useRef(0),locked=useRef(false),blobUrl=useRef(null);
 useEffect(()=>{current.current++;setPhrase('');setConfirmation('');setMessage('');setFile(null);setDownload(null);if(blobUrl.current)URL.revokeObjectURL(blobUrl.current);blobUrl.current=null;return()=>{current.current++;if(blobUrl.current)URL.revokeObjectURL(blobUrl.current);};},[actorId,actorRole,projectUrl]);
 const enabled=projectUrl===ISOLATED_QA_PROJECT_URL&&['system_owner','system_admin'].includes(actorRole)&&!!actorId;
 if(!enabled)return null;
 const run=async verify=>{
  if(locked.current)return;locked.current=true;setBusy(true);setMessage('');const generation=current.current;
  try{
   if(verify){
    if(!file||file.size>70*1024*1024)throw new Error('invalid_archive');
    const result=await decryptQaBackup(JSON.parse(await file.text()),phrase);
    if(generation===current.current)setMessage(uiText('تم التحقق من سلامة الملف؛ عدد الجداول: ')+result.summary.tables+uiText('. هذا ليس اختبار استعادة.'));
   }else{
    if(phrase.length<16||phrase!==confirmation)throw new Error('invalid_passphrase');
    const {data:user,error:identityError}=await client.auth.getUser();
    if(identityError||user?.user?.id!==actorId)throw new Error('not_authorized');
    const {data,error}=await client.functions.invoke('qa-admin-application-backup',{body:{}});
    if(error||data?.export_complete!==true)throw new Error('backup_unavailable');
    const envelope=await encryptQaBackup(data,phrase,confirmation);
    if(generation===current.current){
     if(blobUrl.current)URL.revokeObjectURL(blobUrl.current);
     blobUrl.current=URL.createObjectURL(new Blob([JSON.stringify(envelope)],{type:'application/json'}));
     setDownload({url:blobUrl.current,name:'Pharmacy_QA_Application_'+new Date().toISOString().slice(0,10)+'.pharmacy-backup.json'});
     setMessage('تم تجهيز نسخة التطبيق المشفرة. احفظ الملف وعبارة التشفير في مكانين آمنين منفصلين.');
    }
   }
  }catch{if(generation===current.current)setMessage('تعذر تجهيز النسخة أو فحصها. تحقق من الصلاحية وعبارة التشفير وتطابقها، ثم حاول مجدداً.');}
  finally{locked.current=false;if(generation===current.current){setBusy(false);setPhrase('');setConfirmation('');}}
 };
 return localizeAdminTree(<section className="systemAdminRecovery adminBackupLayout" aria-label={uiText("نسخة تطبيق QA المشفرة")}>
  <div className="adminSettingsCard adminBackupCreate"><h4>{uiText("نسخة تطبيق QA المشفرة")}</h4>
  <p>{uiText("تشمل بيانات التطبيق وملفاته، دون كلمات المرور أو إعدادات المنصة.")}</p>
  <label>{uiText("عبارة تشفير النسخة")}<input type="password" autoComplete="new-password" minLength={16} value={phrase} onChange={e=>setPhrase(e.target.value)} disabled={busy}/></label>
  <label>{uiText("تأكيد عبارة التشفير")}<input type="password" autoComplete="new-password" minLength={16} value={confirmation} onChange={e=>setConfirmation(e.target.value)} disabled={busy}/></label>
  <p>{uiText("16 محرفاً على الأقل؛ احفظ العبارة لاستعمال النسخة.")}</p>
  <button type="button" disabled={busy||phrase.length<16||phrase!==confirmation} onClick={()=>run(false)}>{busy?uiText('جارٍ الحفظ…'):uiText('تجهيز نسخة مشفرة من QA')}</button>
  {download&&<p><a href={download.url} download={download.name}>{uiText("تنزيل نسخة التطبيق المشفرة")}</a></p>}
  </div><div className="adminSettingsCard adminBackupVerify"><h4>{uiText("فحص سلامة نسخة مشفرة")}</h4><p>{uiText("فحص محلي للسلامة، لا يستعيد البيانات.")}</p>
  <label>{uiText("اختيار نسخة مشفرة")}<input type="file" accept=".json,application/json" disabled={busy} onChange={e=>setFile(e.target.files?.[0]||null)}/></label>
  <button type="button" disabled={busy||!file||phrase.length<16} onClick={()=>run(true)}>{uiText("فحص سلامة الملف محلياً")}</button></div>
  {uiText(message)&&<p role="status">{uiText(message)}</p>}
 </section>,language);
}
