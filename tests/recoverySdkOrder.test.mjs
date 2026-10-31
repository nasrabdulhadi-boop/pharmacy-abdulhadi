// Auth SDK integration test with synthetic tokens and a fake in-memory browser surface.
// No network, real account, email delivery or deployed authentication is used.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {createRecoveryFlow,recoveryCallbackState} from '../src/passwordRecoveryFlow.js';

test('installed SDK deferred PASSWORD_RECOVERY is accepted after getSession initialization',async()=>{
 const callback=new URL('https://fixture.vercel.app/#access_token=fixture&refresh_token=fixture-refresh&expires_in=3600&token_type=bearer&type=recovery');
 const originalWindow=globalThis.window,originalDocument=globalThis.document;
 globalThis.window={location:callback,addEventListener(){},removeEventListener(){},history:{replaceState(){}}};
 globalThis.document={visibilityState:'visible',addEventListener(){},removeEventListener(){}};
 const flow=createRecoveryFlow(recoveryCallbackState(callback,true));
 let client;
 try{
  client=createClient('https://fixture.supabase.co','fixture-key',{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:true,lock:async(_name,_timeout,fn)=>fn()},global:{fetch:async()=>new Response(JSON.stringify({id:'fixture',aud:'authenticated',role:'authenticated',email:'test@example.com',app_metadata:{},user_metadata:{}}),{status:200,headers:{'content-type':'application/json'}})}});
  const ready=new Promise(resolve=>{flow.subscribe(state=>{if(state==='ready')resolve()})});
  const {data:{subscription}}=client.auth.onAuthStateChange((event,session)=>flow.onAuthEvent(event,session));
  const {data,error}=await client.auth.getSession();assert.equal(error,null);assert.ok(data.session);
  flow.initialized();assert.notEqual(flow.getState(),'invalid');
  await Promise.race([ready,new Promise((_,reject)=>{const timer=setTimeout(()=>reject(Error('PASSWORD_RECOVERY missing')),1000);timer.unref()})]);
  assert.equal(flow.getState(),'ready');subscription.unsubscribe();
 }finally{
  await client?.auth.stopAutoRefresh();
  if(originalWindow===undefined)delete globalThis.window;else globalThis.window=originalWindow;
  if(originalDocument===undefined)delete globalThis.document;else globalThis.document=originalDocument;
 }
});
