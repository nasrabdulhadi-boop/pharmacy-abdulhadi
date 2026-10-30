// Production is an identity provider only. All data calls go to the fixed QA gateway.
export const PREVIEW_AUTH_URL='https://eewjjzgwoaxhojnjvzgq.supabase.co';
export const PREVIEW_DATA_URL='https://vpjxdsprfcpqclnhbeoh.supabase.co';
export const PREVIEW_GATEWAY=PREVIEW_DATA_URL+'/functions/v1/supplier-original-admin-preview';
export function createSupplierFullPreviewClient(authClient,qaKey,fetcher=fetch){
 const send=async body=>{
  const {data,error}=await authClient.auth.getSession();
  if(error||!data?.session?.access_token)return {data:null,error:{message:'سجّل الدخول بحساب المدير الأصلي'}};
  try{const response=await fetcher(PREVIEW_GATEWAY,{method:'POST',headers:{'Content-Type':'application/json',apikey:qaKey,Authorization:'Bearer '+data.session.access_token},body:JSON.stringify(body)});
   const value=await response.json();
   if(!response.ok)return {data:null,error:{message:value.error?.message||value.error||'تعذر الوصول إلى النسخة التجريبية'}};
   return value;
  }catch{return {data:null,error:{message:'تعذر الاتصال بالنسخة التجريبية؛ أعد المحاولة'}}}
 };
 const builder=(kind,name,args)=>{
  const payload=kind==='rpc'?{args:args||{}}:{action:'select',filters:[],orders:[]};
  let singular=null,promise=null;
  const run=()=>promise||=(async()=>{
   const r=await send({kind,name,payload});if(r.error)return r;
   let data=r.data;
   if(kind==='rpc'&&Array.isArray(data)&&payload.offset!==undefined)data=data.slice(payload.offset,payload.offset+payload.limit);
   if(singular){if(!Array.isArray(data))return r;if(data.length>1||(!data.length&&singular==='single'))return {data:null,error:{message:'عدد نتائج السجل غير متوقع'}};data=data[0]??null;}
   return {...r,data};
  })();
  const q={then:(resolve,reject)=>run().then(resolve,reject),catch:reject=>run().catch(reject),
   select:(columns='*')=>{payload.columns=columns;return q},
   insert:data=>{payload.action='insert';payload.data=data;return q},
   update:data=>{payload.action='update';payload.data=data;return q},
   upsert:data=>{payload.action='upsert';payload.data=data;return q},
   delete:()=>{payload.action='delete';return q},
   order:(column,options={})=>{payload.orders??=[];payload.orders.push({column,ascending:options.ascending!==false});return q},
   limit:n=>{payload.limit=n;return q},range:(from,to)=>{payload.offset=from;payload.limit=to-from+1;return q},
   single:()=>{singular='single';return q},maybeSingle:()=>{singular='maybeSingle';return q}};
  for(const op of ['eq','neq','gt','gte','lt','lte','in','is'])q[op]=(column,value)=>{payload.filters.push({column,op,value});return q};
  return q;
 };
 return {auth:authClient.auth,rpc:(name,args)=>builder('rpc',name,args),from:name=>builder('table',name),
  verifyOriginalAdmin:()=>send({kind:'identity'}),
  storage:{from:bucket=>({
   upload:async(path,file,options={})=>{
    if(bucket!=='prescriptions')return {data:null,error:{message:'مخزن تجريبي غير مدعوم'}};
    if(file.size>10*1024*1024)return {data:null,error:{message:'الحد الأقصى 10 MB'}};
    const bytes=new Uint8Array(await file.arrayBuffer());let binary='';for(let i=0;i<bytes.length;i+=8192)binary+=String.fromCharCode(...bytes.subarray(i,i+8192));
    return send({kind:'storage',action:'upload',path,mime:options.contentType||file.type,base64:btoa(binary)});
   },remove:paths=>send({kind:'storage',action:'remove',paths}),
   createSignedUrl:path=>send({kind:'storage',action:'sign',path})
  })}
 };
}
