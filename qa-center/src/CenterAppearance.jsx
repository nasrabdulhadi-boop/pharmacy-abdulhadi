import React,{useState} from 'react';
const defaults={font:'plex',shape:'rounded',order:[]};
export function useCenterAppearance(actor){
 const key='qa-center-display:'+actor;
 const [value,setValue]=useState(()=>{try{return {...defaults,...JSON.parse(localStorage.getItem(key))};}catch{return defaults;}});
 const save=next=>{setValue(next);try{localStorage.setItem(key,JSON.stringify(next));}catch{}};
 return [value,save];
}
export function CenterAppearance({value,save,sections}){
 function move(index,step){const order=sections.map(([id])=>id);[order[index],order[index+step]]=[order[index+step],order[index]];save({...value,order});}
 return <section className="adminSettingsCard"><h4>تنسيق مركز الإدارة على هذا الجهاز</h4>
 <div className="permissionGrid"><label>الخط<select value={value.font} onChange={e=>save({...value,font:e.target.value})}><option value="plex">IBM Plex عربي</option><option value="alexandria">الإسكندرية</option></select></label>
 <label>شكل الأزرار<select value={value.shape} onChange={e=>save({...value,shape:e.target.value})}><option value="rounded">زوايا ناعمة</option><option value="square">زوايا خفيفة</option><option value="pill">دائري</option></select></label></div>
 <h4>ترتيب التبويبات</h4>{sections.map(([id,label],i)=><div className="tabOrderRow" key={id}><span>{label}</span><button type="button" aria-label={'تقديم '+label} disabled={!i} onClick={()=>move(i,-1)}>تقديم</button><button type="button" aria-label={'تأخير '+label} disabled={i===sections.length-1} onClick={()=>move(i,1)}>تأخير</button></div>)}
 <button type="button" onClick={()=>save(defaults)}>استعادة التنسيق الأساسي</button></section>;
}
