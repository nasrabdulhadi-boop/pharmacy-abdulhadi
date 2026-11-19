import {uiText,uiTemplate,getSystemDirection} from './systemLocale.js';
import React,{useState} from 'react';
import {saveRecoveredPassword} from './passwordRecoveryFlow.js';

export default function RecoveryPasswordForm({auth,enabled,recoveryState,onDone,onRestart,isInvitation=false}){
 const [password,setPassword]=useState(''),[confirmation,setConfirmation]=useState('');
 const [busy,setBusy]=useState(false),[result,setResult]=useState(null);
 const submit=async event=>{
  event.preventDefault();if(busy||result?.ok)return;setBusy(true);setResult(null);
  const next=await saveRecoveredPassword({auth,password,confirmation,enabled,recoveryState});
  if(next.ok){setPassword('');setConfirmation('')}
  setResult(next);setBusy(false);
 };
 return <div className="login" dir={getSystemDirection()}><form onSubmit={submit}>
  <img className="loginLogo" src="/logo.png" alt={uiText("شعار صيدلية عبدالهادي")}/>
  <h1>{isInvitation?uiText('قبول الدعوة وتعيين كلمة المرور'):uiText('تعيين كلمة مرور جديدة')}</h1><p>{uiText("حساب النسخة التجريبية QA فقط")}</p>
  {result?.ok?<><p role="status">{uiText(result.message)}</p><button type="button" className="primary full" onClick={onDone}>{uiText("متابعة إلى النظام")}</button></>:<>
   <label>{uiText("كلمة المرور الجديدة")}<input type="password" autoComplete="new-password" minLength={12} maxLength={72} value={password} onChange={e=>setPassword(e.target.value)} required disabled={busy}/></label>
   <label>{uiText("تأكيد كلمة المرور")}<input type="password" autoComplete="new-password" minLength={12} maxLength={72} value={confirmation} onChange={e=>setConfirmation(e.target.value)} required disabled={busy}/></label>
   <p>{uiText("استخدم 12 محرفاً على الأقل، واحفظ كلمة المرور لديك.")}</p>
   {result&&<p className="error" role="alert">{uiText(result.message)}</p>}
   <button className="primary full" disabled={busy||!enabled}>{busy?uiText('جارٍ الحفظ…'):uiText('حفظ كلمة المرور')}</button>
   <button type="button" onClick={onRestart} disabled={busy}>{uiText("طلب رابط استرداد جديد")}</button>
  </>}
 </form></div>;
}
