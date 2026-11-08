import {uiText,uiTemplate} from './systemLocale.js';
import React,{useEffect,useRef,useState} from 'react';
import {prepareQaInvitation,invitationRequestId} from './qaAccountInvitations.js';
import {localizeAdminTree} from './systemAdminLocale.js';
import {ISOLATED_QA_PROJECT_URL} from './stagingAuthGuard.js';
const errors={invalid_email:'البريد الإلكتروني غير صالح.',invitation_conflict:'الحساب موجود أو توجد دعوة قيد التجهيز. حدّث قائمة الحسابات قبل المحاولة مجدداً.',rate_limited:'بلغت حد الدعوات المؤقت؛ حاول لاحقاً.',not_authorized:'الجلسة أو صلاحية الدعوة غير مناسبة.'};
export default function QaAccountInvitation({client,projectUrl,actorId,actorRole,language='ar',onPrepared}){
 const [email,setEmail]=useState(''),[role,setRole]=useState('employee'),[busy,setBusy]=useState(false),[prepared,setPrepared]=useState(null),[message,setMessage]=useState('');
 const generation=useRef(0),locked=useRef(false);
 useEffect(()=>{generation.current++;setEmail('');setRole('employee');setPrepared(null);setMessage('');setBusy(false);return()=>{generation.current++;};},[actorId,actorRole,projectUrl]);
 const enabled=projectUrl===ISOLATED_QA_PROJECT_URL&&!!actorId&&['system_owner','system_admin'].includes(actorRole);if(!enabled)return null;
 const submit=async event=>{
  event.preventDefault();if(locked.current)return;locked.current=true;setBusy(true);setPrepared(null);setMessage('');const current=generation.current;
  try{const result=await prepareQaInvitation({client,projectUrl,actorId,actorRole,email,role,origin:window.location.origin,requestId:invitationRequestId()});
   if(current===generation.current){setPrepared(result);setEmail('');setMessage('تم تجهيز الدعوة وتسجيلها. لم تُرسل رسالة بريد.');onPrepared?.();}
  }catch(error){if(current===generation.current)setMessage(errors[error.message]||'تعذر تأكيد الدعوة. حدّث قائمة الحسابات قبل إعادة المحاولة.');}
  finally{locked.current=false;if(current===generation.current)setBusy(false);}
 };
 return localizeAdminTree(<section className="systemAdminRecovery" aria-label={uiText("دعوة حساب جديد")}>
  <h4>{uiText("دعوة حساب جديد — QA فقط")}</h4><p>{uiText("رابط لمرة واحدة، تُسلّمه للمستخدم دون إرسال بريد.")}</p>
  <form onSubmit={submit}>
   <label>{uiText("بريد الحساب الجديد")}<input type="email" autoComplete="off" required maxLength={254} value={email} onChange={e=>setEmail(e.target.value)} disabled={busy}/></label>
   <label>{uiText("دور الحساب الجديد")}<select value={role} onChange={e=>setRole(e.target.value)} disabled={busy}><option value="employee">{uiText("موظف")}</option><option value="technical_support">{uiText("دعم فني")}</option>{actorRole==='system_owner'&&<option value="system_admin">{uiText("مدير النظام")}</option>}</select></label>
   <button type="submit" disabled={busy||!email.trim()}>{busy?uiText('جارٍ تجهيز الدعوة…'):uiText('تجهيز رابط دعوة')}</button>
  </form>
  {uiText(message)&&<p role="status">{uiText(message)}</p>}
  {prepared&&<div><p>{uiText("الرابط يمنح الدخول للحساب المدعو؛ سلّمه بأمان.")}</p><label>{uiText("رابط الدعوة")}<textarea data-no-translate readOnly dir="ltr" autoComplete="off" value={prepared.link} style={{width:'100%',minHeight:90,overflowWrap:'anywhere'}} onFocus={e=>e.target.select()}/></label><button type="button" onClick={()=>{setPrepared(null);setMessage('أُخفي رابط الدعوة من هذه الشاشة.');}}>{uiText("إخفاء الرابط")}</button></div>}
 </section>,language);
}
