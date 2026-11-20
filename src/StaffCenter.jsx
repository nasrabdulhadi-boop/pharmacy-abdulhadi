import StaffActivity from './StaffActivity.jsx';
import React,{useEffect,useState} from 'react';
export const allSections={dashboard:'لوحة التحكم',pos:'نقطة البيع',products:'منتجات الصيدلية',siteProducts:'منتجات الموقع',smart:'المخزون الذكي',inventory:'المخزون',purchases:'سجل المشتريات',suppliers:'الموردون',debtors:'المتدينون والدفعات',supplierDebts:'ديون الموردين',prescriptions:'الوصفات',requests:'طلبات الأدوية',offers:'العروض',orders:'الطلبات',returns:'المرتجعات',customers:'العملاء',cashbox:'الصندوق',financial:'مركز الأرباح',reports:'التقارير',daily:'مركز الحركة اليومي',branches:'دليل الفروع',admin:'إعدادات حساب العمل',operations:'تنفيذ العمليات لحساب الدعم الفني',security:'الأمان والتدقيق',corrections:'السماح بالتصحيحات والحذف في الأقسام المحددة',diagnostics:'التشخيص التقني'};

export async function call(client,body){
 const {data,error}=await client.functions.invoke('manager-workspace',{body});
 if(error){let reason;try{reason=(await error.context?.json())?.error;}catch{}throw Error(reason||'تعذّر الاتصال بمركز الإدارة. افتح رابط النظام الأساسي وحدّث الصفحة.');}
 if(data?.error)throw Error(data.error);return data;
}
function Editor({client,row,kind,done}){
 const [sections,setSections]=useState(row?.sections||[]),[busy,setBusy]=useState(false),[error,setError]=useState('');
 async function submit(e){e.preventDefault();if(busy)return;const f=new FormData(e.currentTarget);setBusy(true);setError('');
 try{await call(client,{action:row?'save':'create',id:row?.id,kind,sections,name:f.get('name'),email:f.get('email'),password:f.get('password')});done(true);}
 catch(err){setError(err.message);}finally{setBusy(false);}}
 return <form className="adminSettingsCard" onSubmit={submit}><h4>{row?row.name:kind==='employee'?'إنشاء حساب موظف':'إنشاء حساب دعم فني'}</h4>
 {!row&&<><label>الاسم<input name="name" required maxLength={100}/></label><label>بريد الدخول<input name="email" type="email" required/></label><label>كلمة المرور (12 محرفاً على الأقل)<input name="password" type="password" autoComplete="new-password" required minLength={12}/></label></>}
 <fieldset><legend>الأقسام المسموحة</legend><div className="permissionGrid">{Object.entries(allSections).filter(([id])=>id!=='operations'||kind==='support').map(([id,name])=><label key={id}><input type="checkbox" disabled={busy} checked={sections.includes(id)} onChange={e=>setSections(e.target.checked?[...sections,id]:sections.filter(x=>x!==id))}/>{name}</label>)}</div></fieldset>
 <button className="primary" disabled={busy}>حفظ</button><button type="button" disabled={busy} onClick={()=>done(false)}>إلغاء</button><p role="status">{error}</p></form>;
}
export default function StaffCenter({client}){
 const [rows,setRows]=useState([]),[editor,setEditor]=useState(null),[revision,refresh]=useState(0),[message,setMessage]=useState('');
 useEffect(()=>{let active=true;client.rpc('manager_staff_directory').then(({data,error})=>{if(active){if(error)setMessage('تعذر تحميل الحسابات');else setRows(data||[]);}});return()=>{active=false;};},[revision,client]);
 return <section><div className="qaBranchControls"><button className="primary" onClick={()=>setEditor({kind:'employee'})}>إنشاء حساب موظف</button><button onClick={()=>setEditor({kind:'support'})}>إنشاء حساب دعم فني</button><a href="/?workspace=staff">دخول الموظفين والدعم</a></div>
 {editor&&<Editor key={editor.row?.id||editor.kind} client={client} {...editor} done={saved=>{setEditor(null);if(saved){refresh(v=>v+1);setMessage('تم حفظ الحساب والصلاحيات.');}}}/>}
 {rows.map(r=><div className="tabOrderRow" key={r.id}><span>{r.name} · <bdi>{r.email}</bdi></span><button onClick={()=>setEditor({row:r,kind:r.kind})}>تعديل الصلاحيات</button></div>)}<p role="status">{message}</p><StaffActivity client={client} revision={revision}/></section>;
}
