import test from 'node:test';
import assert from 'node:assert/strict';
import {saveOwnQaProfile,requestOwnQaEmailChange,signOutOtherQaSessions} from '../src/systemAdminProfileActions.js';
const base={previewEnabled:true,projectUrl:'https://vpjxdsprfcpqclnhbeoh.supabase.co',expectedUserId:'test-user',name:'  QA Pharmacist  ',email:'  NEW@example.invalid ',origin:'https://pharmacy-preview.vercel.app',redirectTo:'https://pharmacy-preview.vercel.app/#admin'};
function fixture(id='test-user',failure=null){const calls=[];return {calls,auth:{getUser:async()=>({data:{user:{id,email:'old@example.invalid'}},error:null}),updateUser:async(...args)=>{calls.push(args);return {data:{user:{id}},error:failure}},signOut:async arg=>{calls.push(arg);return {error:failure}}}}}
test('profile, email and session actions cannot write to production or a switched identity',async()=>{
 for(const action of [saveOwnQaProfile,requestOwnQaEmailChange,signOutOtherQaSessions])for(const overrides of [{projectUrl:'https://eewjjzgwoaxhojnjvzgq.supabase.co'},{previewEnabled:false},{expectedUserId:'old-user'}]){const client=fixture();await assert.rejects(action({...base,...overrides,client}));assert.deepEqual(client.calls,[]);}
});
test('profile writes only display metadata; a name never grants a role',async()=>{const client=fixture();assert.deepEqual(await saveOwnQaProfile({...base,client}),{name:'QA Pharmacist'});assert.deepEqual(client.calls,[[{data:{full_name:'QA Pharmacist'}}]]);});
test('invalid names and unsafe email redirects never reach Auth writes',async()=>{
 for(const name of ['','a'.repeat(101),'unsafe\nname']){const client=fixture();await assert.rejects(saveOwnQaProfile({...base,client,name}),/invalid_name/);assert.equal(client.calls.length,0);}
 for(const overrides of [{email:'bad'},{email:'old@example.invalid'},{redirectTo:'https://evil.vercel.app/#admin'},{redirectTo:base.redirectTo+'?token=bad'}]){const client=fixture();await assert.rejects(requestOwnQaEmailChange({...base,...overrides,client}));assert.equal(client.calls.length,0);}
});
test('email change requests confirmation through Auth without asserting delivery or editing roles',async()=>{const client=fixture();assert.deepEqual(await requestOwnQaEmailChange({...base,client}),{requested:true,confirmed:false});assert.deepEqual(client.calls,[[{email:'new@example.invalid'},{emailRedirectTo:base.redirectTo}]]);});
test('other-session revocation preserves the current session and sanitizes failures',async()=>{const client=fixture();assert.deepEqual(await signOutOtherQaSessions({...base,client}),{othersSignedOut:true});assert.deepEqual(client.calls,[{scope:'others'}]);await assert.rejects(signOutOtherQaSessions({...base,client:fixture('test-user',{message:'sensitive'})}),/^Error: session_revoke_failed$/);});
