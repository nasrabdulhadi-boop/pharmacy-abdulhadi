import test from 'node:test';
import assert from 'node:assert/strict';
import {handleInvite} from '../supabase/functions/qa-admin-account-invite/handler.js';
import {prepareQaInvitation,consumeQaInvitation,invitationRequestId} from '../src/qaAccountInvitations.js';
const qa='https://vpjxdsprfcpqclnhbeoh.supabase.co',origin='https://pharmacy-abdulhadi-qa-naser9.vercel.app',id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const body={request_id:id,email:' new@example.invalid ',role:'employee',redirect_to:origin+'/#admin'};
const link=origin+'/#type=invite&token_hash='+'a'.repeat(64);
function mocks({actor='system_owner',reserveError=null,generateError=null,finalizeError=null,privilegedOnFailure=false,returnedHash='a'.repeat(64)}={}){
 const calls=[];
 const scoped={auth:{getUser:async()=>({data:{user:{id:'actor'}},error:null})},rpc:async(name,args)=>{calls.push([name,args]);return name==='qa_my_role'?{data:actor,error:null}:{data:true,error:reserveError};}};
 const admin={auth:{admin:{generateLink:async args=>{calls.push(['generate',args]);return {error:generateError,data:generateError?null:{user:{id:'new'},properties:{hashed_token:returnedHash}}};},getUserById:async()=>({data:{user:{id:'new',email:'new@example.invalid',user_metadata:{qa_invitation_id:id},app_metadata:privilegedOnFailure?{system_role:'system_owner'}:{},email_confirmed_at:null}}}),deleteUser:async user=>{calls.push(['delete',user]);return {error:null};}}},rpc:async(name,args)=>{calls.push([name,args]);return {data:true,error:name==='qa_service_finalize_invitation'?finalizeError:null};}};
 const config={projectUrl:qa,publishable:'public',secret:'server-only',createClient:(_url,key)=>key==='public'?scoped:admin};
 return {config,calls};
}
const request=(value=body,headers={})=>new Request(origin+'/invite',{method:'POST',headers:{Authorization:'Bearer synthetic','Content-Type':'application/json',Origin:origin,...headers},body:JSON.stringify(value)});
test('invitation returns only a validated single-use link after transactional role and audit completion',async()=>{
 const {config,calls}=mocks();const r=await handleInvite(request(),config),data=await r.json();assert.equal(r.status,200);assert.equal(data.email_sent,false);assert.equal(data.action_link,link);assert.equal(r.headers.get('Cache-Control'),'no-store');
 assert.deepEqual(calls.find(c=>c[0]==='generate')[1],{type:'invite',email:'new@example.invalid',options:{redirectTo:body.redirect_to,data:{qa_invitation_id:id}}});
 assert.deepEqual(calls.map(c=>c[0]),['qa_my_role','qa_admin_reserve_invitation','generate','qa_service_finalize_invitation']);
});
test('employees, support and managers inviting managers cannot reach the privileged Auth API',async()=>{
 for(const [actor,role] of [['employee','employee'],['technical_support','employee'],['system_admin','system_admin']]){const {config,calls}=mocks({actor});const r=await handleInvite(request({...body,role}),config);assert.equal(r.status,403);assert.ok(!calls.some(c=>c[0]==='generate'));}
});
test('production, unsafe origins, oversized/null requests and cross-origin redirects fail closed',async()=>{
 for(const value of [{...body,redirect_to:'https://evil.invalid/#admin'},null]){const {config}=mocks();assert.equal((await handleInvite(request(value),config)).status,400);}
 const {config}=mocks();assert.equal((await handleInvite(request(body,{Origin:'https://evil.invalid'}),config)).status,403);
 assert.equal((await handleInvite(request(),{...config,projectUrl:'https://eewjjzgwoaxhojnjvzgq.supabase.co'})).status,403);
 assert.equal((await handleInvite(request(body,{'Content-Length':'5000'}),config)).status,400);
});
test('conflicts and rate limits never create an Auth account',async()=>{
 for(const [code,status] of [['23505',409],['54000',429]]){const {config,calls}=mocks({reserveError:{code}});const r=await handleInvite(request(),config);assert.equal(r.status,status);assert.ok(!calls.some(c=>c[0]==='generate'));}
});
test('failed finalization cleans only the new unconfirmed unprivileged fixture and hides provider details',async()=>{
 const {config,calls}=mocks({finalizeError:{message:'sensitive provider value'}});const r=await handleInvite(request(),config);assert.equal(r.status,503);assert.ok(calls.some(c=>c[0]==='delete'));assert.ok(calls.some(c=>c[0]==='qa_service_fail_invitation'));assert.doesNotMatch(await r.text(),/sensitive|token/);
 const protectedCase=mocks({finalizeError:{},privilegedOnFailure:true});await handleInvite(request(),protectedCase.config);assert.ok(!protectedCase.calls.some(c=>c[0]==='delete'));
});
test('missing one-time hashes fail before role assignment or link disclosure',async()=>{
 const {config,calls}=mocks({returnedHash:'invalid'});assert.equal((await handleInvite(request(),config)).status,503);assert.ok(!calls.some(c=>c[0]==='qa_service_finalize_invitation'));
});
test('client invitation helper verifies current identity and rejects production or unexpected link responses',async()=>{
 let calls=0;const client={auth:{getUser:async()=>({data:{user:{id:'actor'}}})},functions:{invoke:async()=>{calls++;return {data:{prepared:true,email_sent:false,user_id:'new',role:'employee',action_link:link}};}}};
 const options={client,projectUrl:qa,actorId:'actor',actorRole:'system_owner',email:'new@example.invalid',role:'employee',origin,requestId:id};
 assert.equal((await prepareQaInvitation(options)).emailSent,false);
 await assert.rejects(prepareQaInvitation({...options,projectUrl:'https://eewjjzgwoaxhojnjvzgq.supabase.co'}));await assert.rejects(prepareQaInvitation({...options,actorId:'other'}));assert.equal(calls,1);
 client.functions.invoke=async()=>({data:{prepared:true,email_sent:false,user_id:'new',role:'employee',action_link:'https://evil.invalid'}});await assert.rejects(prepareQaInvitation(options));
});

test('first-party invitation consumes its hash only on QA and removes it from the address bar',async()=>{
 const calls=[],session={user:{id:'invited'}},auth={verifyOtp:async args=>{calls.push(args);return {data:{session}};}};
 const options={auth,projectUrl:qa,enabled:true,hash:'#type=invite&token_hash='+'a'.repeat(64),clearFragment:()=>calls.push('cleared')};
 const result=await consumeQaInvitation(options);assert.equal(result.session,session);assert.deepEqual(calls,['cleared',{type:'invite',token_hash:'a'.repeat(64)}]);
 calls.length=0;assert.equal((await consumeQaInvitation({...options,projectUrl:'https://production.invalid'})).handled,false);assert.equal(calls.length,0);
 assert.equal((await consumeQaInvitation({...options,hash:'#type=invite&token_hash=bad'})).session,null);assert.deepEqual(calls,['cleared']);
});

test('provider SHA224 invitation hashes are accepted without assuming SHA256',async()=>{
 const {config}=mocks({returnedHash:'b'.repeat(56)});const r=await handleInvite(request(),config);assert.equal(r.status,200);assert.equal(new URLSearchParams(new URL((await r.json()).action_link).hash.slice(1)).get('token_hash'),'b'.repeat(56));
});
test('request IDs use secure random values when randomUUID is unavailable',()=>{
 const random={getRandomValues:bytes=>{bytes.fill(0);return bytes;}};assert.equal(invitationRequestId(random),'00000000-0000-4000-8000-000000000000');
});
