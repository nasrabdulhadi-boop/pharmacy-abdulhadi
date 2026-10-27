import {inspectFestSource} from '../src/festSourceStatus.js';
// This best-effort process cache limits repeated downloads; it is never an authorization cache.
let recent=null,pending=null;
export default async function handler(req,res){
 res.setHeader('Cache-Control','no-store');
 if(req.method!=='GET'){res.setHeader('Allow','GET');return res.status(405).json({state:'method_not_allowed'})}
 try{
  if(!recent||Date.now()-Date.parse(recent.checkedAt)>=240000){
   if(!pending)pending=inspectFestSource().then(v=>(recent=v)).finally(()=>{pending=null});
   await pending;
  }
  return res.status(200).json(recent);
 }catch{console.error('FEST source availability check failed');return res.status(503).json({state:'unavailable'})}
}
