import {allowStagingAuthMutation} from './stagingAuthGuard.js';

export function normalizeRecoveryEmail(value){return typeof value==='string'?value.trim().toLowerCase():'';}
export function recoveryRequestError(error){
 if(error?.code==='over_email_send_rate_limit')return 'تم بلوغ حد إرسال رسائل البريد في QA مؤقتاً. انتظر نحو ساعة قبل محاولة واحدة جديدة؛ تكرار الضغط لن يرسل رسالة.';
 if(error?.code==='over_request_rate_limit'||error?.status===429)return 'طلبات الاسترداد كثيرة حالياً. انتظر قبل المحاولة مجدداً ولا تكرر الضغط.';
 if(error?.code==='email_address_not_authorized')return 'خدمة البريد التجريبية لا تسمح بالإرسال إلى هذا العنوان حالياً. يلزم إعداد بريد SMTP لمشروع QA.';
 return 'تعذر إرسال طلب الاسترداد حالياً. تحقق من إعدادات البريد أو حاول لاحقاً.';
}
export async function verifyStagingRecoveryCode({auth,email,token,environment}){
 if(!allowStagingAuthMutation(environment))return {ok:false,message:'التحقق معطّل خارج مشروع QA المعتمد.'};
 if(!isValidRecoveryEmail(email)||typeof token!=='string'||!/^\d{6,10}$/.test(token.trim()))return {ok:false,message:'أدخل البريد ورمز الاسترداد المكوّن من 6 إلى 10 أرقام كما وصلك.'};
 try{
  const {data,error}=await auth.verifyOtp({email:normalizeRecoveryEmail(email),token:token.trim(),type:'recovery'});
  if(error)return {ok:false,message:error.status===429?recoveryRequestError(error):'رمز الاسترداد غير صحيح أو استُخدم أو انتهت صلاحيته. استخدم أحدث رمز من البريد.'};
  if(!data?.session?.user)return {ok:false,message:'لم يتم تأكيد جلسة الاسترداد. اطلب رمزاً جديداً.'};
  return {ok:true,message:'تم تأكيد الرمز. يمكنك تعيين كلمة المرور.'};
 }catch{return {ok:false,message:'تعذر الاتصال للتحقق من الرمز. حاول مجدداً.'}}
}
export function isValidRecoveryEmail(value){const email=normalizeRecoveryEmail(value);return email.length<=254&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);}
export function isAllowedRecoveryRedirect(value,expectedOrigin){if(typeof value!=='string'||typeof expectedOrigin!=='string')return false;try{const url=new URL(value);const origin=new URL(expectedOrigin);return url.protocol==='https:'&&origin.protocol==='https:'&&url.origin===origin.origin&&url.hostname.endsWith('.vercel.app')&&((url.pathname==='/admin'&&!url.hash)||(url.pathname==='/'&&url.hash==='#admin'))&&!url.search&&!url.username&&!url.password;}catch{return false}}
export async function requestStagingPasswordRecovery({supabase,email,redirectTo,environment}){
 if(!allowStagingAuthMutation(environment))return {ok:false,message:'استرداد الحساب معطّل خارج بيئة المصادقة التجريبية المعتمدة.'};
 if(!isValidRecoveryEmail(email))return {ok:false,message:'يرجى إدخال بريد إلكتروني صحيح.'};
 if(!isAllowedRecoveryRedirect(redirectTo,environment?.redirectOrigin))return {ok:false,message:'رابط العودة غير معتمد.'};
 if(!supabase?.auth?.resetPasswordForEmail)return {ok:false,message:'خدمة المصادقة غير متاحة.'};
 try{const {error}=await supabase.auth.resetPasswordForEmail(normalizeRecoveryEmail(email),{redirectTo});if(error)return {ok:false,message:recoveryRequestError(error)};return {ok:true,message:'إذا كان البريد مسجلاً، ستصلك رسالة الاسترداد. تحقق من صندوق البريد.'};}
 catch{return {ok:false,message:'تعذر الاتصال بخدمة الاسترداد.'}}
}
