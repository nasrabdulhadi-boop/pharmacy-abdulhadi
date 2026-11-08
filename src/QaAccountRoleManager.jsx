import {uiText,uiTemplate} from './systemLocale.js';
import React,{useEffect,useRef,useState} from 'react';
import QaAccountInvitation from './QaAccountInvitation.jsx';
import {localizeAdminTree} from './systemAdminLocale.js';
import {ISOLATED_QA_PROJECT_URL} from './stagingAuthGuard.js';
const labels={system_owner:'مالك النظام',system_admin:'مدير النظام',employee:'موظف',technical_support:'دعم فني',disabled:'موقوف'};
export default function QaAccountRoleManager({client,projectUrl,actorId,actorRole,language='ar'}){
 const enabled=projectUrl===ISOLATED_QA_PROJECT_URL&&['system_owner','system_admin'].includes(actorRole);
 const [rows,setRows]=useState([]),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[choices,setChoices]=useState({});
 const generation=useRef(0),saving=useRef(false);
 const [reloadVersion,setReloadVersion]=useState(0);
 useEffect(()=>{const current=++generation.current;setRows([]);setChoices({});setMessage('');
  if(!enabled)return;
  setBusy(true);client.rpc('qa_admin_accounts').then(({data,error})=>{if(current!==generation.current)return;if(error||!Array.isArray(data))setMessage('تعذر تحميل الحسابات؛ تحقق من صلاحية الجلسة وتجهيز خدمة QA.');else setRows(data);}).catch(()=>{if(current===generation.current)setMessage('تعذر الاتصال بخدمة الحسابات.');}).finally(()=>{if(current===generation.current)setBusy(false);});
  return()=>{generation.current++};
 },[client,enabled,actorId,actorRole,reloadVersion]);
 if(!enabled)return null;
 const options=actorRole==='system_owner'?['employee','technical_support','system_admin','disabled']:['employee','technical_support','disabled'];
 const save=async row=>{if(busy||saving.current||!options.includes(choices[row.id]))return;const current=generation.current;saving.current=true;setBusy(true);setMessage('');
  try{const {data,error}=await client.rpc('qa_admin_set_role',{p_user_id:row.id,p_role:choices[row.id]});if(current!==generation.current)return;if(error){setMessage('لم يُعتمد التغيير. قد تكون الجلسة أو صلاحية الحساب غير مناسبة.');return;}if(data!==true){setMessage(data===false?'الدور مطابق للحالي؛ لم يحدث تغيير أو إلغاء جديد للجلسات.':'لم يصل تأكيد صالح من الخادم. أعد تحميل الحسابات للتحقق.');return;}setRows(old=>old.map(x=>x.id===row.id?{...x,system_role:choices[row.id]}:x));setMessage('اعتمد الدور وسُجل في مركز الأمان وأُلغيت جلسات الحساب.');}
  catch{if(current===generation.current)setMessage('تعذر تأكيد التغيير. أعد تحميل الحسابات قبل المحاولة مجدداً.');}
  finally{saving.current=false;if(current===generation.current)setBusy(false);}
 };
 return localizeAdminTree(<section aria-label={uiText("إدارة حسابات QA")}><h4>{uiText("إدارة الحسابات — QA فقط")}</h4><QaAccountInvitation client={client} projectUrl={projectUrl} actorId={actorId} actorRole={actorRole} language={language} onPrepared={()=>setReloadVersion(v=>v+1)}/><button type="button" disabled={busy} onClick={()=>setReloadVersion(v=>v+1)}>{uiText("إعادة تحميل الحسابات")}</button><p>{uiText("تغيير الدور ينهي جلسات الحساب.")}</p>{uiText(message)&&<p role="status">{uiText(message)}</p>}{busy&&<p role="status">{uiText("جارٍ التحقق…")}</p>}<div style={{overflowX:'auto'}}><table><thead><tr><th>{uiText("الحساب")}</th><th>{uiText("الدور الحالي")}</th><th>{uiText("الدور الجديد")}</th><th>{uiText("الاعتماد")}</th></tr></thead><tbody>{rows.map(row=>{const protectedRow=row.id===actorId||row.system_role==='system_owner'||(actorRole==='system_admin'&&row.system_role==='system_admin');return <tr key={row.id}><td dir="ltr">{row.email}</td><td>{uiText(labels[row.system_role])||uiText('بلا دور معتمد')}</td><td>{protectedRow?uiText('حساب محمي'):<select aria-label={(language==='en'?'New role for ':uiText('الدور الجديد لحساب '))+row.email} value={choices[row.id]||''} disabled={busy} onChange={e=>setChoices(old=>({...old,[row.id]:e.target.value}))}><option value="">{uiText("اختر الدور")}</option>{options.map(role=><option key={role} value={role}>{uiText(labels[role])}</option>)}</select>}</td><td><button type="button" disabled={busy||protectedRow||!choices[row.id]||choices[row.id]===row.system_role} onClick={()=>save(row)}>{uiText("اعتماد الدور وإلغاء جلساته")}</button></td></tr>})}</tbody></table></div></section>,language);
}
