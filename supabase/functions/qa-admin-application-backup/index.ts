import {createClient} from "npm:@supabase/supabase-js@2.118.0";
const QA_URL="https://vpjxdsprfcpqclnhbeoh.supabase.co";
const allowedOrigin=(origin:string)=>origin==="http://terminal.local:4173"||/^https:\/\/pharmacy-abdulhadi-[a-z0-9-]+-naser9\.vercel\.app$/.test(origin);
const hex=(bytes:ArrayBuffer)=>Array.from(new Uint8Array(bytes),b=>b.toString(16).padStart(2,"0")).join("");
const base64=(bytes:Uint8Array)=>{let result="";for(const byte of bytes)result+=String.fromCharCode(byte);return btoa(result);};
Deno.serve(async req=>{
 const origin=req.headers.get("origin");
 const headers:Record<string,string>={"Content-Type":"application/json","Cache-Control":"no-store","Vary":"Origin"};
 if(origin&&allowedOrigin(origin)){headers["Access-Control-Allow-Origin"]=origin;headers["Access-Control-Allow-Headers"]="authorization, apikey, content-type, x-client-info";headers["Access-Control-Allow-Methods"]="POST, OPTIONS";}
 const response=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 if(origin&&!allowedOrigin(origin))return response({error:"origin_denied"},403);
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers});
 if(req.method!=="POST")return response({error:"method_not_allowed"},405);
 if(Deno.env.get("SUPABASE_URL")!==QA_URL)return response({error:"qa_only"},403);
 const authorization=req.headers.get("authorization")||"";
 if(!authorization.startsWith("Bearer "))return response({error:"not_authorized"},401);
 const publishable=JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")||"{}").default||Deno.env.get("SUPABASE_ANON_KEY");
 const scoped=createClient(QA_URL,publishable!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
 try{
  const identity=await scoped.auth.getUser(authorization.slice(7));
  if(identity.error||!identity.data.user)return response({error:"not_authorized"},401);
  // The database independently checks current owner role, current session, expiry and bans.
  const role=await scoped.rpc("qa_my_role");
  if(role.error||!["system_owner","system_admin"].includes(role.data))return response({error:"not_authorized"},403);
  const body=await req.json().catch(()=>({}));
  const probeMode=body.mode==="synthetic_probe";
  if(probeMode&&!/^[a-f0-9-]{36}$/.test(body.probe_id||""))return response({error:"invalid_probe"},400);
  const snapshot=probeMode?await scoped.rpc("qa_admin_backup_probe_snapshot",{p_probe_id:body.probe_id}):await scoped.rpc("qa_admin_backup_snapshot");
  if(snapshot.error)return response({error:"not_authorized"},403);
  const data=snapshot.data;
  if(data?.project_ref!=="vpjxdsprfcpqclnhbeoh"||!Array.isArray(data.storage_inventory))return response({error:"snapshot_unavailable"},503);
  if(data.storage_inventory.length>30)return response({error:"qa_storage_limit"},413);
  const secret=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}").default||Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const admin=createClient(QA_URL,secret!,{auth:{persistSession:false,autoRefreshToken:false}});
  const files=[];let total=0;
  for(const object of data.storage_inventory){
   if(object.bucket_id!=="supplier-preview-prescriptions"||typeof object.name!=="string")return response({error:"invalid_storage_scope"},500);
   const downloaded=await admin.storage.from(object.bucket_id).download(object.name);
   if(downloaded.error||!downloaded.data)return response({error:"storage_backup_incomplete"},503);
   const bytes=new Uint8Array(await downloaded.data.arrayBuffer());total+=bytes.length;
   if(bytes.length>5*1024*1024||total>5*1024*1024)return response({error:"qa_storage_limit"},413);
   files.push({bucket_id:object.bucket_id,name:object.name,size:bytes.length,sha256:hex(await crypto.subtle.digest("SHA-256",bytes)),bytes_base64:base64(bytes)});
  }
  // Refuse a partial archive if objects were replaced or removed while downloading.
  const recheck=probeMode?await scoped.rpc("qa_admin_backup_probe_snapshot",{p_probe_id:body.probe_id}):await scoped.rpc("qa_admin_backup_snapshot");
  if(recheck.error||JSON.stringify(recheck.data?.storage_inventory)!==JSON.stringify(data.storage_inventory))return response({error:"storage_changed_retry"},409);
  const payload={...data,storage_files:files};
  const digest=hex(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(JSON.stringify(payload))));
  const audit=await admin.rpc("qa_record_completed_backup_export",{p_actor:identity.data.user.id,p_sha256:digest,p_tables:data.tables.length,p_files:files.length});
  if(audit.error||!audit.data)return response({error:"export_audit_failed"},503);
  return response({...payload,export_audit_id:audit.data,export_complete:true});
 }catch{return response({error:"backup_unavailable"},503);}
});
