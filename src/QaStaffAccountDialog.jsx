import React,{useEffect,useRef,useState} from 'react';
import {createPortal} from 'react-dom';
import {uiText,getSystemDirection,useSystemLanguage} from './systemLocale.js';
import QaStaffAccountEditor from './QaStaffAccountEditor.jsx';
export default function QaStaffAccountDialog({onClose,...props}){
 useSystemLanguage();const ref=useRef(null),[busy,setBusy]=useState(false);
 useEffect(()=>{const dialog=ref.current,previous=document.activeElement;dialog.showModal();return()=>{dialog.close();if(previous?.isConnected)previous.focus();};},[]);
 return createPortal(<dialog ref={ref} className="staffAccountDialog" aria-label={uiText('تفاصيل حساب الموظف')} dir={getSystemDirection()} onCancel={e=>{e.preventDefault();if(!busy)onClose();}}>
 <header className="staffDialogHeader"><h3>{uiText('تفاصيل حساب الموظف')}</h3><button type="button" disabled={busy} onClick={onClose} aria-label={uiText('إغلاق نافذة الموظف')}>×</button></header>
 <QaStaffAccountEditor {...props} onCancel={onClose} onBusyChange={setBusy}/>
 </dialog>,document.body);
}
