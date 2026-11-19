import {uiText,uiTemplate} from './systemLocale.js';
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
  <div><h4>{uiText("حالة الأمان")}</h4></div>
  <strong>{!status?uiText('فحص الصلاحيات غير متاح حالياً.'):status.unprotected||status.anonymous?uiText('الفحص يحتاج متابعة'):uiText('قيود QA مطبقة')}</strong>
  {status&&(status.unprotected>0||status.anonymous>0)&&<p>{uiText("جداول غير محمية: ")}<b>{status.unprotected}</b>{uiText(" · وصول زائر لبيانات حساسة: ")}<b>{status.anonymous}</b></p>}
 </article>,language);
}
