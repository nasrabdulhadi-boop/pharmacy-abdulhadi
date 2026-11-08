import React,{useEffect,useRef,useState} from 'react';
import {saveOwnQaProfile,requestOwnQaEmailChange,signOutOtherQaSessions} from './systemAdminProfileActions.js';
import {localizeAdminTree} from './systemAdminLocale.js';

const errors={invalid_name:'اسم العرض غير صالح.',invalid_email:'البريد الإلكتروني غير صالح.',unchanged_email:'البريد الجديد مطابق لبريدك الحالي.',rate_limited:'تم بلوغ حد الطلبات؛ انتظر قبل المحاولة مجدداً.'};
export default function QaProfileDetails({client,projectUrl,previewEnabled,user,language='ar'}){
 const [name,setName]=useState(user?.user_metadata?.full_name||''),[email,setEmail]=useState(''),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[failed,setFailed]=useState(false);
 const generation=useRef(0),pending=useRef(false);
 useEffect(()=>{generation.current++;setName(user?.user_metadata?.full_name||'');setEmail('');setMessage('');setBusy(false);return()=>{generation.current++};},[user?.id]);
 const enabled=previewEnabled===true&&!!user?.id;
 const run=async(action,success)=>{
  if(!enabled||pending.current)return;
  const current=generation.current;pending.current=true;setBusy(true);setMessage('');setFailed(false);
  try{await action({client,projectUrl,previewEnabled,expectedUserId:user.id});if(current===generation.current){setMessage(success);setEmail('');}}
  catch(error){if(current===generation.current){setFailed(true);setMessage(errors[error.message]||'تعذر إكمال الطلب. تحقق من الجلسة أو حاول لاحقاً.');}}
  finally{pending.current=false;if(current===generation.current)setBusy(false);}
 };
 return localizeAdminTree(<section className="systemAdminRecovery" aria-label="بيانات حسابي">
  <form onSubmit={e=>{e.preventDefault();run(options=>saveOwnQaProfile({...options,name}),'تم حفظ اسم العرض.');}}>
   <label>اسم العرض<input autoComplete="name" required maxLength={100} value={name} onChange={e=>setName(e.target.value)} disabled={!enabled||busy}/></label>
   <button type="submit" disabled={!enabled||busy||!name.trim()}>{busy?'جارٍ الحفظ…':'حفظ اسم العرض'}</button>
  </form>
  <form onSubmit={e=>{e.preventDefault();const origin=window.location.origin;run(options=>requestOwnQaEmailChange({...options,email,origin,redirectTo:origin+'/#admin'}),'تم قبول الطلب. أكمل التأكيد المطلوب عبر البريد القديم والجديد حسب إعدادات الخدمة. لم يتم التحقق من وصول الرسائل.');}}>
   <h4>تغيير البريد الإلكتروني</h4><p>تغيير البريد يتطلب التأكيد عبر البريد.</p>
   <label>البريد الجديد<input type="email" required maxLength={254} autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)} disabled={!enabled||busy}/></label>
   <button type="submit" disabled={!enabled||busy||!email.trim()}>طلب تأكيد البريد الجديد</button>
  </form>
  <h4>أمان الجلسات</h4>
  <button type="button" disabled={!enabled||busy} onClick={()=>run(signOutOtherQaSessions,'تم إنهاء جلساتك الأخرى؛ جلستك الحالية مستمرة.')}>إنهاء الجلسات الأخرى</button>
  {message&&<p role={failed?'alert':'status'}>{message}</p>}
 </section>,language);
}
