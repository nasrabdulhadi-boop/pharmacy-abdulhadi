import test from 'node:test';
import assert from 'node:assert/strict';
import {loadPublicCatalog,PUBLIC_CATALOG_FIELDS} from '../src/publicCatalogAccess.js';
test('default catalog path preserves the exact legacy public field allowlist',async()=>{
 const calls=[];
 const chain={select(fields){calls.push(['select',fields]);return this},eq(...args){calls.push(['eq',...args]);return this},order(field){calls.push(['order',field]);return Promise.resolve({data:[{id:'legacy'}],error:null})}};
 const result=await loadPublicCatalog({from(table){calls.push(['from',table]);return chain},rpc(){assert.fail('hardened path must stay opt-in')}});
 assert.equal(result.data[0].id,'legacy');
 assert.deepEqual(calls,[['from','products'],['select',PUBLIC_CATALOG_FIELDS.join(',')],['eq','customer_visible',true],['order','name']]);
});
test('hardened loader paginates and removes unexpected internal fields defensively',async()=>{
 const calls=[];
 const client={from(){assert.fail('no fallback')},async rpc(name,args){calls.push([name,args]);return {data:args.p_offset===0?[{id:'a',name:'A',purchase_price:4},{id:'b',sale_price:9,sale_currency:'USD'}]:[],error:null}}};
 const result=await loadPublicCatalog(client,{hardened:true,pageSize:2});
 assert.equal(result.error,null);assert.equal(result.data.length,2);assert.equal(Object.hasOwn(result.data[0],'purchase_price'),false);
 assert.equal(result.data[1].sale_currency,'USD');assert.equal(calls[1][1].p_offset,2);
});
test('missing hardened RPC never falls back to the insecure legacy table',async()=>{
 const client={from(){assert.fail('fallback forbidden')},async rpc(){return {data:null,error:{code:'PGRST202'}}}};
 const result=await loadPublicCatalog(client,{hardened:true});
 assert.equal(result.data,null);assert.equal(result.error.code,'PGRST202');
});
test('malformed or repeating catalog pages fail without returning partial data',async()=>{
 for(const response of [null,[{id:'a'},{id:'a'}],[{}]]){
  const result=await loadPublicCatalog({async rpc(){return {data:response,error:null}}},{hardened:true,pageSize:2});
  assert.equal(result.data,null);assert.ok(result.error);
 }
});
test('exact catalog cap is checked with a final probe and excess rows are not truncated silently',async()=>{
 for(const excess of [false,true]){
  const client={async rpc(_,{p_offset}){return {data:p_offset===0?[{id:'a'},{id:'b'}]:excess?[{id:'c'}]:[],error:null}}};
  const result=await loadPublicCatalog(client,{hardened:true,pageSize:2,maxRows:2});
  assert.equal(Boolean(result.error),excess);assert.equal(result.data?.length??0,excess?0:2);
 }
});
