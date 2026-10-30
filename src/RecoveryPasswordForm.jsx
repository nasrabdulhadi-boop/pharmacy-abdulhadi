import React,{useState} from 'react';
import {saveRecoveredPassword} from './passwordRecoveryFlow.js';

export default function RecoveryPasswordForm({auth,enabled,recoveryState,onDone,onRestart}){
 const [password,setPassword]=useState(''),[confirmation,setConfirmation]=useState('');
 const [busy,setBusy]=useState(false),[result,setResult]=useState(null);
 const submit=async event=>{
  event.preventDefault();if(busy||result?.ok)return;setBusy(true);setResult(null);
  const next=await saveRecoveredPassword({auth,password,confirmation,enabled,recoveryState});
  if(next.ok){setPassword('');setConfirmation('')}
  setResult(next);setBusy(false);
 };
 return <div className="login" dir="rtl"><form onSubmit={submit}>
  <img className="loginLogo" src="/logo.png" alt="شعار صيدلية عبدالهادي"/>
  <h1>تعيين كلمة مرور جديدة</h1><p>حساب النسخة التجريبية QA فقط</p>
  {result?.ok?<><p role="status">{result.message}</p><button type="button" className="primary full" onClick={onDone}>متابعة إلى النظام</button></>:<>
   <label>كلمة المرور الجديدة<input type="password" autoComplete="new-password" minLength={12} value={password} onChange={e=>setPassword(e.target.value)} required disabled={busy}/></label>
   <label>تأكيد كلمة المرور<input type="password" autoComplete="new-password" minLength={12} value={confirmation} onChange={e=>setConfirmation(e.target.value)} required disabled={busy}/></label>
   <p>استخدم 12 محرفاً على الأقل، واحفظ كلمة المرور لديك.</p>
   {result&&<p className="error" role="alert">{result.message}</p>}
   <button className="primary full" disabled={busy||!enabled}>{busy?'جارٍ الحفظ…':'حفظ كلمة المرور'}</button>
   <button type="button" onClick={onRestart} disabled={busy}>طلب رابط استرداد جديد</button>
  </>}
 </form></div>;
}
