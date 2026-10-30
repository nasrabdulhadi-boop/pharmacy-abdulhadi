import test from 'node:test';
import assert from 'node:assert/strict';
import {requestStagingPasswordRecovery,isValidRecoveryEmail,isAllowedRecoveryRedirect,recoveryRequestError} from '../src/systemAdminAccountRecovery.js';
const staging={mode:'staging',enabled:'true',url:'https://vpjxdsprfcpqclnhbeoh.supabase.co',publishableKey:'qa-public-test-key',redirectOrigin:'https://pharmacy-qa.vercel.app'};
const valid='https://pharmacy-qa.vercel.app/admin';
test('recovery failures explain quota and recipient restrictions without exposing raw errors',async()=>{
 assert.match(recoveryRequestError({code:'over_email_send_rate_limit',status:429}),/حد إرسال رسائل البريد/);
 assert.match(recoveryRequestError({status:429}),/طلبات الاسترداد كثيرة/);
 assert.match(recoveryRequestError({code:'email_address_not_authorized'}),/SMTP/);
 assert.doesNotMatch(recoveryRequestError({message:'secret token'}),/secret|token/);
 const result=await requestStagingPasswordRecovery({supabase:{auth:{resetPasswordForEmail:async()=>({error:{code:'over_email_send_rate_limit',status:429}})}},email:'test@example.com',redirectTo:valid,environment:staging});
 assert.equal(result.ok,false);assert.match(result.message,/حد إرسال رسائل البريد/);
});
test('email normalization and redirect guard reject unsafe inputs',()=>{
 assert.equal(isValidRecoveryEmail(' test@example.com '),true);
 for(const value of ['invalid','a@b',''])assert.equal(isValidRecoveryEmail(value),false);
 for(const value of ['http://pharmacy-qa.vercel.app/admin','https://evil.com/admin','https://pharmacy-qa.vercel.app.evil.com/admin','https://pharmacy-qa.vercel.app/settings'])assert.equal(isAllowedRecoveryRedirect(value,staging.redirectOrigin),false);
 assert.equal(isAllowedRecoveryRedirect(valid,staging.redirectOrigin),true);
 assert.equal(isAllowedRecoveryRedirect('https://pharmacy-qa.vercel.app/#admin',staging.redirectOrigin),true);
 for(const value of ['https://other.vercel.app/admin','https://pharmacy-qa.vercel.app/admin/extra','https://pharmacy-qa.vercel.app/admin?token=x','https://pharmacy-qa.vercel.app/admin#x'])assert.equal(isAllowedRecoveryRedirect(value,staging.redirectOrigin),false);
});
test('production configuration cannot send recovery mail',async()=>{
 let calls=0;const supabase={auth:{resetPasswordForEmail:async()=>{calls++;return {error:null}}}};
 const result=await requestStagingPasswordRecovery({supabase,email:'test@example.com',redirectTo:valid,environment:{...staging,mode:'production'}});
 assert.equal(result.ok,false);assert.equal(calls,0);
});
test('staging valid request calls auth API once and avoids account enumeration',async()=>{
 let calls=0;const supabase={auth:{resetPasswordForEmail:async(email,options)=>{calls++;assert.equal(email,'test@example.com');assert.equal(options.redirectTo,valid);return {error:null}}}};
 const result=await requestStagingPasswordRecovery({supabase,email:' Test@Example.com ',redirectTo:valid,environment:staging});
 assert.equal(result.ok,true);assert.equal(calls,1);assert.match(result.message,/إذا كان البريد مسجلاً/);
});
