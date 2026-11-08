import {useSyncExternalStore} from 'react';
import {ADMIN_PREF_KEY,readAdminPreferences,writeAdminPreferences} from './systemAdminPreferences.js';
import {ADMIN_EN} from './systemAdminLocale.js';
import {SYSTEM_EN} from './systemTranslations.js';
let language=readAdminPreferences(typeof window==='undefined'?null:window.localStorage).language;
const listeners=new Set();
export const getSystemLanguage=()=>language;
export const getSystemDirection=()=>language==='en'?'ltr':'rtl';
const subscribe=fn=>{listeners.add(fn);return()=>listeners.delete(fn);};
export const useSystemLanguage=()=>useSyncExternalStore(subscribe,getSystemLanguage,getSystemLanguage);
export function setSystemLanguage(value){
 const next=value==='en'?'en':'ar';
 if(typeof window!=='undefined'){const preferences=readAdminPreferences(window.localStorage);writeAdminPreferences(window.localStorage,{...preferences,language:next});}
 if(language!==next){language=next;for(const fn of listeners)fn();}
 if(typeof document!=='undefined'){document.documentElement.lang=next;document.documentElement.dir=getSystemDirection();}
}
if(typeof window!=='undefined')window.addEventListener('storage',event=>{if(event.key===ADMIN_PREF_KEY){const next=readAdminPreferences(window.localStorage).language;if(next!==language){language=next;for(const fn of listeners)fn();}}});
export function uiText(value){
 if(language!=='en'||typeof value!=='string')return value;
 if(/^[+-]?[\d,.\s]+\s+ل\.س$/.test(value))return value.replace(/ل\.س$/, 'SYP');
 const key=value.trim(),translated=SYSTEM_EN[key]??ADMIN_EN[key];
 return typeof translated==='string'?value.replace(key,translated):value;
}
export function uiTemplate(parts,values){
 const key=parts.map((part,i)=>part+(i<values.length?'{'+i+'}':'')).join('');
 const translated=language==='en'?(SYSTEM_EN[key.trim()]??ADMIN_EN[key.trim()]):null;
 return typeof translated==='string'?key.replace(key.trim(),translated).replace(/\{(\d+)\}/g,(_,i)=>String(values[Number(i)])):parts.map((part,i)=>part+(i<values.length?String(values[i]):'')).join('');
}

const sourceCopy=new Map();
for(const [source,translated] of Object.entries({...ADMIN_EN,...SYSTEM_EN}))if(!sourceCopy.has(translated))sourceCopy.set(translated,source);
export function uiSourceText(value){const text=typeof value==='string'?value.trim():'';return sourceCopy.get(text)||text;}
export function uiHtmlTemplate(parts,values){
 if(language!=='en')return parts.map((part,i)=>part+(i<values.length?String(values[i]):'')).join('');
 const translate=part=>part.replace(/(>)([^<>]*)(?=<|$)/g,(_,open,text)=>open+uiText(text)).replace(/^([^<>]*)(?=<)/,text=>uiText(text)).replace(/dir=(["'])rtl\1/g,'dir="ltr"').replace(/direction:\s*rtl/g,'direction:ltr');
 return parts.map((part,i)=>translate(part)+(i<values.length?String(values[i]):'')).join('');
}
