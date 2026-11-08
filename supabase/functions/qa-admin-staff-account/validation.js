export const staffFields={full_name:120,phone:40,address:500,job_title:120,employee_code:120,start_date:10,notes:2000};
export function cleanStaffProfile(value){
 if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!Object.hasOwn(staffFields,k)))throw Error('invalid_profile');
 const result={};for(const [key,max]of Object.entries(staffFields)){const v=value[key]??'';if(typeof v!=='string'||v.trim().length>max)throw Error('invalid_profile');result[key]=v.trim();}
 if(result.full_name.length<2)throw Error('invalid_profile');
 if(result.start_date&&(!/^\d{4}-\d{2}-\d{2}$/.test(result.start_date)||!Number.isFinite(Date.parse(result.start_date))||new Date(result.start_date).toISOString().slice(0,10)!==result.start_date))throw Error('invalid_profile');return result;
}
export function validStaffPassword(value){return typeof value==='string'&&value.length>=12&&value.length<=128&&/[A-Za-z]/.test(value)&&/[0-9]/.test(value)&&/[^A-Za-z0-9\s]/.test(value);}
export function cleanStaffCommand(body){
 if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some(k=>!['action','request_id','email','role','target_id','profile','password','manager_password'].includes(k)))throw Error('invalid_request');
 if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(body.request_id||''))throw Error('invalid_request');
 if(!validStaffPassword(body.password))throw Error('invalid_password');
 if(body.action==='create'){
  if(body.manager_password!==undefined)throw Error('invalid_request');
  const email=typeof body.email==='string'?body.email.trim().toLowerCase():'';
  if(email.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||body.target_id)throw Error('invalid_email');
  if(!['employee','technical_support'].includes(body.role))throw Error('not_authorized');
  return{action:'create',request_id:body.request_id,email,role:body.role,profile:cleanStaffProfile(body.profile),password:body.password};
 }
 if(body.action!=='password'||!/^[a-f0-9-]{36}$/.test(body.target_id||'')||body.email||body.role||body.profile)throw Error('invalid_request');
 if(typeof body.manager_password!=='string'||!body.manager_password||body.manager_password.length>1024)throw Error('manager_confirmation_required');
 return{action:'password',request_id:body.request_id,target_id:body.target_id,password:body.password,manager_password:body.manager_password};
}
