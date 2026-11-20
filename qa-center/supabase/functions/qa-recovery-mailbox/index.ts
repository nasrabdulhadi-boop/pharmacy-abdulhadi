import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
const url=Deno.env.get('SUPABASE_URL');
const key=JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')||'{}').default||Deno.env.get('SUPABASE_ANON_KEY');
const secret=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const opts={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
const isManager=u=>u&&['system_admin','system_owner'].includes(u.app_metadata?.system_role??(u.app_metadata?.role==='admin'?'system_admin':''));
Deno.serve(async req=>{
 const origin=req.headers.get('origin')||'';
 const headers={'Access-Control-Allow-Origin':origin,'Vary':'Origin','Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Allow-Headers':'authorization,apikey,x-client-info,content-type','Cache-Control':'no-store'};
 const respond=(ok,status)=>Response.json({ok},{status,headers});
 if(url!=='https://vpjxdsprfcpqclnhbeoh.supabase.co'||!/^https:\/\/pharmacy-abdulhadi-[a-z0-9-]+-naser9\.vercel\.app$/.test(origin))return new Response(null,{status:403});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return respond(false,405);
 try{
 const {action,email,code,password}=await req.json();
 if(!['link','reset'].includes(action)||typeof email!=='string'||email.length>254||!/^\d{6,10}$/.test(code)||typeof password!=='string'||new TextEncoder().encode(password).length>72)return respond(false,400);
 const admin=createClient(url,secret,opts), auth=createClient(url,key,opts);
 let manager;
 if(action==='link'){
   const {data,error}=await auth.auth.getUser((req.headers.get('authorization')??'').replace(/^Bearer /i,''));
   manager=data.user;
   if(error||!isManager(manager)||manager.email?.toLowerCase()===email.trim().toLowerCase())return respond(false,403);
   const pass=await createClient(url,key,opts).auth.signInWithPassword({email:manager.email,password});
   if(pass.error||pass.data.user?.id!==manager.id)return respond(false,403);
 }else if(password.length<12)return respond(false,400);
 const proof=await auth.auth.verifyOtp({type:'email',email:email.trim(),token:code});
 const mailbox=proof.data.user;
 if(proof.error||!mailbox?.email_confirmed_at||mailbox.email?.toLowerCase()!==email.trim().toLowerCase())return respond(false,403);
 if(action==='link'){
   const {error}=await admin.from('qa_verified_recovery_mailboxes').upsert({manager_id:manager.id,mailbox_id:mailbox.id,email:mailbox.email,verified_at:new Date().toISOString()},{onConflict:'manager_id'});
   return respond(!error,error?400:200);
 }
 const {data,error}=await admin.from('qa_verified_recovery_mailboxes').select('manager_id').eq('mailbox_id',mailbox.id).eq('email',mailbox.email).maybeSingle();
 if(error||!data)return respond(false,403);
 const target=await admin.auth.admin.getUserById(data.manager_id);
 if(target.error||!isManager(target.data.user)||target.data.user.factors?.some(f=>f.status==='verified')||Date.parse(target.data.user.banned_until??'')>Date.now())return respond(false,403);
 const saved=await admin.auth.admin.updateUserById(data.manager_id,{password});
 return respond(!saved.error,saved.error?400:200);
 }catch{return respond(false,400);}
});
