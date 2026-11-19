import {staffFields,validStaffPassword} from './qaStaffAccounts.js';
export function validateStaffAccountForm({mode='create',profile={},email='',password='',confirmation='',managerPassword=''}){
 const errors={};
 if(mode!=='password'){
  for(const [key,max]of Object.entries(staffFields))if(typeof (profile[key]??'')!=='string'||(profile[key]||'').trim().length>max)errors[key]='قيمة الحقل أطول من الحد المسموح.';
  if(typeof profile.full_name!=='string'||profile.full_name.trim().length<2)errors.full_name='أدخل الاسم الكامل من محرفين على الأقل.';
  const date=profile.start_date;
  if(date&&(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!Number.isFinite(Date.parse(date))||new Date(date).toISOString().slice(0,10)!==date))errors.start_date='أدخل تاريخ بدء عمل صالحاً.';
 }
 if(mode==='create'&&(typeof email!=='string'||email.trim().length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())))errors.email='أدخل بريد تسجيل دخول صالحاً.';
 if(mode!=='profile'){
  if(!validStaffPassword(password))errors.password='كلمة المرور تحتاج 12 إلى 128 محرفاً وحروفاً إنكليزية وأرقاماً ورمزاً مثل ! أو @.';
  if(!confirmation)errors.confirmation='أعد إدخال كلمة المرور في حقل التأكيد.';
  else if(password!==confirmation)errors.confirmation='كلمة المرور وتأكيدها غير متطابقين.';
 }
 if(mode==='password'&&(typeof managerPassword!=='string'||!managerPassword||managerPassword.length>1024))errors.managerPassword='أدخل كلمة مرور المدير لتأكيد التغيير.';
 return errors;
}
