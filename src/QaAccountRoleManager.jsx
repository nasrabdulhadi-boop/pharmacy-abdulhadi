import {uiText,uiTemplate} from './systemLocale.js';
import {Users,UserPlus,RefreshCw,KeyRound,Link2} from 'lucide-react';
import React,{useEffect,useRef,useState} from 'react';
import QaStaffAccountDialog from './QaStaffAccountDialog.jsx';
import QaStaffAccountEditor from './QaStaffAccountEditor.jsx';
import './STAFF_ACCOUNTS.css';
import QaAccountInvitation from './QaAccountInvitation.jsx';
import {localizeAdminTree} from './systemAdminLocale.js';
import {ISOLATED_QA_PROJECT_URL} from './stagingAuthGuard.js';
const labels={system_owner:'مالك النظام',system_admin:'مدير النظام',employee:'موظف',technical_support:'دعم فني',disabled:'موقوف'};
export default function QaAccountRoleManager({client,projectUrl,actorId,actorRole,language='ar'}){
 const enabled=projectUrl===ISOLATED_QA_PROJECT_URL&&['system_owner','system_admin'].includes(actorRole);
 const [rows,setRows]=useState([]),[busy,setBusy]=useState(false),[message,setMessage]=useState(''),[choices,setChoices]=useState({});
 const [editor,setEditor]=useState(null);
 const generation=useRef(0),saving=useRef(false);
 const [reloadVersion,setReloadVersion]=useState(0);
 useEffect(()=>{setEditor(null)},[actorId,actorRole,projectUrl]);
 useEffect(()=>{const current=++generation.current;setRows([]);setChoices({});setMessage('');
  if(!enabled){setEditor(null);return;}
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
 return localizeAdminTree(<section aria-label={uiText("إدارة حسابات QA")}><div className="adminAccountsHeading"><div className="adminSectionTitle"><span className="adminTitleIcon"><Users size={23}/></span><h4>{uiText("إدارة الحسابات — QA فقط")}</h4></div><button className="adminAction adminActionPrimary" type="button" disabled={busy} onClick={()=>setEditor({create:true})}><UserPlus size={18}/>{uiText("إضافة موظف أو فني")}</button></div>{editor&&(editor.create?<QaStaffAccountEditor key={actorId+':create'} client={client} projectUrl={projectUrl} actorId={actorId} actorRole={actorRole} onCancel={()=>setEditor(null)} onSaved={()=>setReloadVersion(v=>v+1)}/>:<QaStaffAccountDialog key={actorId+':'+editor.id} client={client} projectUrl={projectUrl} actorId={actorId} actorRole={actorRole} row={editor} onClose={()=>setEditor(null)} onSaved={()=>setReloadVersion(v=>v+1)}/>)}<details className="adminInvitationDisclosure"><summary><Link2 size={20}/><span>{uiText("دعوة برابط بدلاً من كلمة مرور")}</span></summary><QaAccountInvitation client={client} projectUrl={projectUrl} actorId={actorId} actorRole={actorRole} language={language} onPrepared={()=>setReloadVersion(v=>v+1)}/></details><div className="adminAccountsToolbar"><button className="adminAction adminActionSecondary" type="button" disabled={busy} onClick={()=>setReloadVersion(v=>v+1)}><RefreshCw size={17}/>{uiText("إعادة تحميل الحسابات")}</button><p>{uiText("تغيير الدور ينهي جلسات الحساب.")}</p></div>{uiText(message)&&<p role="status">{uiText(message)}</p>}{busy&&<p role="status">{uiText("جارٍ التحقق…")}</p>}<div style={{overflowX:'auto'}}><table><thead><tr><th>{uiText("الحساب")}</th><th>{uiText("الدور الحالي")}</th><th>{uiText("الدور الجديد")}</th><th>{uiText("الاعتماد")}</th></tr></thead><tbody>{rows.map(row=>{const protectedRow=!!row.manager_id&&row.manager_id!==actorId&&actorRole!=='system_owner'||row.id===actorId||row.system_role==='system_owner'||(actorRole==='system_admin'&&row.system_role==='system_admin');return <tr key={row.id}><td><span className="staffAccountName">{row.staff_profile?.full_name||row.email}</span>{row.staff_profile?.full_name&&<span className="staffAccountEmail" dir="ltr">{row.email}</span>}{row.can_manage_profile&&<button className="adminAction adminActionDetails" type="button" disabled={busy} onClick={()=>setEditor(row)}><KeyRound size={16}/>{uiText("البيانات وكلمة المرور")}</button>}</td><td><span className={'adminRoleChip adminRole-'+row.system_role}>{uiText(labels[row.system_role])||uiText('بلا دور معتمد')}</span></td><td>{protectedRow?uiText('حساب محمي'):<select aria-label={(language==='en'?'New role for ':uiText('الدور الجديد لحساب '))+row.email} value={choices[row.id]||''} disabled={busy} onChange={e=>setChoices(old=>({...old,[row.id]:e.target.value}))}><option value="">{uiText("اختر الدور")}</option>{options.map(role=><option key={role} value={role}>{uiText(labels[role])}</option>)}</select>}</td><td><button className="adminAction adminActionApply" type="button" disabled={busy||protectedRow||!choices[row.id]||choices[row.id]===row.system_role} onClick={()=>save(row)}>{uiText("اعتماد الدور وإلغاء جلساته")}</button></td></tr>})}</tbody></table></div></section>,language);
}
