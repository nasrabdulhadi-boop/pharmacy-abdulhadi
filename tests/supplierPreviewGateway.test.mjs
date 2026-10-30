import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {transformSync} from 'esbuild';
const code=transformSync(fs.readFileSync(new URL('../supabase/functions/supplier-original-admin-preview/index.ts',import.meta.url),'utf8'),{loader:'ts',format:'cjs'}).code;
const actor='15cdd7b6-cbfa-4607-9364-2787447f7680';
function gateway(identityStatus=200,user={id:actor,email:'admin@example.test',app_metadata:{role:'admin'}}){
 const calls=[];let handler;
 vm.runInNewContext(code,{Deno:{env:{get:k=>k==='SUPABASE_URL'?'https://vpjxdsprfcpqclnhbeoh.supabase.co':'server-only-test-secret'},serve:f=>{handler=f}},Request,Response,AbortSignal,Uint8Array,atob,fetch:async(url,init)=>{calls.push({url,init});return new Response(JSON.stringify(url.includes('/auth/v1/user')?user:7),{status:url.includes('/auth/v1/user')?identityStatus:200,headers:{'Content-Type':'application/json'}})}});
 return {calls,handler};
}
const request=(body,token='test.token.signature')=>new Request('https://preview.example.test',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});
test('gateway requires production-verified original administrator before any QA operation',async()=>{
 const noToken=gateway();assert.equal((await noToken.handler(new Request('https://preview.test',{method:'POST'}))).status,401);assert.equal(noToken.calls.length,0);
 const invalid=gateway(401);assert.equal((await invalid.handler(request({kind:'rpc',name:'admin_get_products'}))).status,401);assert.equal(invalid.calls.length,1);
 const wrong=gateway(200,{id:'another-user',app_metadata:{role:'admin'}});assert.equal((await wrong.handler(request({kind:'rpc',name:'admin_get_products'}))).status,403);assert.equal(wrong.calls.length,1);
 const employee=gateway(200,{id:actor,app_metadata:{role:'employee'}});assert.equal((await employee.handler(request({kind:'rpc',name:'admin_get_products'}))).status,403);
});
test('successful operation only reads identity from production and sends database work to QA',async()=>{
 const g=gateway();const res=await g.handler(request({kind:'rpc',name:'admin_products_count',payload:{args:{}}}));assert.equal(res.status,200);
 assert.equal(g.calls.length,2);assert.equal(g.calls[0].url,'https://eewjjzgwoaxhojnjvzgq.supabase.co/auth/v1/user');assert.equal(g.calls[0].init.method,'GET');
 assert.equal(g.calls[1].url,'https://vpjxdsprfcpqclnhbeoh.supabase.co/rest/v1/rpc/supplier_preview_original_admin_bridge');assert.equal(g.calls[1].init.method,'POST');
 const body=JSON.parse(g.calls[1].init.body);assert.equal(body.p_actor,actor);assert.equal(body.p_name,'admin_products_count');assert.ok(!JSON.stringify(await res.json()).includes('server-only-test-secret'));
});
test('identity verification needs no QA account and no password copy',async()=>{
 const g=gateway();const res=await g.handler(request({kind:'identity'}));const body=await res.json();assert.equal(body.data.id,actor);assert.equal(g.calls.length,1);assert.ok(g.calls.every(c=>!c.url.includes('/auth/v1/admin')));
});
