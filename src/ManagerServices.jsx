import {uiText} from './systemLocale.js';
import {createClient} from '@supabase/supabase-js';
import React,{useEffect,useState} from 'react';
import {encryptArchive,decryptArchive} from './managerArchive.js';

export function ManagerMembers({client}){
 const [members,setMembers]=useState(null),[error,setError]=useState(false);
 useEffect(()=>{
   let active=true;
   (async()=>{
     try {
       const {data,error}=await client.rpc('manager_center_members');
       if(error || !Array.isArray(data) || !data.length) throw Error();
       if(active)setMembers(data);
     } catch {if(active)setError(true);}
   })();
   return ()=>{active=false;};
 },[client]);
 if(error)return <p role="alert">{uiText("تعذّر تحميل حسابات النظام.")}</p>;
 if(!members)return <p role="status">{uiText("جارٍ تحميل الحسابات…")}</p>;
 const labels={admin:'مدير النظام',system_admin:'مدير النظام',system_owner:'مالك النظام',employee:'موظف',technical_support:'دعم فني'};
 return <table><thead><tr><th>{uiText("البريد الإلكتروني")}</th><th>{uiText("دور الحساب")}</th></tr></thead><tbody>{members.map(member=><tr key={member.email}><td dir="ltr">{member.email}</td><td>{labels[member.role] || 'غير معيّن'}</td></tr>)}</tbody></table>;
}

export function ManagerArchive({client}){
 const [pass,setPass]=useState(''),[confirmation,setConfirmation]=useState(''),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 async function run(file){
   if(busy)return;
   setBusy(true);setMessage('');
   try {
     let envelope;
     if(file){
       if(file.size>75*1024*1024)throw Error();
       envelope=JSON.parse(await file.text());
     }else{
       if(pass!==confirmation || pass.length<16)throw Error();
       const {data,error}=await client.rpc('manager_center_data_archive');
       if(error)throw error;
       envelope=await encryptArchive(data,pass,confirmation);
     }
     const {summary}=await decryptArchive(envelope,pass);
     if(!file){
       const url=URL.createObjectURL(new Blob([JSON.stringify(envelope)],{type:'application/json'}));
       const link=document.createElement('a');
       link.href=url;link.download='pharmacy-data-'+new Date().toISOString().slice(0,10)+'.json';link.click();
       setTimeout(()=>URL.revokeObjectURL(url),30000);
     }
     setPass('');setConfirmation('');
     setMessage('تم التحقق من الملف المشفّر. عدد الجداول '+summary.tables+'، وعدد السجلات '+summary.rows+'.');
   }catch{setMessage(file?'تعذّر فتح الملف. تحقق من الملف وعبارة التشفير.':'تعذّر إنشاء نسخة البيانات المشفّرة.');}
   finally{setBusy(false);}
 }
 return <section className="adminSettingsCard"><h4>{uiText("نسخة مشفّرة من بيانات الصيدلية")}</h4><p>{uiText("تشمل سجلات قاعدة الصيدلية. ملفات صور الوصفات وحسابات الدخول وإعدادات الاستضافة خارج نطاق هذه النسخة. احتفظ بعبارة التشفير لفتح الملف لاحقاً.")}</p>
 <label>{uiText("عبارة التشفير")}<input type="password" minLength={16} autoComplete="off" value={pass} onChange={e=>setPass(e.target.value)}/></label>
 <label>{uiText("تأكيد عبارة التشفير")}<input type="password" autoComplete="off" value={confirmation} onChange={e=>setConfirmation(e.target.value)}/></label>
 <button type="button" disabled={busy||pass.length<16||pass!==confirmation} onClick={()=>run(null)}>{uiText("تنزيل نسخة مشفّرة")}</button>
 <label>{uiText("التحقق من ملف محفوظ")}<input type="file" accept="application/json,.json" disabled={busy||pass.length<16} onChange={e=>{const f=e.target.files?.[0];e.target.value='';if(f)run(f);}}/></label>
 <p role="status">{busy?uiText("جارٍ المعالجة…"):message}</p></section>;
}

export function ChangeManagerPassword({client}){
 const [current,setCurrent]=useState(''),[next,setNext]=useState(''),[confirm,setConfirm]=useState(''),[busy,setBusy]=useState(false),[message,setMessage]=useState('');
 async function submit(event){
   event.preventDefault();if(busy)return;
   if(next!==confirm || next.length<12 || new TextEncoder().encode(next).length>72){setMessage('تحقق من طول كلمة المرور وتطابق التأكيد.');return;}
   setBusy(true);setMessage('');
   try{
     const {data,error:identityError}=await client.auth.getUser();
     if(identityError||!data?.user?.email)throw Error();
     const verifier=createClient(import.meta.env.VITE_SUPABASE_URL,import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,{
       auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false,storageKey:'manager-password-confirmation'}
     });
     try{
       const verification=await verifier.auth.signInWithPassword({email:data.user.email,password:current});
       if(verification.error||verification.data?.user?.id!==data.user.id)throw Error();
       const {error}=await verifier.auth.updateUser({password:next,current_password:current});
       if(error)throw error;
     }finally{await verifier.auth.signOut({scope:'local'}).catch(()=>{});}
     setCurrent('');setNext('');setConfirm('');setMessage('تم تحديث كلمة المرور.');
   }catch{setMessage('تعذّر تغيير كلمة المرور. تحقق من كلمة المرور الحالية ومن الجلسة.');}
   finally{setBusy(false);}
 }
 return <form className="adminSettingsCard" onSubmit={submit}><h4>{uiText("تغيير كلمة المرور")}</h4>
 <label>{uiText("كلمة المرور الحالية")}<input autoComplete="current-password" type="password" value={current} required onChange={e=>setCurrent(e.target.value)}/></label>
 <label>{uiText("كلمة المرور الجديدة")}<input autoComplete="new-password" type="password" minLength={12} required value={next} onChange={e=>setNext(e.target.value)}/></label>
 <label>{uiText("تأكيد كلمة المرور")}<input autoComplete="new-password" type="password" required value={confirm} onChange={e=>setConfirm(e.target.value)}/></label>
 <button disabled={busy} type="submit">{uiText("حفظ كلمة المرور")}</button><p role="status">{message}</p></form>;
}
