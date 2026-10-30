import {ISOLATED_QA_PROJECT_URL} from './stagingAuthGuard.js';
export async function updateOwnQaPassword({client,previewEnabled,projectUrl,password,confirmation}){
 if(previewEnabled!==true||projectUrl!==ISOLATED_QA_PROJECT_URL)throw new Error('qa_auth_disabled');
 if(typeof password!=='string'||password.length<12||password.length>128||password!==confirmation)throw new Error('invalid_password');
 const {data,error}=await client.auth.getUser();
 if(error||!data?.user?.id)throw new Error('not_authorized');
 const result=await client.auth.updateUser({password});
 if(result.error)throw new Error('password_update_failed');
 return true;
}
