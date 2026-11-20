import React,{useEffect,useState} from 'react';
import {createClient} from '@supabase/supabase-js';
import {call} from './StaffCenter.jsx';
export function mailboxClient(){return createClient(import.meta.env.VITE_SUPABASE_URL,import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,{auth:{storageKey:'abdulhadi-recovery-proof',flowType:'implicit',persistSession:false,detectSessionInUrl:false,autoRefreshToken:false}});}
export default function ManagerRecovery({client,link=false,callback=null}){
 const [email,setEmail]=useState(callback?.email||''),[password,setPass]=useState(''),[code,setCode]=useState(''),[sent,setSent]=useState(!!callback),[message,setMessage]=useState(''),[busy,setBusy]=useState(false),[saved,setSaved]=useState('');
 useEffect(()=>{if(link)call(client,{action:'contact'}).then(r=>setSaved(r.email)).catch(()=>setMessage('تعذّر تحميل بريد الاسترداد.'));},[client,link]);
 async function run(){setBusy(true);setMessage('');
 try{if(!sent){
 if(link)await call(client,{action:'prepareMailbox',email,current:password});
 const auth=mailboxClient();const r=await auth.auth.signInWithOtp({email,options:{shouldCreateUser:false,emailRedirectTo:location.origin+'/?workspace=mail&mode='+(link?'link':'recover')}});if(r.error)throw r.error;
 setSent(true);setMessage('افتح رابط الرسالة في هذا المتصفح أو أدخل رمزها هنا.');
 }else{await call(client,{action:link?'link':'recover',email,password,code,proof:callback?.proof});setPass('');setCode('');setSent(false);if(link)setSaved(email);setMessage(link?'تم تأكيد بريد الاسترداد.':'تم تغيير كلمة مرور المدير.');}}
 catch{setMessage('تعذّرت العملية. تحقق من البريد وكلمة المرور وصلاحية رسالة التأكيد.');}finally{setBusy(false);}}
 return <section className="adminSettingsCard"><h4>{link?'بريد الاسترداد الاحتياطي':'استرداد حساب المدير'}</h4>{saved&&<p>البريد المؤكّد · <bdi>{saved}</bdi></p>}
 <label>البريد الاحتياطي<input type="email" value={email} disabled={sent} onChange={e=>setEmail(e.target.value.trim().toLowerCase())}/></label>
 {(sent||link)&&<label>{link?'كلمة مرور المدير الحالية':'كلمة المرور الجديدة (١٢ محرفاً على الأقل)'}<input type="password" value={password} onChange={e=>setPass(e.target.value)} autoComplete={link?'current-password':'new-password'}/></label>}
 {sent&&!callback&&<label>رمز البريد<input value={code} autoComplete="one-time-code" onChange={e=>setCode(e.target.value.trim())}/></label>}
 <button type="button" disabled={busy||!email||(link&&!password)||(sent&&(!password||(!code&&!callback)))} onClick={run}>{sent?'اعتماد التأكيد':'إرسال رسالة التحقق'}</button>
 {!callback&&sent&&<button type="button" onClick={()=>setSent(false)}>تغيير البريد أو إعادة الإرسال</button>}<p role="status">{message}</p></section>;
}
