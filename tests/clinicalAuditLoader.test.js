import test from 'node:test';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {CLINICAL_AUDIT_FIELDS,loadClinicalAuditCatalog,clinicalAuditErrorMessage} from '../src/clinicalAuditLoader.js';
const row=id=>({id,name:'Synthetic '+id,active_ingredient:'synthetic',active:true});
const code=value=>error=>error.code===value;

test('audit loads bounded consecutive pages and retains only review fields',async()=>{
 const calls=[],progress=[];
 const data=[{...row('a'),purchase_price:99,sale_price:100},row('b'),row('c')];
 const result=await loadClinicalAuditCatalog({pageSize:2,onProgress:n=>progress.push(n),fetchPage:async({limit,offset})=>{
  calls.push([limit,offset]);return {data:data.slice(offset,offset+limit)};
 }});
 assert.deepEqual(calls,[[2,0],[2,2],[2,3]]);assert.deepEqual(progress,[2,3]);
 assert.equal(result.complete,true);assert.equal(result.rows.length,3);
 assert.equal(Object.hasOwn(result.rows[0],'purchase_price'),false);
 assert.equal(Object.hasOwn(result.rows[0],'sale_price'),false);
 assert.equal(data[0].purchase_price,99);
});

test('audit exact cap needs an empty sentinel and never silently truncates',async()=>{
 for(const total of [4,5]){
  const calls=[],data=Array.from({length:total},(_,i)=>row('id'+i));
  const r=await loadClinicalAuditCatalog({pageSize:3,maxRows:4,fetchPage:async({limit,offset})=>{
   calls.push([limit,offset]);return {data:data.slice(offset,offset+limit)};
  }});
  assert.deepEqual(calls,[[3,0],[1,3],[1,4]]);
  assert.equal(r.rows.length,4);assert.equal(r.complete,total===4);
 }
});

test('short server-clamped pages cannot masquerade as a complete catalog',async()=>{
 const data=[row('a'),row('b'),row('c')],offsets=[];
 const result=await loadClinicalAuditCatalog({fetchPage:async({offset})=>{
  offsets.push(offset);return {data:data.slice(offset,offset+1)};
 }});
 assert.deepEqual(offsets,[0,1,2,3]);assert.equal(result.rows.length,3);assert.equal(result.complete,true);
});

test('audit refuses repeated product IDs within or across pages',async()=>{
 for(const pages of [[[row('a'),row('a')]],[[row('a'),row('b')],[row('a')]]]){
  let call=0;
  await assert.rejects(loadClinicalAuditCatalog({pageSize:2,fetchPage:async()=>({data:pages[call++]})}),code('audit_invalid_page'));
 }
});

test('audit refuses malformed fields, hidden protocol failures and oversized pages',async()=>{
 const invalid=[null,{},[null],[[]],[{name:'No ID'}],[{...row('a'),id:' '}],[{...row('a'),active:false}],[{...row('a'),active:'true'}],[{...row('a'),name:{text:'unexpected'}}],[row('a'),row('b'),row('c')]];
 for(const data of invalid)await assert.rejects(loadClinicalAuditCatalog({pageSize:2,fetchPage:async()=>({data})}),code('audit_invalid_page'));
});

test('audit discards partial results when a later page fails without disclosing server error details',async()=>{
 const progress=[];let call=0;
 await assert.rejects(loadClinicalAuditCatalog({pageSize:1,onProgress:n=>progress.push(n),fetchPage:async()=>++call===1?{data:[row('a')]}:{error:{message:'private schema diagnostic'}}}),code('audit_request_failed'));
 assert.deepEqual(progress,[1]);
 assert.equal(clinicalAuditErrorMessage({message:'private schema diagnostic'}).includes('private'),false);
});

test('audit validates the sentinel instead of treating a repeated cap page as complete',async()=>{
 await assert.rejects(loadClinicalAuditCatalog({maxRows:1,fetchPage:async()=>({data:[row('a')]})}),code('audit_invalid_page'));
});

test('audit timeout rejects even a transport that ignores abort and aborts its signal',async()=>{
 let requestSignal;
 await assert.rejects(loadClinicalAuditCatalog({timeoutMs:10,fetchPage:({signal})=>{
  requestSignal=signal;return new Promise(()=>{});
 }}),code('audit_timeout'));
 assert.equal(requestSignal.aborted,true);
});

test('audit cancellation aborts an in-flight request and issues no later pages',async()=>{
 const controller=new AbortController();let requestSignal,calls=0,started;
 const ready=new Promise(resolve=>{started=resolve});
 const pending=loadClinicalAuditCatalog({signal:controller.signal,fetchPage:({signal})=>{
  calls++;requestSignal=signal;started();return new Promise(()=>{});
 }});
 await ready;controller.abort();
 await assert.rejects(pending,code('audit_cancelled'));
 assert.equal(requestSignal.aborted,true);assert.equal(calls,1);
});

test('audit cancelled before start never calls the transport',async()=>{
 const controller=new AbortController();controller.abort();let calls=0;
 await assert.rejects(loadClinicalAuditCatalog({signal:controller.signal,fetchPage:async()=>{calls++;return {data:[]}}}),code('audit_cancelled'));
 assert.equal(calls,0);
});

test('audit limits reject invalid configuration before any requests',async()=>{
 for(const opts of [{pageSize:0},{pageSize:501},{maxRows:20001},{timeoutMs:0},{maxRows:1.2}]){
  let calls=0;await assert.rejects(loadClinicalAuditCatalog({...opts,fetchPage:async()=>{calls++;return {data:[]}}}),code('audit_invalid_options'));
  assert.equal(calls,0);
 }
});

test('audit handles the full synthetic 20k boundary without retaining the sentinel',async()=>{
 let calls=0;
 const result=await loadClinicalAuditCatalog({fetchPage:async({limit,offset})=>{
  calls++;return {data:offset===20000?[]:Array.from({length:limit},(_,i)=>row(String(offset+i)))};
 }});
 assert.equal(calls,41);assert.equal(result.complete,true);assert.equal(result.rows.length,20000);
});

test('real Supabase client composes RPC projection, paging and abort signal with an isolated transport',async()=>{
 const requests=[];
 const client=createClient('https://clinical-qa.invalid','synthetic-public-key',{
  auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},
  global:{fetch:async(url,options)=>{
   requests.push({url:String(url),options});
   return new Response(JSON.stringify(requests.length===1?[row('synthetic-only')]:[]),{status:200,headers:{'Content-Type':'application/json'}});
  }}
 });
 const result=await loadClinicalAuditCatalog({fetchPage:({limit,offset,signal})=>client.rpc('admin_get_products_page',{p_limit:limit,p_offset:offset}).select(CLINICAL_AUDIT_FIELDS.join(',')).abortSignal(signal)});
 assert.equal(result.complete,true);assert.equal(result.rows.length,1);assert.equal(requests.length,2);
 const request=requests[0];
 assert.equal(new URL(request.url).searchParams.get('select'),CLINICAL_AUDIT_FIELDS.join(','));
 assert.deepEqual(JSON.parse(request.options.body),{p_limit:500,p_offset:0});
 assert.deepEqual(JSON.parse(requests[1].options.body),{p_limit:500,p_offset:1});
 assert.equal(request.options.signal instanceof AbortSignal,true);
 assert.equal(request.url.includes('purchase_price'),false);
});
