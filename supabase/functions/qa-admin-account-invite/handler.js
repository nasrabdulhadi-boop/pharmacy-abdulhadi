const QA='https://vpjxdsprfcpqclnhbeoh.supabase.co';
const allowedOrigin=value=>/^https:\/\/pharmacy-abdulhadi-[a-z0-9-]+-naser9\.vercel\.app$/.test(value||'');
const validRedirect=(value,origin)=>{try{const u=new URL(value);return allowedOrigin(u.origin)&&(!origin||u.origin===origin)&&u.pathname==='/'&&u.hash==='#admin'&&!u.search&&!u.username&&!u.password;}catch{return false;}};
export async function handleInvite(req,config){
 const origin=req.headers.get('origin'),headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin'};
 if(origin&&allowedOrigin(origin)){headers['Access-Control-Allow-Origin']=origin;headers['Access-Control-Allow-Headers']='authorization, apikey, content-type, x-client-info';headers['Access-Control-Allow-Methods']='POST, OPTIONS';}
 const response=(value,status=200)=>new Response(JSON.stringify(value),{status,headers});
 if(config.projectUrl!==QA)return response({error:'qa_only'},403);
 if(origin&&!allowedOrigin(origin))return response({error:'origin_denied'},403);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return response({error:'method_not_allowed'},405);
 const auth=req.headers.get('authorization')||'';if(!auth.startsWith('Bearer '))return response({error:'not_authorized'},401);
 const scoped=config.createClient(QA,config.publishable,{global:{headers:{Authorization:auth}},auth:{persistSession:false,autoRefreshToken:false}});
 let admin=null,reserved=false,created=null,finalized=false,requestId=null,email=null;
 const fail=async()=>{
  if(!admin||!reserved||finalized)return;
  if(created){
   const current=await admin.auth.admin.getUserById(created);
   const u=current.data?.user;
   // Never delete an existing/confirmed/privileged account on a partial failure.
   if(u&&u.email?.toLowerCase()===email&&u.user_metadata?.qa_invitation_id===requestId&&!u.email_confirmed_at&&!u.app_metadata?.system_role&&!u.app_metadata?.role)await admin.auth.admin.deleteUser(created);
  }
  await admin.rpc('qa_service_fail_invitation',{p_id:requestId});
 };
 try{
  const identity=await scoped.auth.getUser(auth.slice(7));
  if(identity.error||!identity.data?.user)return response({error:'not_authorized'},401);
  const role=await scoped.rpc('qa_my_role');
  if(role.error||!['system_owner','system_admin'].includes(role.data))return response({error:'not_authorized'},403);
  if(Number(req.headers.get('content-length'))>4096)return response({error:'invalid_request'},400);
  const raw=await req.text();if(raw.length>4096)return response({error:'invalid_request'},400);
  let body;try{body=JSON.parse(raw);}catch{return response({error:'invalid_request'},400);}
  if(!body||typeof body!=='object'||Array.isArray(body))return response({error:'invalid_request'},400);
  requestId=body.request_id;email=typeof body.email==='string'?body.email.trim().toLowerCase():'';
  if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(requestId||'')||email.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||!validRedirect(body.redirect_to,origin))return response({error:'invalid_request'},400);
  if(!['system_admin','employee','technical_support'].includes(body.role)||(body.role==='system_admin'&&role.data!=='system_owner'))return response({error:'not_authorized'},403);
  const reservation=await scoped.rpc('qa_admin_reserve_invitation',{p_id:requestId,p_email:email,p_role:body.role});
  if(reservation.error)return response({error:reservation.error.code==='23505'?'invitation_conflict':reservation.error.code==='54000'?'rate_limited':'not_authorized'},reservation.error.code==='23505'?409:reservation.error.code==='54000'?429:403);
  if(reservation.data!==true)return response({error:'invitation_unavailable'},503);
  reserved=true;admin=config.createClient(QA,config.secret,{auth:{persistSession:false,autoRefreshToken:false}});
  // generateLink creates a link but sends no email. No password or OTP is returned.
  const generated=await admin.auth.admin.generateLink({type:'invite',email,options:{redirectTo:body.redirect_to,data:{qa_invitation_id:requestId}}});
  const user=generated.data?.user;if(!generated.error&&user?.id)created=user.id;
  if(generated.error||!created)throw Error('invite_failed');
  const hash=generated.data?.properties?.hashed_token;
  if(typeof hash!=='string'||!/^[a-f0-9]{56,128}$/.test(hash))throw Error('unsafe_link');
  // Explicit first-party verification avoids dependence on obsolete Auth redirect settings.
  // The hash is a one-time credential and is never logged or stored in the database.
  const callback=new URL(body.redirect_to);callback.hash=new URLSearchParams({type:'invite',token_hash:hash}).toString();
  const link=callback.href;
  const completed=await admin.rpc('qa_service_finalize_invitation',{p_id:requestId,p_target:created});
  if(completed.error||completed.data!==true)throw Error('finalize_failed');
  finalized=true;
  return response({prepared:true,email_sent:false,user_id:created,role:body.role,action_link:link});
 }catch(error){const reason=['invite_failed','unsafe_link','finalize_failed'].includes(error?.message)?error.message:'invitation_failed';try{await fail();}catch{}return response({error:'invitation_unavailable',reason},503);}
}
