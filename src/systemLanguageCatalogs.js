import {ADMIN_EN,CAPABILITY_LABELS} from './systemAdminEnglish.js';
import {SYSTEM_EN} from './systemTranslations.js';
export const ENGLISH_INTERFACE=Object.freeze({...ADMIN_EN,...SYSTEM_EN,...Object.fromEntries(Object.values(CAPABILITY_LABELS))});
const dictionaries={en:ENGLISH_INTERFACE},pending={};
const loaders={ru:()=>import('./locales/ru.js'),tr:()=>import('./locales/tr.js'),ro:()=>import('./locales/ro.js'),fr:()=>import('./locales/fr.js'),de:()=>import('./locales/de.js')};
const sourceByEnglish=new Map();for(const [source,value]of Object.entries(ENGLISH_INTERFACE))if(!sourceByEnglish.has(value))sourceByEnglish.set(value,source);
const reverse=new Map();
const addReverse=(value,source)=>{if(!reverse.has(value))reverse.set(value,new Set());reverse.get(value).add(source);};
for(const [source,value]of Object.entries(ENGLISH_INTERFACE))addReverse(value,source);
export async function loadInterfaceLanguage(code){
 if(code==='ar'||dictionaries[code])return;
 if(!loaders[code])throw Error('unsupported_language');
 if(!pending[code])pending[code]=loaders[code]().then(module=>{dictionaries[code]=module.default;for(const [source,value]of Object.entries(module.default))addReverse(value,source);}).catch(error=>{delete pending[code];throw error;});
 await pending[code];
}
export function sourceInterfaceTexts(value){const text=typeof value==='string'?value.trim():'';return reverse.has(text)?[...reverse.get(text)]:[text];}
export const sourceInterfaceText=value=>sourceInterfaceTexts(value)[0];
export function translateInterfaceText(value,code='ar'){
 if(code==='ar'||typeof value!=='string')return value;
 if(/^[+-]?[\d,.\s]+\s+ل\.س$/.test(value))return value.replace(/ل\.س$/,'SYP');
 const key=value.trim(),source=sourceByEnglish.get(key)||key;
 const counted=key.match(/^([\d,.]+)(\s+)(صنف يحتاج مراجعة|صنف يحتاج مراجعة التوريد|دفعة أو صنف حسب مؤشر النظام)$/);
 if(counted){const suffix=translateInterfaceText(counted[3],code);if(suffix!==counted[3])return value.replace(key,counted[1]+counted[2]+suffix);}
 const translated=dictionaries[code]?.[source]??ENGLISH_INTERFACE[source];
 return typeof translated==='string'?value.replace(key,translated):value;
}
