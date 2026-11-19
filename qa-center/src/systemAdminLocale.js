import React from 'react';

// Scoped to the administration center. Values entered by the user are never translated.
import {ADMIN_EN,CAPABILITY_LABELS} from './systemAdminEnglish.js';
import {translateInterfaceText} from './systemLanguageCatalogs.js';
export {ADMIN_EN};

export function adminText(value,language='ar'){return translateInterfaceText(value,language);}


export function adminCapabilityLabel(capability,language='ar'){
 const pair=CAPABILITY_LABELS[capability];if(!pair)return capability;return language==='en'?pair[1]:translateInterfaceText(pair[0],language);
}
export function localizeAdminTree(node,language='ar'){
 if(typeof node==='string')return adminText(node,language);
 if(Array.isArray(node))return React.Children.map(node,child=>localizeAdminTree(child,language));
 if(!React.isValidElement(node))return node;
 if(node.props['data-no-translate'])return node;
 // Custom components own their translations and receive the selected language.
 if(typeof node.type!=='string'&&node.type!==React.Fragment)return React.cloneElement(node,{language});
 const props={};
 for(const key of ['title','aria-label','placeholder'])if(typeof node.props[key]==='string')props[key]=adminText(node.props[key],language);
 return React.cloneElement(node,props,localizeAdminTree(node.props.children,language));
}

export function adminManifestError(error,language='ar'){return adminText(String(error).startsWith('Unverified section:')?'قسم مطلوب في وصف النسخة غير متحقق.':'وصف النسخة غير صالح.',language);}
