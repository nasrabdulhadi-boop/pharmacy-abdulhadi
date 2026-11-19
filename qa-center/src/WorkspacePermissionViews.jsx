import {uiText,uiTemplate,uiSourceTexts} from './systemLocale.js';
import React,{useEffect,useRef} from 'react';
import {LockKeyhole} from 'lucide-react';
export function WorkspaceSectionFrame({locked,title,children}){
 return <><div hidden={!locked} className="workspaceRoleBadge"><LockKeyhole size={17}/><strong>{uiText(title)}{uiText(" — مقفل حسب الصلاحيات")}</strong><span className="workspaceMaskedValue" aria-label={uiText("أرقام محجوبة")}>••••</span><span>{uiText("الأرقام محجوبة والبيانات غير محمّلة لهذا الحساب")}</span></div><div inert={locked?true:undefined} className={locked?'workspaceRedacted':''} aria-label={locked?uiText(title)+uiText(' — معاينة محجوبة'):uiText(undefined)}>{children}</div></>;
}
const deniedLabels={pharmacyProducts:/تعديل|حذف|إخفاء|إظهار|استعادة/,inventory:/إضافة دفعة|تعديل|حذف|إتلاف|تسوية|تعديل رصيد/,suppliers:/إضافة|تعديل|حذف|سجل المشتريات/,purchases:/إضافة مورد|مورد جديد|تعديل أسعار|ديون الموردين|حذف|تسجيل دفعة/,returns:/مرتجع.*مورد|إلى المورد/,pos:/سعر الصرف/};
// This controls presentation only. QA RPC/RLS independently enforces every read and write.
export function WorkspaceOperationSurface({section,restricted,children}){
 const ref=useRef(null);
 useEffect(()=>{
  if(!restricted||!ref.current)return;
  const mask=()=>{for(const button of ref.current.querySelectorAll('button')){
   const label=[button.textContent,button.title,button.getAttribute('aria-label')].flatMap(uiSourceTexts).join(' ');
   const destructive=section!=='pos'&&(button.classList.contains('danger')||!!button.querySelector('.lucide-trash-2'));
   const draftLineRemoval=section==='purchases'&&uiSourceTexts(button.title).includes('حذف الصنف');
   if(!draftLineRemoval&&(destructive||deniedLabels[section]?.test(label)||(section==='suppliers'&&button.classList.contains('linkButton')))){if(!button.disabled)button.disabled=true;button.dataset.workspaceDenied='true';button.title=uiText('غير مسموح لصلاحيات هذا الحساب');button.setAttribute('aria-label',uiText('إجراء مقفل حسب الصلاحيات'))}
  }};
  mask();const observer=new MutationObserver(mask);observer.observe(ref.current,{childList:true,subtree:true,attributes:true,attributeFilter:['disabled']});return()=>observer.disconnect();
 },[section,restricted]);
 const guard=e=>{if(restricted&&e.target.closest?.('[data-workspace-denied]')){e.preventDefault();e.stopPropagation()}};
 return <section ref={ref} onClickCapture={guard} className="workspaceOriginalSection">{children}</section>;
}
