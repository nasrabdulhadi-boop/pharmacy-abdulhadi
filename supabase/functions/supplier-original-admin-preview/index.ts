const PROD_URL = "https://eewjjzgwoaxhojnjvzgq.supabase.co";
const PROD_KEY = "sb_publishable_1lcCtZ-gca7KBW6OKZnvwA_F_3hJr6B";
const EXPECTED_ADMIN = "15cdd7b6-cbfa-4607-9364-2787447f7680";
const QA_URL = Deno.env.get("SUPABASE_URL")!;
const QA_SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BUCKET = "supplier-preview-prescriptions";
function cors(req: Request) {
 const origin=req.headers.get("origin")||"";
 const allowed=/^https:\/\/pharmacy-abdulhadi-[a-z0-9-]+-naser9\.vercel\.app$/.test(origin);
 return {"Content-Type":"application/json","Access-Control-Allow-Origin":allowed?origin:"https://pharmacy-abdulhadi-git-feature-supplier-payment-c-ad26d7-naser9.vercel.app","Access-Control-Allow-Headers":"authorization,apikey,content-type,x-client-info","Access-Control-Allow-Methods":"POST,OPTIONS","Vary":"Origin"};
}
Deno.serve(async (req: Request) => {
 const headers=cors(req);const reply=(status:number,value:unknown)=>new Response(JSON.stringify(value),{status,headers});
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers});
 if(req.method!=="POST")return reply(405,{error:"Method not allowed"});
 const authorization=req.headers.get("Authorization")||"";
 if(!/^Bearer [A-Za-z0-9._-]+$/.test(authorization)||authorization.length>10000)return reply(401,{error:"Sign in with the original administrator account"});
 try{
  // The production project is used for identity verification only. No production data RPC or mutation.
  const identity=await fetch(PROD_URL+"/auth/v1/user",{method:"GET",headers:{apikey:PROD_KEY,Authorization:authorization},signal:AbortSignal.timeout(12000)});
  if(!identity.ok)return reply(401,{error:"Original administrator session is invalid or expired"});
  const user=await identity.json();
  if(user.id!==EXPECTED_ADMIN||user.app_metadata?.role!=="admin")return reply(403,{error:"Original administrator account required"});
  const raw=await req.text();if(raw.length>15000000)return reply(413,{error:"Request too large"});
  let body;try{body=JSON.parse(raw)}catch{return reply(400,{error:"Invalid JSON"})}
  if(body.kind==="identity")return reply(200,{data:{id:user.id,email:user.email,role:"admin"},error:null});
  if(body.kind==="storage"){
   if(!["upload","remove","sign"].includes(body.action))return reply(400,{error:"Invalid file action"});
   const paths=body.action==="remove"?body.paths:[body.path];
   if(!Array.isArray(paths)||paths.length<1||paths.length>10||paths.some((p:unknown)=>typeof p!=="string"||!/^admin\/[A-Za-z0-9._-]+$/.test(p)))return reply(400,{error:"Invalid preview file path"});
   let path="/storage/v1/object/"+BUCKET+"/"+paths[0],opts:RequestInit;
   if(body.action==="upload"){
    if(!["image/jpeg","image/png","image/webp","application/pdf"].includes(body.mime)||typeof body.base64!=="string"||body.base64.length>14000000)return reply(400,{error:"Invalid file"});
    const binary=atob(body.base64);if(binary.length>10*1024*1024)return reply(413,{error:"File too large"});
    opts={method:"POST",headers:{Authorization:"Bearer "+QA_SERVICE,apikey:QA_SERVICE,"Content-Type":body.mime},body:Uint8Array.from(binary,c=>c.charCodeAt(0))};
   }else{
    if(body.action==="remove"){path="/storage/v1/object/"+BUCKET;opts={method:"DELETE",body:JSON.stringify({prefixes:paths})};}
    else {path="/storage/v1/object/sign/"+BUCKET+"/"+paths[0];opts={method:"POST",body:JSON.stringify({expiresIn:300})};}
    opts.headers={Authorization:"Bearer "+QA_SERVICE,apikey:QA_SERVICE,"Content-Type":"application/json"};
   }
   const response=await fetch(QA_URL+path,opts);const result=await response.json();
   if(!response.ok)return reply(400,{data:null,error:{message:result.message||"Preview file operation failed"}});
   return reply(200,{data:body.action==="sign"?{signedUrl:QA_URL+"/storage/v1"+result.signedURL}:{path:paths[0]},error:null});
  }
  if(!["rpc","table"].includes(body.kind)||typeof body.name!=="string")return reply(400,{error:"Invalid preview operation"});
  const response=await fetch(QA_URL+"/rest/v1/rpc/supplier_preview_original_admin_bridge",{method:"POST",headers:{Authorization:"Bearer "+QA_SERVICE,apikey:QA_SERVICE,"Content-Type":"application/json"},body:JSON.stringify({p_actor:user.id,p_kind:body.kind,p_name:body.name,p_payload:body.payload||{}}),signal:AbortSignal.timeout(25000)});
  const data=await response.json();
  if(!response.ok)return reply(response.status,{data:null,error:{message:data.message||"Preview operation failed",code:data.code}});
  return reply(200,{data,error:null});
 }catch{return reply(500,{data:null,error:{message:"Preview operation failed; no production data was changed"}})}
});

