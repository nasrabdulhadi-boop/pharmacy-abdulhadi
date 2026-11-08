import test from 'node:test';
import assert from 'node:assert/strict';
import {recoveryCallbackState,createRecoveryFlow,saveRecoveredPassword} from '../src/passwordRecoveryFlow.js';

test('expired callbacks in fragment or query open recovery, without reflecting provider messages',()=>{
 assert.equal(recoveryCallbackState({hash:'#error=access_denied&error_code=otp_expired&error_description=untrusted'},true),'invalid');
 assert.equal(recoveryCallbackState({search:'?error_code=otp_expired'},true),'invalid');
 assert.equal(recoveryCallbackState({hash:'#admin'},true),'idle');
 assert.equal(recoveryCallbackState({hash:'#type=recovery&access_token=secret'},false),'idle');
});
test('recovery intent alone never enables password updates; a verified SDK event is required',()=>{
 const flow=createRecoveryFlow(recoveryCallbackState({hash:'#type=recovery&access_token=secret'},true));
 assert.equal(flow.getState(),'pending');flow.onAuthEvent('SIGNED_IN',{user:{id:'test'}});
 flow.initialized();assert.equal(flow.getState(),'pending');flow.timeout();assert.equal(flow.getState(),'failed');
 flow.onAuthEvent('PASSWORD_RECOVERY',null);assert.equal(flow.getState(),'failed');
 flow.onAuthEvent('PASSWORD_RECOVERY',{user:{id:'test'}});assert.equal(flow.getState(),'ready');
 flow.initialized();assert.equal(flow.getState(),'ready');
 flow.onAuthEvent('SIGNED_OUT',null);assert.equal(flow.getState(),'invalid');
});
test('fast recovery event survives React subscription and explicit restart does not expose an old session',()=>{
 const flow=createRecoveryFlow();flow.onAuthEvent('PASSWORD_RECOVERY',{user:{id:'qa'}});
 assert.equal(flow.getState(),'ready');const seen=[];const unsubscribe=flow.subscribe(s=>seen.push(s));
 flow.restart();flow.reset();unsubscribe();flow.restart();assert.deepEqual(seen,['invalid','idle']);
});
test('password changes are blocked for production, unverified callbacks, mismatch and short values',async()=>{
 let calls=0;const auth={getSession:async()=>{calls++;return {data:{session:{}}}},updateUser:async()=>{calls++;return {error:null}}};
 const base={auth,password:'a-long-test-password',confirmation:'a-long-test-password',enabled:true,recoveryState:'ready'};
 for(const override of [{enabled:false},{recoveryState:'pending'},{confirmation:'different'},{password:'short',confirmation:'short'},{password:'a'.repeat(129),confirmation:'a'.repeat(129)}])assert.equal((await saveRecoveredPassword({...base,...override})).ok,false);
 assert.equal(calls,0);
});
test('valid QA recovery updates only password and handles an expired session without writes',async()=>{
 const inputs={password:'a-long-test-password',confirmation:'a-long-test-password',enabled:true,recoveryState:'ready'};
 let written=null;const auth={getSession:async()=>({data:{session:{user:{id:'qa'}}}}),updateUser:async args=>{written=args;return {error:null}}};
 assert.equal((await saveRecoveredPassword({...inputs,auth})).ok,true);assert.deepEqual(written,{password:inputs.password});
 written=null;auth.getSession=async()=>({data:{session:null}});
 assert.equal((await saveRecoveredPassword({...inputs,auth})).ok,false);assert.equal(written,null);
});
test('auth failures do not leak provider errors, credentials or URLs into messages',async()=>{
 const inputs={password:'a-long-test-password',confirmation:'a-long-test-password',enabled:true,recoveryState:'ready'};
 for(const error of [{code:'same_password'},new Error('sensitive token=secret')]){
  const result=await saveRecoveredPassword({...inputs,auth:{getSession:async()=>({data:{session:{}}}),updateUser:async()=>({error})}});
  assert.equal(result.ok,false);assert.doesNotMatch(result.message,/secret|token=/);
 }
});

test('invitation callback needs the verified invited identity before opening password setup',()=>{
 const flow=createRecoveryFlow(recoveryCallbackState({hash:'#type=invite&access_token=synthetic'},true));assert.equal(flow.getState(),'pending');assert.equal(flow.isInvitation(),true);
 flow.onAuthEvent('SIGNED_IN',{user:{id:'ordinary'}});assert.equal(flow.getState(),'pending');
 flow.onAuthEvent('SIGNED_IN',{user:{id:'invited',email_confirmed_at:'2026-11-08',app_metadata:{qa_invitation_id:'synthetic'}}});assert.equal(flow.getState(),'ready');
 flow.reset();assert.equal(flow.isInvitation(),false);assert.equal(flow.getState(),'idle');
});
test('ordinary login never becomes an invitation password setup',()=>{
 const flow=createRecoveryFlow();flow.onAuthEvent('SIGNED_IN',{user:{email_confirmed_at:'now',app_metadata:{qa_invitation_id:'old-invitation'}}});assert.equal(flow.getState(),'idle');
});
