import {staffClient} from './staffClient.js';
import {getSystemDirection} from './systemLocale.js';
import React,{useEffect,useState} from 'react';
import {createClient} from '@supabase/supabase-js';
import ManagerRecovery,{mailboxClient} from './ManagerRecovery.jsx';
import {call} from './StaffCenter.jsx';
import './style.css';
import './REDESIGN_V6_3.css';
import './REDESIGN_V6_3_REAL.css';
import './CenterLayout.css';
const q=new URLSearchParams(location.search),mode=q.get('workspace');
const isRecovery=['recover','mail'].includes(mode);
const token=isRecovery&&new URLSearchParams(location.hash.slice(1)).get('access_token');
if(token)history.replaceState({},'',location.pathname+location.search);
const recoveryClient=!isRecovery?null:createClient(import.meta.env.VITE_SUPABASE_URL,import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,{auth:{detectSessionInUrl:false,...(mode==='staff'?{storageKey:'pharmacy-staff-session'}:{})}});
const client=mode==='staff'?staffClient:recoveryClient;
function Recovery(){
 const [proof,setProof]=useState(undefined);
 useEffect(()=>{if(!token){setProof(null);return;}mailboxClient().auth.getUser(token).then(({data})=>setProof(data.user?{proof:token,email:data.user.email}:null));},[]);
 return <main dir={getSystemDirection()} className="panel centerLayout systemAdminModern">{proof!==undefined&&<ManagerRecovery client={client} link={mode==='mail'&&q.get('mode')==='link'} callback={proof}/>}<a href="/#admin">العودة إلى دخول المدير</a></main>;
}
function StaffShell({Shell,user}){
 const [access,setAccess]=useState(null),[error,setError]=useState('');
 useEffect(()=>{let active=true;const read=()=>call(client,{action:'view'}).then(r=>{if(active){setAccess(r);setError('');}}).catch(e=>{if(active){setAccess(null);setError(e.message);}});read();const id=setInterval(read,8000);return()=>{active=false;clearInterval(id);};},[user.id]);
 if(!access)return <main dir={getSystemDirection()}>{error||'جارٍ تحميل الصلاحيات…'} <button onClick={()=>client.auth.signOut()}>خروج</button></main>;
 return <Shell staff={access} onLogout={()=>client.auth.signOut()}/>;
}
export function Staff({Shell}){
 const [user,setUser]=useState(null),[error,setError]=useState('');
 useEffect(()=>{const {data}=client.auth.onAuthStateChange((_,s)=>setUser(s?.user));return()=>data.subscription.unsubscribe();},[]);
 if(user)return <StaffShell key={user.id} Shell={Shell} user={user}/>;
 return <main className="login"><form onSubmit={async e=>{e.preventDefault();const f=new FormData(e.currentTarget);const r=await client.auth.signInWithPassword({email:String(f.get('email')).trim(),password:String(f.get('pass'))});if(r.error)setError('تعذّر تسجيل الدخول.');}}><img className="loginLogo" src="/logo.png" alt=""/><h1>دخول الموظفين والدعم الفني</h1><input name="email" type="email" required placeholder="البريد الإلكتروني"/><input name="pass" type="password" required placeholder="كلمة المرور"/><button>دخول</button><p role="alert">{error}</p><a href="/#admin">دخول المدير</a></form></main>;
}
export {Recovery};
