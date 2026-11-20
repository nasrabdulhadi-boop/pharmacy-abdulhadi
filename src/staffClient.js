import {createClient} from '@supabase/supabase-js';
import {call} from './StaffCenter.jsx';
const raw=new URLSearchParams(location.search).get('workspace')==='staff'?createClient(import.meta.env.VITE_SUPABASE_URL,import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,{auth:{storageKey:'pharmacy-staff-session',detectSessionInUrl:false}}):null;
async function request(body){
 try{return {data:(await call(raw,body)).result,error:null};}
 catch(error){return {data:null,error};}
}
function from(table){
 const steps=[];
 const builder={then(resolve,reject){return request({action:'table',table,steps}).then(resolve,reject);}};
 for(const method of ['select','insert','update','upsert','delete','eq','in','or','gte','lt','order','limit','range','single','maybeSingle']){
  builder[method]=(...args)=>{steps.push([method,...args]);return builder;};
 }
 return builder;
}
export const staffClient={auth:raw?.auth,functions:raw?.functions,storage:{from:()=>({
 createSignedUrl:path=>request({action:'file',op:'read',path}),
 async upload(path,file,options){const r=await request({action:'file',op:'upload',path});return r.error?r:raw.storage.from('prescriptions').uploadToSignedUrl(path,r.data.token,file,options);}
})},from,rpc:(fn,args={})=>request({action:'rpc',fn,args})};
