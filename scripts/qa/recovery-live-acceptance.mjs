// QA-only disposable fixture. This verifies hosted Auth, NOT email delivery.
// The fixture must be provisioned separately; never use a personal account.
import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {createRecoveryFlow,saveRecoveredPassword} from '../../src/passwordRecoveryFlow.js';
import {verifyStagingRecoveryCode} from '../../src/systemAdminAccountRecovery.js';
const url='https://vpjxdsprfcpqclnhbeoh.supabase.co';
const key=process.env.QA_PUBLISHABLE_KEY;assert.ok(key);
const fixture=JSON.parse(readFileSync('/tmp/pharmacy-qa-recovery-fixture.json'));
assert.match(fixture.email,/^qa-close-[a-z0-9]+-recovery@example\.invalid$/);
const resultFile='/tmp/pharmacy-qa-recovery-live-results.json';
const results=existsSync(resultFile)?JSON.parse(readFileSync(resultFile)):[];
const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
const environment={mode:'staging',enabled:'true',url,publishableKey:key};
const record=(name,condition)=>{assert.ok(condition,name);results.push({name,passed:true});};
try{
 if(process.argv[2]==='expired'){
  const result=await verifyStagingRecoveryCode({auth:client.auth,email:fixture.email,token:fixture.token,environment});
  record('hosted Auth rejects expired synthetic recovery OTP',!result.ok);
 }else if(process.argv[2]==='valid'){
  const flow=createRecoveryFlow();const sub=client.auth.onAuthStateChange((event,session)=>flow.onAuthEvent(event,session));
  const bad=await verifyStagingRecoveryCode({auth:client.auth,email:fixture.email,token:fixture.token==='000000'?'000001':'000000',environment});
  record('hosted Auth rejects incorrect recovery OTP',!bad.ok);
  const verified=await verifyStagingRecoveryCode({auth:client.auth,email:fixture.email,token:fixture.token,environment});
  record('hosted Auth verifies fresh synthetic recovery OTP',verified.ok);
  record('real SDK PASSWORD_RECOVERY event unlocks form',flow.getState()==='ready');
  const updated=await saveRecoveredPassword({auth:client.auth,password:fixture.newPassword,confirmation:fixture.newPassword,enabled:true,recoveryState:flow.getState()});
  record('password recovery saves through real hosted Auth',updated.ok);
  record('recovered identity remains the disposable owner',(await client.auth.getUser()).data?.user?.id===fixture.id);
  const reuse=await verifyStagingRecoveryCode({auth:client.auth,email:fixture.email,token:fixture.token,environment});
  record('used recovery OTP cannot be replayed',!reuse.ok);
  await client.auth.signOut({scope:'global'});
  const old=await client.auth.signInWithPassword({email:fixture.email,password:fixture.password});
  record('old password no longer authenticates',!!old.error&&!old.data.session);
  const fresh=await client.auth.signInWithPassword({email:fixture.email,password:fixture.newPassword});
  record('fresh password authenticates the same owner',!fresh.error&&fresh.data.user?.id===fixture.id);
  record('password update preserves server-issued owner role',fresh.data.user?.app_metadata?.system_role==='system_owner');
  await client.auth.signOut({scope:'global'});sub.data.subscription.unsubscribe();
 }else throw new Error('Choose expired or valid fixture phase');
}catch(error){results.push({name:'recovery phase '+process.argv[2],passed:false,error:error.code||error.name});process.exitCode=1;}
finally{writeFileSync(resultFile,JSON.stringify(results,null,2));console.log({passed:results.filter(r=>r.passed).length,failed:results.filter(r=>!r.passed).length,emailDeliveryTested:false});}
