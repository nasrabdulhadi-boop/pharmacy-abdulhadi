import test from 'node:test';
import assert from 'node:assert/strict';
import {createSupplierFullPreviewClient,PREVIEW_GATEWAY} from '../src/supplierFullPreviewClient.js';
const session={auth:{getSession:async()=>({data:{session:{access_token:'production-identity-test-token'}},error:null})}};
test('all data requests use QA gateway; original auth is reused without forwarding passwords',async()=>{
 const calls=[];const fetcher=async(url,init)=>{calls.push({url,init,body:JSON.parse(init.body)});return {ok:true,json:async()=>({data:[{id:1},{id:2},{id:3}],error:null})}};
 const client=createSupplierFullPreviewClient(session,'qa-publishable',fetcher);
 const rows=await client.rpc('admin_get_inventory').range(1,1);assert.deepEqual(rows.data,[{id:2}]);
 const q=client.from('orders').select('id,status').eq('status','new').gte('created_at','2026-10-30').order('created_at',{ascending:false}).limit(10);
 await q;await q;assert.equal(calls.length,2,'one execution for repeated awaits');
 await client.from('batches').update({quantity:2}).eq('id','test-id');
 await client.verifyOriginalAdmin();
 for(const c of calls){assert.equal(c.url,PREVIEW_GATEWAY);assert.equal(c.init.method,'POST');assert.equal(c.init.headers.Authorization,'Bearer production-identity-test-token');assert.ok(!c.init.body.includes('password'));}
 assert.equal(calls[1].body.payload.filters.length,2);assert.equal(calls[2].body.kind,'table');assert.equal(calls[3].body.kind,'identity');
});
test('missing login or gateway failure never falls back to production data',async()=>{
 let count=0;const fetcher=async()=>{count++;throw Error('offline')};
 const signedOut=createSupplierFullPreviewClient({auth:{getSession:async()=>({data:{session:null}})}},'key',fetcher);
 assert.ok((await signedOut.rpc('admin_products_count')).error);assert.equal(count,0);
 const client=createSupplierFullPreviewClient(session,'key',fetcher);assert.ok((await client.rpc('admin_products_count')).error);assert.equal(count,1);
});
test('single records and admin shortcut writes keep expected query shapes',async()=>{
 const calls=[];const client=createSupplierFullPreviewClient(session,'key',async(url,init)=>{calls.push(JSON.parse(init.body));return {ok:true,json:async()=>({data:[],error:null})}});
 assert.equal((await client.from('pos_shortcut_preferences').select('items').eq('user_id','owner').maybeSingle()).data,null);
 await client.from('pos_shortcut_preferences').upsert({user_id:'owner',items:[]},{onConflict:'user_id'});
 assert.equal(calls[1].payload.action,'upsert');assert.equal(calls[1].payload.data.user_id,'owner');
});
