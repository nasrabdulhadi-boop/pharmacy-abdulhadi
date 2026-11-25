import React,{useRef,useState} from 'react';
import {ArrowDown,ArrowUp,ArrowLeftRight,ListOrdered} from 'lucide-react';
import {uiText} from './systemLocale.js';
const defaults={font:'plex',shape:'rounded',order:[]};
export function useCenterAppearance(actor){
 const key='qa-center-display:'+actor;
 const [value,setValue]=useState(()=>{try{return {...defaults,...JSON.parse(localStorage.getItem(key))};}catch{return defaults;}});
 const save=next=>{setValue(next);try{localStorage.setItem(key,JSON.stringify(next));}catch{}};
 return [value,save];
}
export function CenterAppearance({value,save,sections,children}){
 const [ordering,setOrdering]=useState(false);
 const openButton=useRef(null),backButton=useRef(null);
 function changePage(open){
  setOrdering(open);
  requestAnimationFrame(()=> (open?backButton:openButton).current?.focus());
 }
 function move(index,step){
  const order=sections.map(([id])=>id);
  [order[index],order[index+step]]=[order[index+step],order[index]];
  save({...value,order});
 }
 if(ordering)return <section className="appearancePage">
  <header className="appearanceHeading"><h4><ListOrdered size={20}/> {uiText('ترتيب التبويبات')}</h4><button ref={backButton} onClick={()=>changePage(false)}>{uiText('العودة إلى المظهر')}</button></header>
  <ol className="appearanceOrder">{sections.map(([id,label],i)=><li key={id}><span>{uiText(label)}</span>
   <button aria-label={uiText('تقديم')+' '+uiText(label)} disabled={!i} onClick={()=>move(i,-1)}><ArrowUp size={18}/></button>
   <button aria-label={uiText('تأخير')+' '+uiText(label)} disabled={i===sections.length-1} onClick={()=>move(i,1)}><ArrowDown size={18}/></button></li>)}</ol>
 </section>;
 return <div className="appearancePage">
  {children}
  <div className="appearanceFields"><label>{uiText('خط مركز الإدارة')}<select value={value.font} onChange={e=>save({...value,font:e.target.value})}>
   <option value="plex">IBM Plex عربي</option><option value="alexandria">الإسكندرية</option><option value="kufi">نوتو كوفي</option><option value="naskh">نوتو نسخ</option><option value="sans">نوتو سانس عربي</option></select></label>
  <label>{uiText('شكل الأزرار')}<select value={value.shape} onChange={e=>save({...value,shape:e.target.value})}><option value="rounded">{uiText('زوايا ناعمة')}</option><option value="square">{uiText('زوايا خفيفة')}</option><option value="pill">{uiText('دائري')}</option></select></label></div>
  <button ref={openButton} className="appearanceOrderLink" onClick={()=>changePage(true)}><ListOrdered size={22}/><strong>{uiText('ترتيب التبويبات')}</strong><ArrowLeftRight size={17}/></button>
  <button className="appearanceReset" onClick={()=>save(defaults)}>{uiText('استعادة التنسيق الأساسي')}</button>
 </div>;
}
