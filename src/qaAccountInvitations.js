import {ISOLATED_QA_PROJECT_URL} from './stagingAuthGuard.js';
import {normalizeRecoveryEmail,isValidRecoveryEmail} from './systemAdminAccountRecovery.js';
export async function prepareQaInvitation({client,projectUrl,actorId,actorRole,email,role,origin,requestId}){
 if(projectUrl!==ISOLATED_QA_PROJECT_URL||!actorId||!['system_owner','system_admin'].includes(actorRole))throw Error('not_authorized');
 const normalized=normalizeRecoveryEmail(email);
 if(!isValidRecoveryEmail(normalized))throw Error('invalid_email');
 if(!['employee','technical_support','system_admin'].includes(role)||(role==='system_admin'&&actorRole!=='system_owner'))throw Error('not_authorized');
 if(!/^https:\/\/pharmacy-abdulhadi-[a-z0-9-]+-naser9\.vercel\.app$/.test(origin||''))throw Error('invalid_redirect');
 if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(requestId||''))throw Error('invalid_request');
 const user=await client.auth.getUser();if(user.error||user.data?.user?.id!==actorId)throw Error('not_authorized');
 const redirect=origin+'/#admin';
 const {data,error}=await client.functions.invoke('qa-admin-account-invite',{body:{request_id:requestId,email:normalized,role,redirect_to:redirect}});
 if(error){const status=error.context?.status;throw Error(status===409?'invitation_conflict':status===429?'rate_limited':'invitation_unavailable');}
 let link;try{link=new URL(data?.action_link);}catch{throw Error('invitation_unavailable');}
 if(data?.prepared!==true||data.email_sent!==false||data.role!==role||!data.user_id||link.origin!==origin||link.pathname!=='/'||link.search||new URLSearchParams(link.hash.slice(1)).get('type')!=='invite'||!/^[a-f0-9]{56,128}$/.test(new URLSearchParams(link.hash.slice(1)).get('token_hash')||''))throw Error('invitation_unavailable');
 return {link:link.href,userId:data.user_id,email:normalized,role,emailSent:false};
}

export async function consumeQaInvitation({auth,projectUrl,enabled,hash,clearFragment}){
 if(projectUrl!==ISOLATED_QA_PROJECT_URL||enabled!==true)return {handled:false};
 const params=new URLSearchParams((hash||'').replace(/^#/,''));
 if(params.get('type')!=='invite'||!params.has('token_hash'))return {handled:false};
 const token=params.get('token_hash');clearFragment();
 if(!/^[a-f0-9]{56,128}$/.test(token||''))return {handled:true,session:null};
 try{const {data,error}=await auth.verifyOtp({type:'invite',token_hash:token});return {handled:true,session:!error?data?.session||null:null};}
 catch{return {handled:true,session:null};}
}

export function invitationRequestId(random=globalThis.crypto){
 if(typeof random?.randomUUID==='function')return random.randomUUID();
 const bytes=random.getRandomValues(new Uint8Array(16));bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
 const hex=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');return [hex.slice(0,8),hex.slice(8,12),hex.slice(12,16),hex.slice(16,20),hex.slice(20)].join('-');
}
