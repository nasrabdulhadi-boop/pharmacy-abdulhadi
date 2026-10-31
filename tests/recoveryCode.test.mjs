import test from 'node:test';
import assert from 'node:assert/strict';
import {verifyStagingRecoveryCode} from '../src/systemAdminAccountRecovery.js';
const environment={mode:'staging',enabled:'true',url:'https://vpjxdsprfcpqclnhbeoh.supabase.co',publishableKey:'qa-fixture'};

test('recovery OTP uses the recovery grant only and requires a verified returned session',async()=>{
 let called=0;const auth={verifyOtp:async args=>{called++;assert.deepEqual(args,{email:'test@example.com',token:'123456',type:'recovery'});return {data:{session:{user:{id:'fixture'}}}}}};
 assert.equal((await verifyStagingRecoveryCode({auth,email:' Test@Example.com ',token:'123456',environment})).ok,true);assert.equal(called,1);
 auth.verifyOtp=async()=>({data:{session:null}});
 assert.equal((await verifyStagingRecoveryCode({auth,email:'test@example.com',token:'123456',environment})).ok,false);
});
test('production and malformed codes never call auth, and provider failures expose no secrets',async()=>{
 let called=0;const auth={verifyOtp:async()=>{called++;return {error:{message:'private secret',code:'otp_expired'}}}};
 const base={auth,email:'test@example.com',token:'123456',environment};
 for(const override of [{environment:{...environment,mode:'production'}},{environment:{...environment,url:'https://eewjjzgwoaxhojnjvzgq.supabase.co'}},{token:'invalid'},{email:'invalid'}])assert.equal((await verifyStagingRecoveryCode({...base,...override})).ok,false);
 assert.equal(called,0);
 const result=await verifyStagingRecoveryCode(base);assert.equal(result.ok,false);assert.doesNotMatch(result.message,/private|secret/);
});
