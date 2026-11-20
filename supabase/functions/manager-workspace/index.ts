import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
const url=Deno.env.get('SUPABASE_URL');
const key=JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')||'{}').default||Deno.env.get('SUPABASE_ANON_KEY');
const secret=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const fresh={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
const issuer='pharmacy_manager_v1',restrictedRole='pharmacy_workspace_only';
const rights={employee:['pos','products','inventory','suppliers','purchases','debtors'],support:['diagnostics']};
const origins=new Set(['https://pharmacy-abdulhadi.vercel.app','https://pharmacy-abdulhadi-naser9.vercel.app']);
const manager=u=>u&&u.role==='authenticated'&&['system_admin','system_owner'].includes(u.app_metadata.system_role??(u.app_metadata.role==='admin'?'system_admin':''));
const mailbox=u=>u?.role===restrictedRole&&u.app_metadata?.workspace_issuer===issuer&&u.app_metadata?.staff_kind==='mailbox';
Deno.serve(async req=>{
 const origin=req.headers.get('origin')||'';
 const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin','Cache-Control':'no-store'};
 const reply=(data,status=200)=>Response.json(data,{status,headers});
 if(url!=='https://eewjjzgwoaxhojnjvzgq.supabase.co'||!origins.has(origin))return new Response(null,{status:403});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({},405);
 try{
 const raw=await req.text();if(raw.length>12000)return reply({},400);
 const b=JSON.parse(raw),auth=createClient(url,key,fresh),service=createClient(url,secret,fresh);
 const token=(req.headers.get('authorization')||'').replace(/^Bearer /i,'');
 const user=token?(await auth.auth.getUser(token)).data.user:null;
 const email=String(b.email||'').trim().toLowerCase();
 const denied=()=>reply({error:'تعذّر التحقق من الطلب.'},403);
 if(b.action==='command'){
  if(user?.role!==restrictedRole||user?.app_metadata?.workspace_issuer!==issuer)return denied();
  const r=await service.rpc('manager_staff_command',{p_actor:user.id,p_request:b.request,p_op:b.op,p_payload:b.payload});
  return r.error?denied():reply({result:r.data});
 }
 if(b.action==='view'){
  if(!user||user.role!==restrictedRole||user.app_metadata.workspace_issuer!==issuer||!Object.hasOwn(rights,user.app_metadata.staff_kind))return denied();
  if(!b.section)return reply({name:user.app_metadata.staff_name,sections:user.app_metadata.sections||[]});
  const r=await service.rpc('manager_staff_view',{p_actor:user.id,p_section:b.section,p_search:String(b.search||'')});
  return r.error?denied():reply({rows:r.data});
 }
 if(b.action==='recover'||b.action==='link'){
  if(b.action==='link'&&!manager(user))return denied();
  if(typeof b.password!=='string'||new TextEncoder().encode(b.password).length>72)return denied();
  if(b.action==='recover'&&b.password.length<12)return denied();
  const verified=b.proof?null:await auth.auth.verifyOtp({email,token:String(b.code),type:'email'});
  const jwt=b.proof||verified?.data.session?.access_token;
  const proof=jwt?(await auth.auth.getUser(jwt)).data.user:null;
  if(!mailbox(proof)||!proof.email_confirmed_at||proof.email!==email)return denied();
  const claims=JSON.parse(atob(jwt.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));
  if(!claims.amr?.some(a=>['otp','magiclink'].includes(a.method)&&a.timestamp*1000>Date.now()-600000))return denied();
  const consume=async()=>{const r=await service.rpc('manager_consume_mail_session',{p_user:proof.id,p_session:claims.session_id});return !r.error&&r.data===true;};
  if(b.action==='link'){
   if(proof.app_metadata.manager_id!==user.id)return denied();
   const check=await createClient(url,key,fresh).auth.signInWithPassword({email:user.email,password:b.password});
   if(check.error||check.data.user?.id!==user.id)return denied();
   if(!await consume())return denied();
   const r=await service.from('manager_recovery_contacts').upsert({manager_id:user.id,mailbox_id:proof.id,email,verified_at:new Date().toISOString()});
   return r.error?denied():reply({ok:true});
  }
  const row=await service.from('manager_recovery_contacts').select('manager_id').eq('mailbox_id',proof.id).eq('email',email).single();
  if(row.error)return denied();
  const target=(await service.auth.admin.getUserById(row.data.manager_id)).data.user;
  if(!manager(target)||target.factors?.some(f=>f.status==='verified')||Date.parse(target.banned_until)>Date.now())return denied();
  if(!await consume())return denied();
  const changed=await service.auth.admin.updateUserById(target.id,{password:b.password});
  return changed.error?denied():reply({ok:true});
 }
 if(!manager(user))return denied();
 if(b.action==='contact'){const r=await service.from('manager_recovery_contacts').select('email').eq('manager_id',user.id).maybeSingle();return r.error?denied():reply({email:r.data?.email||''});}
 if(b.action==='prepareMailbox'){
  if(!email||email===user.email||typeof b.current!=='string')return denied();
  const check=await createClient(url,key,fresh).auth.signInWithPassword({email:user.email,password:b.current});if(check.error||check.data.user?.id!==user.id)return denied();
  const find=await service.rpc('manager_find_mailbox',{p_manager:user.id,p_email:email});
  if(find.error)return denied();
  if(!find.data){const made=await service.auth.admin.createUser({email,role:restrictedRole,email_confirm:true,app_metadata:{workspace_issuer:issuer,manager_id:user.id,staff_kind:'mailbox'}});if(made.error)return denied();}
  return reply({ok:true});
 }
 if(!Object.hasOwn(rights,b.kind)||!Array.isArray(b.sections)||b.sections.some(s=>!Object.hasOwn(rights,b.kind).includes(s)))return denied();
 const sections=[...new Set(b.sections)];
 if(b.action==='save'){
  const target=(await service.auth.admin.getUserById(b.id)).data.user;
  if(!target||target.role!==restrictedRole||target.app_metadata.workspace_issuer!==issuer||target.app_metadata.manager_id!==user.id||target.app_metadata.staff_kind!==b.kind)return denied();
  const r=await service.auth.admin.updateUserById(target.id,{app_metadata:{...target.app_metadata,sections}});return r.error?denied():reply({ok:true});
 }
 if(b.action!=='create'||typeof b.name!=='string'||!b.name.trim()||b.name.length>100||typeof b.password!=='string'||b.password.length<12||new TextEncoder().encode(b.password).length>72)return denied();
 const r=await service.auth.admin.createUser({email,password:b.password,role:restrictedRole,email_confirm:true,app_metadata:{workspace_issuer:issuer,manager_id:user.id,staff_kind:b.kind,staff_name:b.name.trim(),sections}});
 return r.error?reply({error:'تعذّر إنشاء الحساب. تحقق من البريد وكلمة المرور.'},400):reply({ok:true});
 }catch{return reply({error:'تعذّر تنفيذ الطلب.'},400);}
});
