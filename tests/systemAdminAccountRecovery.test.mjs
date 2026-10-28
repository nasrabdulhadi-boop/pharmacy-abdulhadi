import test from 'node:test';
import assert from 'node:assert/strict';
import {requestStagingPasswordRecovery,isValidRecoveryEmail,isAllowedRecoveryRedirect} from '../src/systemAdminAccountRecovery.js';
const staging={mode:'staging',enabled:'true',url:'https://vpjxdsprfcpqclnhbeoh.supabase.co',publishableKey:'qa-public-test-key'};
const valid='https://pharmacy-qa.vercel.app/admin';
test('email normalization and redirect guard reject unsafe inputs',()=>{
 assert.equal(isValidRecoveryEmail(' test@example.com '),true);
 for(const value of ['invalid','a@b',''])assert.equal(isValidRecoveryEmail(value),false);
 for(const value of ['http://pharmacy-qa.vercel.app/admin','https://evil.com/admin','https://pharmacy-qa.vercel.app.evil.com/admin','https://pharmacy-qa.vercel.app/settings'])assert.equal(isAllowedRecoveryRedirect(value),false);
 assert.equal(isAllowedRecoveryRedirect(valid),true);
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
