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
const TEXT_ATTRIBUTES=['aria-label','aria-description','title','placeholder','alt'];
const SKIP_TRANSLATION_TAGS=new Set(['SCRIPT','STYLE','NOSCRIPT','TEXTAREA','CODE','PRE']);
let domObserver=null;
function translateDomText(raw){
 if(typeof raw!=='string'||!raw.trim())return raw;
 return translateInterfaceText(raw,language);
}
function localizeElement(element){
 if(!element||element.nodeType!==1)return;
 if(SKIP_TRANSLATION_TAGS.has(element.tagName)||element.isContentEditable)return;
 for(const attr of TEXT_ATTRIBUTES){
  const value=element.getAttribute(attr);
  if(value){const translated=translateDomText(value);if(translated!==value)element.setAttribute(attr,translated);}
 }
 const currentDirection=element.getAttribute('dir');
 if(currentDirection==='rtl'){
  if(!element.dataset.systemLocaleOriginalDir)element.dataset.systemLocaleOriginalDir='rtl';
  if(getSystemDirection()==='ltr')element.setAttribute('dir','ltr');
 }else if(element.dataset.systemLocaleOriginalDir==='rtl'&&getSystemDirection()==='rtl'){
  element.setAttribute('dir','rtl');
 }
 if(element.style?.direction==='rtl'){
  if(!element.dataset.systemLocaleOriginalInlineDirection)element.dataset.systemLocaleOriginalInlineDirection='rtl';
  if(getSystemDirection()==='ltr')element.style.direction='ltr';
 }else if(element.dataset.systemLocaleOriginalInlineDirection==='rtl'&&getSystemDirection()==='rtl'){
  element.style.direction='rtl';
 }
}
function localizeSubtree(root){
 if(!root||typeof document==='undefined')return;
 const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
 let node;while((node=walker.nextNode())){
  const parent=node.parentElement;
  if(!parent||SKIP_TRANSLATION_TAGS.has(parent.tagName)||parent.isContentEditable)continue;
  const translated=translateDomText(node.nodeValue);
  if(translated!==node.nodeValue)node.nodeValue=translated;
 }
 if(root.nodeType===1)localizeElement(root);
 root.querySelectorAll?.('*').forEach(localizeElement);
}
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
const TEXT_ATTRIBUTES=['aria-label','aria-description','title','placeholder','alt'];
const SKIP_TRANSLATION_TAGS=new Set(['SCRIPT','STYLE','NOSCRIPT','TEXTAREA','CODE','PRE']);
let domObserver=null;
function translateDomText(raw){
 if(typeof raw!=='string'||!raw.trim())return raw;
 return translateInterfaceText(raw,language);
}
function localizeElement(element){
 if(!element||element.nodeType!==1)return;
 if(SKIP_TRANSLATION_TAGS.has(element.tagName)||element.isContentEditable)return;
 for(const attr of TEXT_ATTRIBUTES){
  const value=element.getAttribute(attr);
  if(value){const translated=translateDomText(value);if(translated!==value)element.setAttribute(attr,translated);}
 }
 const currentDirection=element.getAttribute('dir');
 if(currentDirection==='rtl'){
  if(!element.dataset.systemLocaleOriginalDir)element.dataset.systemLocaleOriginalDir='rtl';
  if(getSystemDirection()==='ltr')element.setAttribute('dir','ltr');
 }else if(element.dataset.systemLocaleOriginalDir==='rtl'&&getSystemDirection()==='rtl'){
  element.setAttribute('dir','rtl');
 }
 if(element.style?.direction==='rtl'){
  if(!element.dataset.systemLocaleOriginalInlineDirection)element.dataset.systemLocaleOriginalInlineDirection='rtl';
  if(getSystemDirection()==='ltr')element.style.direction='ltr';
 }else if(element.dataset.systemLocaleOriginalInlineDirection==='rtl'&&getSystemDirection()==='rtl'){
  element.style.direction='rtl';
 }
}
function localizeSubtree(root){
 if(!root||typeof document==='undefined')return;
 const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
 let node;while((node=walker.nextNode())){
  const parent=node.parentElement;
  if(!parent||SKIP_TRANSLATION_TAGS.has(parent.tagName)||parent.isContentEditable)continue;
  const translated=translateDomText(node.nodeValue);
  if(translated!==node.nodeValue)node.nodeValue=translated;
 }
 if(root.nodeType===1)localizeElement(root);
 root.querySelectorAll?.('*').forEach(localizeElement);
}
function queueDomLocalization(){
 if(domQueued||typeof document==='undefined')return;domQueued=true;
 queueMicrotask(()=>{domQueued=false;localizeSubtree(document.body);});
}
function installDomLocalization(){
 if(typeof document==='undefined'||!document.body||domObserver)return;
 localizeSubtree(document.body);
 domObserver=new MutationObserver(records=>{
  for(const record of records){
   if(record.type==='characterData'){
    const node=record.target,parent=node.parentElement;
    if(parent&&!SKIP_TRANSLATION_TAGS.has(parent.tagName)&&!parent.isContentEditable){const translated=translateDomText(node.nodeValue);if(translated!==node.nodeValue)node.nodeValue=translated;}
   }else if(record.type==='attributes')localizeElement(record.target);
   else for(const added of record.addedNodes){if(added.nodeType===3){const parent=added.parentElement;if(parent&&!SKIP_TRANSLATION_TAGS.has(parent.tagName)){const translated=translateDomText(added.nodeValue);if(translated!==added.nodeValue)added.nodeValue=translated;}}else if(added.nodeType===1)localizeSubtree(added);}
  }
 });
 domObserver.observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:[...TEXT_ATTRIBUTES,'dir','style']});
}
const applyDocument=()=>{if(typeof document!=='undefined'){document.documentElement.lang=language;document.documentElement.dir=getSystemDirection();document.title=uiText('صيدلية عبدالهادي')+' | '+uiText('نظام إدارة الصيدلية');localizeSubtree(document.body);installDomLocalization();}};
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
