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
function localizedValue(value){
 if(typeof value!=='string'||!value.trim())return value;
 const leading=value.match(/^\s*/)?.[0]||'',trailing=value.match(/\s*$/)?.[0]||'';
 const core=value.slice(leading.length,value.length-trailing.length);
 if(!core)return value;
 if(language==='ar')return leading+sourceInterfaceText(core)+trailing;
 return leading+translateInterfaceText(core,language)+trailing;
}
function localizeTextNode(textNode){\n if(!textNode||textNode.nodeType!==3)return;\n const parent=textNode.parentElement;if(!parent||parent.closest('script,style,textarea,input,select,[contenteditable=\"true\"],[data-no-translate]'))return;\n const before=textNode.nodeValue,after=localizedValue(before);if(after!==before)textNode.nodeValue=after;\n}\nfunction localizeNode(node){
 if(!node||node.nodeType!==1)return;
 const tag=node.tagName?.toLowerCase();
 if(['script','style','textarea','input','select','option'].includes(tag)||node.isContentEditable)return;
 if(node.hasAttribute('data-no-translate'))return;
 const walker=document.createTreeWalker(node,NodeFilter.SHOW_TEXT);
 const texts=[];while(walker.nextNode())texts.push(walker.currentNode);
 for(const textNode of texts){
  const parent=textNode.parentElement;if(!parent||parent.closest('script,style,textarea,input,select,[contenteditable="true"],[data-no-translate]'))continue;
  const before=textNode.nodeValue,after=localizedValue(before);if(after!==before)textNode.nodeValue=after;
 }
 for(const attr of localizationAttributes){
  if(node.hasAttribute(attr)){const before=node.getAttribute(attr),after=localizedValue(before);if(after!==before)node.setAttribute(attr,after);}
 }
 if(node.hasAttribute('dir')&&node.tagName.toLowerCase()!=='bdi'&&!node.closest('bdi,[data-preserve-direction]')){
  const current=node.getAttribute('dir');if(current==='rtl'||current==='ltr')node.setAttribute('dir',getSystemDirection());
 }
 if(node.style?.direction==='rtl'||node.style?.direction==='ltr')node.style.direction=getSystemDirection();
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
   if(record.type==='characterData'){const before=record.target.nodeValue,after=localizedValue(before);if(after!==before)record.target.nodeValue=after;}
   else if(record.type==='attributes')localizeNode(record.target);
   else for(const node of record.addedNodes){if(node.nodeType===1)localizeNode(node);else if(node.nodeType===3)localizeTextNode(node);}
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
