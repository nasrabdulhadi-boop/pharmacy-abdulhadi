import React,{useEffect,useState} from 'react';
import {ISOLATED_QA_PROJECT_URL} from './stagingAuthGuard.js';
import {localizeAdminTree} from './systemAdminLocale.js';
export default function QaAdminSecurityStatus({client,projectUrl,language='ar'}){
 const [status,setStatus]=useState(null);
 useEffect(()=>{let active=true;setStatus(null);
  if(projectUrl!==ISOLATED_QA_PROJECT_URL)return;
  client.rpc('qa_admin_center_status').then(({data,error})=>{
   if(active&&!error&&data?.schema_version===1&&Number.isInteger(data.unprotected_public_tables)&&Number.isInteger(data.anonymous_sensitive_tables))setStatus({unprotected:data.unprotected_public_tables,anonymous:data.anonymous_sensitive_tables});
  }).catch(()=>{});
  return()=>{active=false};
 },[client,projectUrl]);
 return localizeAdminTree(<article className="systemAdminSecurityAudit" role="status">
  <div><h4>مراجعة الخادم الحالية</h4><p>قراءة مؤشرات الأمان من الخادم، دون بيانات حسابات أو فواتير.</p></div>
  <strong>{!status?'فحص الصلاحيات غير متاح حالياً.':status.unprotected||status.anonymous?'الفحص يحتاج متابعة':'قيود QA مطبقة'}</strong>
  {status&&<><p>منح الزائر على الجداول الحساسة: <b>{status.anonymous}</b></p><p>قيود الوصول المباشر مطبقة؛ اختبارات الجلسات الفعلية مستقلة.</p></>}
 </article>,language);
}
