// Read callback intent before the Auth SDK consumes the URL fragment. Never retain tokens.
export function recoveryCallbackState(location,enabled){
 if(!enabled||!location)return 'idle';
 const hash=new URLSearchParams((location.hash||'').replace(/^#/,''));
 const search=new URLSearchParams(location.search||'');
 if(hash.has('error')||hash.has('error_code')||search.has('error')||search.has('error_code'))return 'invalid';
 return hash.get('type')==='recovery'?'pending':'idle';
}
export function createRecoveryFlow(initial='idle'){
 let state=initial;const listeners=new Set();
 const set=next=>{state=next;for(const fn of listeners)fn(state)};
 return {getState:()=>state,subscribe(fn){listeners.add(fn);return()=>listeners.delete(fn)},
  onAuthEvent(event,session){if(event==='PASSWORD_RECOVERY'&&session?.user)set('ready');else if(event==='SIGNED_OUT'&&state==='ready')set('invalid')},
  initialized(){if(state==='pending')set('invalid')},restart(){set('invalid')},reset(){set('idle')}};
}
export async function saveRecoveredPassword({auth,password,confirmation,enabled,recoveryState}){
 if(!enabled||recoveryState!=='ready')return {ok:false,message:'رابط الاسترداد غير صالح. اطلب رابطاً جديداً.'};
 if(typeof password!=='string'||password.length<12)return {ok:false,message:'استخدم كلمة مرور من 12 محرفاً على الأقل.'};
 if(password!==confirmation)return {ok:false,message:'كلمتا المرور غير متطابقتين.'};
 try{
  const {data:sessionData,error:sessionError}=await auth.getSession();
  if(sessionError||!sessionData?.session)return {ok:false,message:'انتهت جلسة الاسترداد. اطلب رابطاً جديداً.'};
  const {error}=await auth.updateUser({password});
  if(error)return {ok:false,message:error.code==='same_password'?'اختر كلمة مرور مختلفة عن السابقة.':'تعذر حفظ كلمة المرور. تحقق من متطلبات كلمة المرور أو اطلب رابطاً جديداً.'};
  return {ok:true,message:'تم حفظ كلمة المرور الجديدة بنجاح.'};
 }catch{return {ok:false,message:'تعذر الاتصال بخدمة المصادقة. حاول مجدداً.'}}
}
