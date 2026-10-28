export const ADMIN_PREF_KEY='pharmacy_admin_center_preferences_v1';
export const DEFAULT_ADMIN_PREF=Object.freeze({language:'ar',density:'comfortable'});
export function normalizeAdminPreferences(value){
 return {language:value?.language==='en'?'en':'ar',density:value?.density==='compact'?'compact':'comfortable'};
}
export function readAdminPreferences(storage){
 try{return normalizeAdminPreferences(JSON.parse(storage?.getItem(ADMIN_PREF_KEY)||'null'));}
 catch{return {...DEFAULT_ADMIN_PREF};}
}
export function writeAdminPreferences(storage,value){
 const clean=normalizeAdminPreferences(value);
 try{storage?.setItem(ADMIN_PREF_KEY,JSON.stringify(clean));return true;}
 catch{return false;}
}
