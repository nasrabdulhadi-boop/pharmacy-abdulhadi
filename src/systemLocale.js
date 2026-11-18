import {useSyncExternalStore} from 'react';
import {ADMIN_PREF_KEY,readAdminPreferences,writeAdminPreferences} from './systemAdminPreferences.js';
import {loadInterfaceLanguage,translateInterfaceText,sourceInterfaceText,sourceInterfaceTexts} from './systemLanguageCatalogs.js';
import {normalizeSystemLanguage,systemDateLocale} from './systemLanguages.js';
let language=readAdminPreferences(typeof window==='undefined'?null:window.localStorage).language;
export const getSystemLanguage=()=>language;
export const getSystemDirection=()=>language==='ar'?'rtl':'ltr';
const listeners=new Set();let revision=0,request=0;
const notify=()=>{revision++;for(const fn of listeners)fn();};
export const getSystemDateLocale=()=>systemDateLocale(language);
const subscribe=fn=>{listeners.add(fn);return()=>listeners.delete(fn);};
const snapshot=()=>language+':'+revision;
export const useSystemLanguage=()=>{useSyncExternalStore(subscribe,snapshot,snapshot);return language;};
const applyDocument=()=>{if(typeof document!=='undefined'){document.documentElement.lang=language;document.documentElement.dir=getSystemDirection();document.title=uiText('صيدلية عبدالهادي')+' | '+uiText('نظام إدارة الصيدلية');}};
export function setSystemLanguage(value){
 const next=normalizeSystemLanguage(value),version=++request;const apply=()=>{if(version!==request)return;
 if(typeof window!=='undefined'){const preferences=readAdminPreferences(window.localStorage);writeAdminPreferences(window.localStorage,{...preferences,language:next});}
 if(language!==next){language=next;notify();}applyDocument();};
 if(next==='ar'||next==='en'){apply();return Promise.resolve();}return loadInterfaceLanguage(next).then(apply);
}
if(typeof window!=='undefined'){
 const initial=language;loadInterfaceLanguage(initial).then(()=>{if(language===initial){notify();applyDocument();}}).catch(()=>{if(language===initial&&request===0){language='ar';notify();applyDocument();}});
 window.addEventListener('storage',event=>{if(event.key===ADMIN_PREF_KEY)setSystemLanguage(readAdminPreferences(window.localStorage).language).catch(()=>{});});
}
export const uiText=value=>translateInterfaceText(value,language);
export function uiTemplate(parts,values){
 const key=parts.map((part,i)=>part+(i<values.length?'{'+i+'}':'')).join('');
 const translated=language==='ar'?null:uiText(key.trim());
 return typeof translated==='string'?key.replace(key.trim(),translated).replace(/\{(\d+)\}/g,(_,i)=>String(values[Number(i)])):parts.map((part,i)=>part+(i<values.length?String(values[i]):'')).join('');
}

export const uiSourceText=sourceInterfaceText;
export const uiSourceTexts=sourceInterfaceTexts;
export function uiHtmlTemplate(parts,values){
 if(language==='ar')return parts.map((part,i)=>part+(i<values.length?String(values[i]):'')).join('');
 const translate=part=>part.replace(/(>)([^<>]*)(?=<|$)/g,(_,open,text)=>open+uiText(text)).replace(/^([^<>]*)(?=<)/,text=>uiText(text)).replace(/dir=(["'])rtl\1/g,'dir="ltr"').replace(/direction:\s*rtl/g,'direction:ltr');
 return parts.map((part,i)=>translate(part)+(i<values.length?String(values[i]):'')).join('');
}
