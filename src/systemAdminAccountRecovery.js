import {isStagingAuthMutationEnabled} from './stagingAuthGuard.js';

export function normalizeRecoveryEmail(value){return typeof value==='string'?value.trim().toLowerCase():'';}
export function isValidRecoveryEmail(value){const email=normalizeRecoveryEmail(value);return email.length<=254&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);}
export function isAllowedRecoveryRedirect(value){if(typeof value!=='string')return false;try{const url=new URL(value);return url.protocol==='https:'&&url.hostname.endsWith('.vercel.app')&&url.pathname.startsWith('/admin')&&!url.username&&!url.password;}catch{return false}}
export async function requestStagingPasswordRecovery({supabase,email,redirectTo,environment}){
 if(!isStagingAuthMutationEnabled(environment))return {ok:false,message:'استرداد الحساب معطّل خارج بيئة المصادقة التجريبية المعتمدة.'};
 if(!isValidRecoveryEmail(email))return {ok:false,message:'يرجى إدخال بريد إلكتروني صحيح.'};
 if(!isAllowedRecoveryRedirect(redirectTo))return {ok:false,message:'رابط العودة غير معتمد.'};
 if(!supabase?.auth?.resetPasswordForEmail)return {ok:false,message:'خدمة المصادقة غير متاحة.'};
 try{const {error}=await supabase.auth.resetPasswordForEmail(normalizeRecoveryEmail(email),{redirectTo});if(error)return {ok:false,message:'تعذر إرسال الطلب. حاول لاحقاً.'};return {ok:true,message:'إذا كان البريد مسجلاً، ستصلك رسالة الاسترداد. تحقق من صندوق البريد.'};}
 catch{return {ok:false,message:'تعذر الاتصال بخدمة الاسترداد.'}}
}
