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
 if(language!==next){language=next;notify();}applyDocument();scheduleLocalization();};
 if(next==='ar'||next==='en'){apply();return Promise.resolve();}return loadInterfaceLanguage(next).then(apply);
}
if(typeof window!=='undefined'){
 const initial=language;loadInterfaceLanguage(initial).then(()=>{if(language===initial){notify();applyDocument();scheduleLocalization();}}).catch(()=>{if(language===initial&&request===0){language='ar';notify();applyDocument();scheduleLocalization();}});
 window.addEventListener('storage',event=>{if(event.key===ADMIN_PREF_KEY)setSystemLanguage(readAdminPreferences(window.localStorage).language).catch(()=>{});});
}

const localizationAttributes=['placeholder','title','aria-label','alt'];
const originalTextValues=new WeakMap(),originalAttributeValues=new WeakMap();
function localizedValue(value){
 if(typeof value!=='string'||!value.trim())return value;
 const leading=value.match(/^\\s*/)?.[0]||'',trailing=value.match(/\\s*$/)?.[0]||'';
 const core=value.slice(leading.length,value.length-trailing.length);
 if(!core)return value;
 if(language==='ar')return leading+sourceInterfaceText(core)+trailing;
 return leading+translateInterfaceText(core,language)+trailing;
}
function shouldSkipTranslation(element){
 return !element||element.closest('script,style,textarea,input,[contenteditable="true"],[data-no-translate]');
}
function localizeTextNode(textNode){
 if(!textNode||textNode.nodeType!==3)return;
 const parent=textNode.parentElement;if(shouldSkipTranslation(parent))return;
 const before=textNode.nodeValue;let record=originalTextValues.get(textNode);if(!record||record.last!==before){record={source:language==='ar'?before:sourceInterfaceText(before),last:before};originalTextValues.set(textNode,record);}
 const after=language==='ar'?record.source:translateInterfaceText(record.source,language);if(after!==before){textNode.nodeValue=after;record.last=after;}
}
function localizeElement(element){
 if(!element||element.nodeType!==1||shouldSkipTranslation(element))return;
 for(const attr of localizationAttributes){
  if(element.hasAttribute(attr)){const before=element.getAttribute(attr);let records=originalAttributeValues.get(element);if(!records){records=new Map();originalAttributeValues.set(element,records);}let record=records.get(attr);if(!record||record.last!==before){record={source:language==='ar'?before:sourceInterfaceText(before),last:before};records.set(attr,record);}const after=language==='ar'?record.source:translateInterfaceText(record.source,language);if(after!==before){element.setAttribute(attr,after);record.last=after;}}
 }
 if(element.hasAttribute('dir')&&element.tagName.toLowerCase()!=='bdi'&&!element.closest('bdi,[data-preserve-direction]')){
  const current=element.getAttribute('dir');if(current==='rtl'||current==='ltr')element.setAttribute('dir',getSystemDirection());
 }
 if(element.style?.direction==='rtl'||element.style?.direction==='ltr')element.style.direction=getSystemDirection();
 for(const child of element.childNodes){
  if(child.nodeType===3)localizeTextNode(child);
  else if(child.nodeType===1)localizeElement(child);
 }
}
function localizeNode(node){
 if(!node)return;
 if(node.nodeType===3){localizeTextNode(node);return;}
 if(node.nodeType===1)localizeElement(node);
}
let localizationObserver=null,localizationQueued=false;
function localizeDocument(){
 if(typeof document==='undefined'||!document.body)return;
 localizeNode(document.body);
}
function scheduleLocalization(){
 if(localizationQueued)return;localizationQueued=true;
 queueMicrotask(()=>{localizationQueued=false;localizeDocument();});
}
function installGlobalLocalization(){
 if(typeof document==='undefined'||!document.body||localizationObserver)return;
 localizationObserver=new MutationObserver(records=>{
  for(const record of records){
   if(record.type==='characterData')localizeTextNode(record.target);
   else if(record.type==='attributes')localizeElement(record.target);
   else for(const node of record.addedNodes)localizeNode(node);
  }
 });
 localizationObserver.observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:[...localizationAttributes,'dir','style']});
 localizeDocument();
}
if(typeof document!=='undefined'){
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',installGlobalLocalization,{once:true});
 else installGlobalLocalization();
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
