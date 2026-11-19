import {ISOLATED_QA_PROJECT_URL} from './stagingAuthGuard.js';
import {cleanStaffCommand,cleanStaffProfile} from '../supabase/functions/qa-admin-staff-account/validation.js';
export {staffFields,validStaffPassword} from '../supabase/functions/qa-admin-staff-account/validation.js';
export async function manageQaStaffAccount({client,projectUrl,actorId,actorRole,command}){
 if(projectUrl!==ISOLATED_QA_PROJECT_URL||!actorId||!['system_owner','system_admin'].includes(actorRole))throw Error('not_authorized');
 const clean=cleanStaffCommand(command),identity=await client.auth.getUser();if(identity.error||identity.data?.user?.id!==actorId)throw Error('not_authorized');
 const {data,error}=await client.functions.invoke('qa-admin-staff-account',{body:clean});
 if(error){let reason;try{reason=(await error.context.clone().json()).error;}catch{}throw Error(reason||'account_operation_unconfirmed');}
 if(data?.completed!==true||data.action!==clean.action||!data.user_id||data.email_sent!==false)throw Error('account_operation_unconfirmed');return data;
}
export async function saveQaStaffProfile({client,projectUrl,targetId,profile}){
 if(projectUrl!==ISOLATED_QA_PROJECT_URL)throw Error('not_authorized');
 const {data,error}=await client.rpc('qa_admin_save_staff_profile',{p_target:targetId,p_profile:cleanStaffProfile(profile)});if(error||data!==true)throw Error('profile_save_failed');
}
