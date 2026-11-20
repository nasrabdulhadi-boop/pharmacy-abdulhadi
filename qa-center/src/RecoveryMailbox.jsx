import React,{useEffect,useState} from 'react';
export default function RecoveryMailbox({client,link=false}){
 const [email,setEmail]=useState(''),[code,setCode]=useState(''),[password,setPassword]=useState(''),[sent,setSent]=useState(false),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[saved,setSaved]=useState('');
 useEffect(()=>{let active=true;if(link)client.from('qa_verified_recovery_mailboxes').select('email').maybeSingle().then(({data})=>{if(active)setSaved(data?.email||'');});return ()=>{active=false;};},[client,link]);
 async function run(){
  setBusy(true);setMessage('');
  try{
   if(!sent){
    const {error}=await client.auth.signInWithOtp({email:email.trim(),options:{shouldCreateUser:link,emailRedirectTo:location.origin+'/#admin'}});
    if(error)throw error;
    setSent(true);setMessage('أدخل رمز التحقق المرسل إلى هذا البريد.');
   }else{
    const {error,data}=await client.functions.invoke('qa-recovery-mailbox',{body:{action:link?'link':'reset',email:email.trim(),password,code}});
    if(error||!data?.ok)throw Error();
    if(link)setSaved(email.trim());
    setSent(false);setPassword('');setCode('');setMessage(link?'تم تأكيد بريد الاسترداد وحفظه.':'تم تغيير كلمة المرور. يمكنك تسجيل الدخول الآن.');
   }
  }catch{setMessage('تعذّر إتمام الخطوة. تحقق من البريد والرمز وكلمة المرور ثم حاول مجدداً.');}finally{setBusy(false);}
 }
 return <section className="adminSettingsCard"><h4>{link?'بريد الاسترداد الاحتياطي':'استعادة حساب المدير بالبريد الاحتياطي'}</h4>
 {saved&&<p>البريد المؤكد · <bdi>{saved}</bdi></p>}
 <label>البريد الاحتياطي<input type="email" autoComplete="off" value={email} disabled={busy} onChange={e=>{setEmail(e.target.value);setSent(false);setCode('');}}/></label>
 {sent&&<><label>رمز البريد<input value={code} inputMode="numeric" autoComplete="one-time-code" onChange={e=>setCode(e.target.value.trim())}/></label>
 <label>{link?'كلمة مرور المدير الحالية':'كلمة مرور جديدة (١٢ محرفاً على الأقل)'}<input type="password" autoComplete={link?'current-password':'new-password'} value={password} onChange={e=>setPassword(e.target.value)}/></label></>}
 <button type="button" disabled={busy||!email.trim()||(sent&&(!password||!code))} onClick={run}>{sent?(link?'تأكيد وربط البريد':'اعتماد كلمة المرور'):'إرسال رمز التحقق'}</button>
 {sent&&<button type="button" disabled={busy} onClick={()=>{setCode('');setSent(false);}}>طلب رمز جديد</button>}
 <p role="status">{message}</p></section>;
}
