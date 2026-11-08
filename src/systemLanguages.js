export const SYSTEM_LANGUAGES=Object.freeze([
 {code:'ar',name:'العربية',locale:'ar-SY-u-nu-latn'},
 {code:'en',name:'English',locale:'en-US'},
 {code:'ru',name:'Русский',locale:'ru-RU-u-nu-latn'},
 {code:'tr',name:'Türkçe',locale:'tr-TR-u-nu-latn'},
 {code:'ro',name:'Română',locale:'ro-RO-u-nu-latn'},
 {code:'fr',name:'Français',locale:'fr-FR-u-nu-latn'},
 {code:'de',name:'Deutsch',locale:'de-DE-u-nu-latn'}
]);
export const normalizeSystemLanguage=value=>SYSTEM_LANGUAGES.some(x=>x.code===value)?value:'ar';
export const systemDateLocale=language=>SYSTEM_LANGUAGES.find(x=>x.code===language)?.locale||SYSTEM_LANGUAGES[0].locale;
