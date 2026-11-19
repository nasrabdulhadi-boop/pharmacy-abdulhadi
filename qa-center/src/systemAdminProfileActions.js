import {ISOLATED_QA_PROJECT_URL} from './stagingAuthGuard.js';
import {normalizeRecoveryEmail,isValidRecoveryEmail,isAllowedRecoveryRedirect} from './systemAdminAccountRecovery.js';

async function ownUser({client,projectUrl,previewEnabled,expectedUserId}){
 if(projectUrl!==ISOLATED_QA_PROJECT_URL||previewEnabled!==true)throw new Error('qa_auth_disabled');
 if(!expectedUserId)throw new Error('not_authorized');
 const {data,error}=await client.auth.getUser();
 if(error||data?.user?.id!==expectedUserId)throw new Error('not_authorized');
 return data.user;
}
export async function saveOwnQaProfile(options){
 const name=typeof options.name==='string'?options.name.trim():'';
 if(!name||name.length>100||/[\u0000-\u001f\u007f]/.test(name))throw new Error('invalid_name');
 await ownUser(options);
 const {data,error}=await options.client.auth.updateUser({data:{full_name:name}});
 if(error||data?.user?.id!==options.expectedUserId)throw new Error('profile_update_failed');
 return {name};
}
export async function requestOwnQaEmailChange(options){
 const email=normalizeRecoveryEmail(options.email);
 if(!isValidRecoveryEmail(email))throw new Error('invalid_email');
 if(!isAllowedRecoveryRedirect(options.redirectTo,options.origin))throw new Error('invalid_redirect');
 const user=await ownUser(options);
 if(normalizeRecoveryEmail(user.email)===email)throw new Error('unchanged_email');
 const {data,error}=await options.client.auth.updateUser({email},{emailRedirectTo:options.redirectTo});
 if(error)throw new Error(error.status===429?'rate_limited':'email_request_failed');
 if(data?.user?.id!==options.expectedUserId)throw new Error('not_authorized');
 // An accepted request is not evidence that a mailbox received a confirmation.
 return {requested:true,confirmed:false};
}
export async function signOutOtherQaSessions(options){
 await ownUser(options);
 const {error}=await options.client.auth.signOut({scope:'others'});
 if(error)throw new Error('session_revoke_failed');
 return {othersSignedOut:true};
}
