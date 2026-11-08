import {cleanStaffCommand} from './validation.js';
const QA='https://vpjxdsprfcpqclnhbeoh.supabase.co';
const allowedOrigin=v=>/^https:\/\/pharmacy-abdulhadi-[a-z0-9-]+-naser9\.vercel\.app$/.test(v||'');
export async function handleStaffAccount(req,config){
 const origin=req.headers.get('origin'),headers={'Content-Type':'application/json','Cache-Control':'no-store',Vary:'Origin'};
 if(origin&&allowedOrigin(origin))Object.assign(headers,{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'});
 const response=(value,status=200)=>new Response(JSON.stringify(value),{status,headers});
 if(config.projectUrl!==QA||origin&&!allowedOrigin(origin))return response({error:'qa_only'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return response({error:'method_not_allowed'},405);
 const token=req.headers.get('authorization')||'';if(!token.startsWith('Bearer '))return response({error:'not_authorized'},401);
 let admin,command,reserved=false;
 try{
  const scoped=config.createClient(QA,config.publishable,{global:{headers:{Authorization:token}},auth:{persistSession:false,autoRefreshToken:false}});
  const identity=await scoped.auth.getUser(token.slice(7)),role=await scoped.rpc('qa_my_role');
  if(identity.error||!identity.data?.user||role.error||!['system_owner','system_admin'].includes(role.data))return response({error:'not_authorized'},403);
  const raw=await req.text();if(raw.length>8192)return response({error:'invalid_request'},400);
  try{command=cleanStaffCommand(JSON.parse(raw));}catch(e){return response({error:['invalid_request','invalid_email','invalid_profile','invalid_password','not_authorized','manager_confirmation_required'].includes(e.message)?e.message:'invalid_request'},400);}
  if(command.action==='password'){
   const attempt=await scoped.rpc('qa_admin_begin_staff_password_check',{p_id:command.request_id,p_target:command.target_id});
   if(attempt.error||attempt.data!==true)return response({error:attempt.error?.code==='54000'?'confirmation_rate_limited':'not_authorized'},attempt.error?.code==='54000'?429:403);
   // Separate non-persistent client: never replace or globally sign out the manager's session.
   const proof=config.createClient(QA,config.publishable,{auth:{persistSession:false,autoRefreshToken:false}});
   let verified=false;
   try{const signed=await proof.auth.signInWithPassword({email:identity.data.user.email,password:command.manager_password});verified=!signed.error&&signed.data?.user?.id===identity.data.user.id&&!!signed.data?.session;}
   finally{await proof.auth.signOut({scope:'local'}).catch(()=>{});command.manager_password='';}
   if(!verified)return response({error:'manager_confirmation_failed'},403);
   admin=config.createClient(QA,config.secret,{auth:{persistSession:false,autoRefreshToken:false}});
   const approved=await admin.rpc('qa_service_verify_staff_password_check',{p_id:command.request_id});if(approved.error||approved.data!==true)return response({error:'manager_confirmation_failed'},403);
  }
  const reservation=await scoped.rpc('qa_admin_reserve_staff',{p_id:command.request_id,p_action:command.action,p_email:command.email||null,p_role:command.role||null,p_target:command.target_id||null,p_profile:command.profile||null});
  if(reservation.error||reservation.data!==true)return response({error:reservation.error?.code==='23505'?'account_conflict':reservation.error?.code==='54000'?'rate_limited':'not_authorized'},reservation.error?.code==='23505'?409:reservation.error?.code==='54000'?429:403);
  reserved=true;admin=config.createClient(QA,config.secret,{auth:{persistSession:false,autoRefreshToken:false}});
  let target=command.target_id;
  if(command.action==='create'){
   // Manager-provisioned local credential; no verification/recovery email is sent.
   // Stay banned and without an active role until the DB links and authorizes it.
   const created=await admin.auth.admin.createUser({email:command.email,password:command.password,email_confirm:true,ban_duration:'876000h',app_metadata:{system_role:'disabled',qa_staff_request:command.request_id,qa_staff_manager:identity.data.user.id},user_metadata:{full_name:command.profile.full_name}});
   if(created.error||!created.data?.user?.id)throw Error('auth_failed');target=created.data.user.id;
  }else{
   // DB reservation already removed sessions and disabled the target. Failure stays closed.
   const updated=await admin.auth.admin.updateUserById(target,{password:command.password});if(updated.error||updated.data?.user?.id!==target)throw Error('auth_failed');
  }
  const completed=await admin.rpc('qa_service_complete_staff',{p_id:command.request_id,p_target:target});if(completed.error||completed.data!==true)throw Error('completion_failed');
  return response({completed:true,user_id:target,action:command.action,email_sent:false});
 }catch{
  if(reserved&&admin&&command)try{await admin.rpc('qa_service_fail_staff',{p_id:command.request_id});}catch{}
  return response({error:'account_operation_unconfirmed',access_may_be_disabled:reserved},503);
 }
}
