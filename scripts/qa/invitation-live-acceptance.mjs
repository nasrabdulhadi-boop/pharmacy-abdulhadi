// Real QA Auth/API tests. No emails sent. Only explicitly tagged synthetic identities.
import fs from 'node:fs';import assert from 'node:assert/strict';import {randomUUID,randomBytes} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';
import {createRecoveryFlow,recoveryCallbackState,saveRecoveredPassword} from '../../src/passwordRecoveryFlow.js';
const file=process.env.QA_ACCOUNT_FIXTURES,fixture=JSON.parse(fs.readFileSync(file,'utf8'));assert.equal(fixture.environment,'isolated-qa');assert.match(fixture.namespace,/^qa-invite-[a-f0-9]{12}$/);
const resume=process.env.QA_INVITATION_RESUME_REVOCATION==='true';
const qa='https://vpjxdsprfcpqclnhbeoh.supabase.co',origin='https://pharmacy-abdulhadi-fa9kd970j-naser9.vercel.app',results=resume?JSON.parse(fs.readFileSync('/tmp/qa-invitation-live-results.json','utf8')).results:[];
const check=(name,value)=>{assert.ok(value,name);if(!resume||!results.some(r=>r.name===name))results.push({name,passed:true});console.log(JSON.stringify({checks:results.length}));};
const client=()=>createClient(qa,fixture.key,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(u,o)=>fetch(u,{...o,signal:AbortSignal.timeout(30000)})}});
const sessions={};let knownCreated=fixture.invited||[];
const invoke=async(label,body)=>fetch(qa+'/functions/v1/qa-admin-account-invite',{method:'POST',headers:{apikey:fixture.key,Authorization:'Bearer '+sessions[label].token,'Content-Type':'application/json',Origin:origin},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
const request=(suffix,role='employee')=>({request_id:randomUUID(),email:fixture.namespace+'-'+suffix+'@example.com',role,redirect_to:origin+'/#admin'});
try{
 for(const user of fixture.users){const c=client(),r=await c.auth.signInWithPassword({email:user.email,password:user.password});assert.equal(r.error,null,'fixture login '+user.label);sessions[user.label]={c,token:r.data.session.access_token};if(resume&&user.label==='owner'){const r=await c.rpc('qa_admin_set_role',{p_user_id:fixture.users.find(u=>u.label==='manager').id,p_role:'system_admin'});assert.equal(r.error,null,'restore disposable manager for revoked-session check');}}
 if(!resume){
 for(const label of ['employee','support']){const r=await invoke(label,request(label+'-denied'));check(label+' cannot prepare invitation',r.status===403);}
 const escalation=await invoke('manager',request('escalation','system_admin'));check('manager cannot invite another manager',escalation.status===403);
 const privileged=await sessions.owner.c.rpc('qa_service_finalize_invitation',{p_id:randomUUID(),p_target:randomUUID()});check('authenticated owner cannot call service finalizer directly',privileged.error?.code==='42501');
 const unchanged=await invoke('owner',{...request('unused'),email:fixture.users.find(u=>u.label==='owner').email});check('existing owner account is protected from invitation',unchanged.status===409);
 for(const [actor,suffix,role] of [['owner','new-employee','employee'],['manager','new-support','technical_support'],['owner','new-manager','system_admin']]){
  const body=request(suffix,role),r=await invoke(actor,body),data=await r.json();if(r.status!==200)console.error(JSON.stringify({stage:'prepare',status:r.status,error:data.error,reason:data.reason}));
  check(actor+' prepares '+role+' without sending email',r.status===200&&data.prepared===true&&data.email_sent===false&&data.role===role);
  knownCreated.push({id:data.user_id,email:body.email,requestId:body.request_id});fixture.invited=knownCreated;fs.writeFileSync(file,JSON.stringify(fixture),{mode:0o600});
  const link=new URL(data.action_link);check('invitation uses QA verify endpoint and allowed callback',link.origin===origin&&link.pathname==='/'&&new URLSearchParams(link.hash.slice(1)).get('type')==='invite');
  const duplicate=await invoke(actor,body);check('invitation replay cannot create a second account',duplicate.status===409);
  const recipient=client(),hash=new URLSearchParams(link.hash.slice(1)).get('token_hash');assert.ok(hash,'QA invitation hash present');
  const accepted=await recipient.auth.verifyOtp({token_hash:hash,type:'invite'});check('recipient accepts one-use invitation token',!accepted.error&&accepted.data.user?.id===data.user_id&&!!accepted.data.session);
  const flow=createRecoveryFlow(recoveryCallbackState({hash:link.hash},true));flow.onAuthEvent('SIGNED_IN',accepted.data.session);check('verified invitation enters password setup',flow.getState()==='ready'&&flow.isInvitation());
  const password='Qa!'+randomBytes(24).toString('hex');const saved=await saveRecoveredPassword({auth:recipient.auth,password,confirmation:password,enabled:true,recoveryState:flow.getState()});check('recipient can choose a password',saved.ok);
  const roleResult=await recipient.rpc('qa_my_role');check('server grants exactly the invited role',!roleResult.error&&roleResult.data===role);
  const replay=await client().auth.verifyOtp({token_hash:hash,type:'invite'});check('consumed invitation token is rejected',!!replay.error);
  await recipient.auth.signOut({scope:'global'});const signed=await recipient.auth.signInWithPassword({email:body.email,password});check('recipient can sign in with the chosen password',!signed.error&&signed.data.user?.id===data.user_id);await recipient.auth.signOut({scope:'global'});
 }
 }
 const manager=fixture.users.find(u=>u.label==='manager');const changed=await sessions.owner.c.rpc('qa_admin_set_role',{p_user_id:manager.id,p_role:'technical_support'});check('owner can revoke temporary manager authority',!changed.error&&changed.data===true);
 const stale=await invoke('manager',request('stale-session'));console.log(JSON.stringify({revokedSessionHttpStatus:stale.status}));check('stale manager JWT loses invitation access immediately',[401,403].includes(stale.status));
 console.log(JSON.stringify({passed:results.length,failed:0,emailSent:false,browserTested:false}));
}catch(error){console.error(JSON.stringify({passed:results.length,error:error.message}));process.exitCode=1;}
finally{for(const s of Object.values(sessions))await s.c.auth.signOut({scope:'global'});fs.writeFileSync('/tmp/qa-invitation-live-results.json',JSON.stringify({results},null,2),{mode:0o600});}
