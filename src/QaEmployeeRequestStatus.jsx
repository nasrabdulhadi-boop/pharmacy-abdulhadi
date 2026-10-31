import React,{useEffect,useRef,useState} from 'react';
import {employeeRequestRows} from './qaEmployeeRequests.js';
export default function QaEmployeeRequestStatus({client}){
 const [open,setOpen]=useState(false),[rows,setRows]=useState([]),[loading,setLoading]=useState(false),[error,setError]=useState(false);
 const generation=useRef(0);
 useEffect(()=>()=>{generation.current++},[]);
 const load=async()=>{
  const version=++generation.current;setLoading(true);setError(false);
  try{const result=await client.rpc('qa_sandbox_requests');if(result.error)throw result.error;if(version===generation.current)setRows(employeeRequestRows(result.data));}
  catch{if(version===generation.current){setRows([]);setError(true)}}finally{if(version===generation.current)setLoading(false)}
 };
 const toggle=()=>{setOpen(!open);if(!open)load();else generation.current++};
 return <section className="workspaceEmployeeRequests card" aria-label="متابعة طلباتي">
  <button type="button" aria-expanded={open} aria-controls="qa-own-request-list" onClick={toggle}>متابعة طلباتي — قرارات المدير</button>
  {open&&<div id="qa-own-request-list"><p>آخر 20 طلباً من طلباتك. الطلب المعلّق لا يغيّر المخزون أو الحسابات قبل موافقة المدير.</p><button type="button" onClick={load} disabled={loading}>تحديث حالة طلباتي</button>
   {loading?<p role="status">جارٍ تحديث الطلبات…</p>:error?<p role="alert">تعذر تحميل حالة الطلبات. أعد التحديث.</p>:rows.length?<ul>{rows.map(r=><li key={r.id}><strong>{r.operation}</strong><span className={'requestStatus requestStatus-'+r.status}>{r.statusLabel}</span><small>رقم الطلب: {r.id.slice(0,8)}{r.createdAt?' • '+new Date(r.createdAt).toLocaleString('ar-SY'):''}</small></li>)}</ul>:<p>لا توجد طلبات لعرضها.</p>}
  </div>}
 </section>;
}
