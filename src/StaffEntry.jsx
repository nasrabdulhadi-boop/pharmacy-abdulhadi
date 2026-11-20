import React,{useEffect,useRef,useState} from 'react';
import {createRoot} from 'react-dom/client';
import {createClient} from '@supabase/supabase-js';
import ManagerRecovery,{mailboxClient} from './ManagerRecovery.jsx';
import {allSections,call} from './StaffCenter.jsx';
import './style.css';
import './REDESIGN_V6_3.css';
import './REDESIGN_V6_3_REAL.css';
import './CenterLayout.css';
const q=new URLSearchParams(location.search),mode=q.get('workspace');
const token=new URLSearchParams(location.hash.slice(1)).get('access_token');
if(token)history.replaceState({},'',location.pathname+location.search);
const client=createClient(import.meta.env.VITE_SUPABASE_URL,import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,{auth:{detectSessionInUrl:false,...(mode==='staff'?{storageKey:'pharmacy-staff-session'}:{})}});
function Recovery(){
 const [proof,setProof]=useState(undefined);
 useEffect(()=>{if(!token){setProof(null);return;}mailboxClient().auth.getUser(token).then(({data})=>setProof(data.user?{proof:token,email:data.user.email}:null));},[]);
 return <main dir="rtl" className="panel centerLayout systemAdminModern">{proof!==undefined&&<ManagerRecovery client={client} link={mode==='mail'&&q.get('mode')==='link'} callback={proof}/>}<a href="/#admin">العودة إلى دخول المدير</a></main>;
}
function Operations({section,rows,refresh}){
 const [cart,setCart]=useState([]),[msg,message]=useState(''),[busy,setBusy]=useState(false);
 const lock=useRef(false),request=useRef(null);
 async function commit(op,payload){
  if(lock.current)return;lock.current=true;setBusy(true);const fingerprint=JSON.stringify([op,payload]);
  if(request.current?.fingerprint!==fingerprint)request.current={fingerprint,id:crypto.randomUUID()};
  try{const value=await call(client,{action:'command',request:request.current.id,op,payload});request.current=null;setCart([]);message(op==='sale'?'تم البيع · '+value.result.total+' ل.س':'تم الحفظ');refresh();}
  catch(e){message(e.message);}finally{lock.current=false;setBusy(false);}
 }
 return <>{section==='products'&&<form onSubmit={e=>{e.preventDefault();const f=new FormData(e.currentTarget);commit('add_product',{name:f.get('name'),barcode:f.get('barcode'),price:f.get('price')});}}><h4>إضافة صنف</h4><label>اسم الصنف<input name="name" required maxLength={160}/></label><label>الباركود<input required name="barcode" maxLength={80}/></label><label>سعر البيع بالليرة<input required type="number" min="0" name="price"/></label><button disabled={busy}>حفظ الصنف</button></form>}
 {section==='debtors'&&<form onSubmit={e=>{e.preventDefault();const name=new FormData(e.currentTarget).get('name');commit('add_debtor',{name});}}><label>اسم المتدين الجديد<input name="name" required maxLength={120}/></label><button disabled={busy}>إضافة متدين</button></form>}
 {section==='pos'&&<div className="adminSettingsCard"><h4>الفاتورة النقدية</h4>{cart.map(x=><p key={x.product_id}>{x.name} × {x.quantity} <button disabled={busy} onClick={()=>setCart(cart.filter(r=>r!==x))}>إزالة</button></p>)}<button className="primary" disabled={!cart.length||busy} onClick={()=>commit('sale',{items:cart.map(({product_id,quantity,expected_price})=>({product_id,quantity,expected_price}))})}>تأكيد البيع النقدي · {cart.reduce((a,x)=>a+Number(x.expected_price)*x.quantity,0).toLocaleString('ar-SY')} ل.س</button></div>}
 {msg&&<p role="status">{msg}</p>}<div style={{overflowX:'auto'}}><table><thead><tr>{Object.keys(rows[0]||{}).filter(k=>k!=='id').map(k=><th key={k}>{k}</th>)}{['pos','debtors'].includes(section)&&<th>الإجراء</th>}</tr></thead><tbody>{rows.map((r,i)=><tr key={r.id||i}>{Object.entries(r).filter(([k])=>k!=='id').map(([k,v])=><td key={k}>{v??'—'}</td>)}{section==='pos'&&<td><button disabled={busy||Number(r['الرصيد المتاح'])<1} onClick={()=>setCart(prev=>{const old=prev.find(x=>x.product_id===r.id);if((old?.quantity??0)>=Number(r['الرصيد المتاح']))return prev;return [...prev.filter(x=>x!==old),{product_id:r.id,name:r['الصنف'],expected_price:r['البيع بالليرة'],quantity:(old?.quantity??0)+1}];})}>إضافة للفاتورة</button></td>}
 {section==='debtors'&&<td><form onSubmit={e=>{e.preventDefault();commit('pay_debtor',{id:r.id,amount:Number(new FormData(e.currentTarget).get('amount'))});}}><input required type="number" name="amount" min="1" max={Number(r['الرصيد بالليرة'])} aria-label={'دفعة نقدية من '+r['الاسم']}/><button disabled={busy||Number(r['الرصيد بالليرة'])<=0}>تسجيل دفعة</button></form></td>}</tr>)}</tbody></table></div></>;
}
function Workspace({user}){
 const [mobile,setMobile]=useState(false);
 const [identity,setIdentity]=useState(null),[section,choose]=useState(''),[search,setSearch]=useState(''),[revision,refresh]=useState(0),[rows,setRows]=useState(null),[error,setError]=useState('');
 useEffect(()=>{let live=true;async function read(){try{const r=await call(client,{action:'view'});if(live)setIdentity(r);}catch{if(live)setIdentity({sections:[],name:user.email});}}read();const t=setInterval(read,8000);return()=>{live=false;clearInterval(t);};},[user.id]);
 const active=identity?.sections.includes(section)?section:identity?.sections[0]||'';
 useEffect(()=>{let live=true;setRows(null);setError('');if(active)call(client,{action:'view',section:active,search}).then(r=>{if(live)setRows(r.rows);}).catch(e=>{if(live)setError(e.message);});return()=>{live=false;};},[active,search,revision]);
 return <div className="adminShell" dir="rtl"><aside className={mobile?'open':''}><div className="sideBrand"><img className="sideLogo" src="/logo.png" alt=""/><div><b>صيدلية عبدالهادي</b><span>{identity?.name}</span></div></div>
 <nav className="navGroup">{Object.entries(allSections).map(([id,label])=><button disabled={!identity?.sections.includes(id)} aria-current={active===id?'page':undefined} key={id} onClick={()=>{choose(id);setSearch('');setMobile(false);}}>{label}</button>)}</nav><button onClick={()=>client.auth.signOut()}>تسجيل الخروج</button></aside><main className="adminMain"><div className="mobileBar"><button onClick={()=>setMobile(!mobile)}>الأقسام</button></div><section className="panel systemAdminModern centerLayout">
 {active?<><h3>{allSections[active]}</h3>{active!=='diagnostics'&&<label>بحث<input value={search} onChange={e=>setSearch(e.target.value)}/></label>}{error&&<p role="alert">{error}</p>}<Operations key={active} section={active} rows={rows||[]} refresh={()=>refresh(v=>v+1)}/></>:<p>{identity?'لم يمنح المدير صلاحيات لهذا الحساب.':'جارٍ التحقق من الصلاحيات…'}</p>}</section></main></div>;
}
function Staff(){
 const [user,setUser]=useState(null),[error,setError]=useState('');
 useEffect(()=>{const {data}=client.auth.onAuthStateChange((_,s)=>setUser(s?.user));return()=>data.subscription.unsubscribe();},[]);
 if(user)return <Workspace key={user.id} user={user}/>;
 return <main className="login"><form onSubmit={async e=>{e.preventDefault();const f=new FormData(e.currentTarget);const r=await client.auth.signInWithPassword({email:String(f.get('email')).trim(),password:String(f.get('pass'))});if(r.error)setError('تعذّر تسجيل الدخول.');}}><img className="loginLogo" src="/logo.png" alt=""/><h1>دخول الموظفين والدعم الفني</h1><input name="email" type="email" required placeholder="البريد الإلكتروني"/><input name="pass" type="password" required placeholder="كلمة المرور"/><button>دخول</button><p role="alert">{error}</p><a href="/#admin">دخول المدير</a></form></main>;
}
createRoot(document.getElementById('root')).render(mode==='staff'?<Staff/>:<Recovery/>);
