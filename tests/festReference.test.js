import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {createHash} from 'node:crypto';
import {festManifest as manifest,validateFestIndex,searchFestMembers,festIdentityMatches,findFestRecords,isFestStatusCurrent,safeFestUrl,fetchFestFile,loadFestResults} from '../src/festReference.js';
import {inspectFestSource} from '../src/festSourceStatus.js';
const base=new URL('../public/clinical/fest/',import.meta.url);
const read=name=>fs.readFileSync(new URL(name,base));
const index=JSON.parse(gunzipSync(read('index.json.gz')));
const fileFetch=async url=>new Response(read(url.split('/').pop()));
test('FEST complete snapshot, all compressed shards and provenance are consistent',()=>{
 assert.equal(validateFestIndex(index),index);
 let total=0,conditions=0,refs=0,audiences=0;const seen=new Set();
 for(const [name,meta] of Object.entries(manifest.files)){
  const bytes=read(name);assert.equal(bytes.length,meta.bytes);assert.equal(createHash('sha256').update(bytes).digest('hex'),meta.sha256);
  if(!name.startsWith('records-'))continue;
  const data=JSON.parse(gunzipSync(bytes));assert.equal(data.snapshot,index.snapshot);
  for(const r of data.records){assert.ok(!seen.has(r.id));seen.add(r.id);total++;if(r.situation)conditions++;refs+=r.references.length;assert.ok(r.consequence);assert.equal(r.groups.length,2);assert.ok(r.evidence);audiences+=r.audiences.length}
 }
 assert.equal(audiences,36319);assert.equal(total,11050);assert.equal(conditions,1322);assert.equal(refs,20623);assert.equal(index.unassessed.length,456);
});
test('FEST rejects incomplete, invalid and mixed-version indices',()=>{
 for(const mutate of [i=>i.records.pop(),i=>i.snapshot='old',i=>i.records[0].groups[0]=[999999],i=>i.records[1].id=i.records[0].id]){const i=structuredClone(index);mutate(i);assert.throws(()=>validateFestIndex(i))}
});
test('Source English search is discovery only and no unselected text is screened',()=>{
 assert.ok(searchFestMembers(index,'clopidogrel').some(m=>m.id==='atc:B01AC04'));
 assert.ok(searchFestMembers(index,'B01AC04').some(m=>m.id==='atc:B01AC04'));
 assert.equal(searchFestMembers(index,'كلام غير معروف').length,0);
 assert.throws(()=>findFestRecords(index,['Clopidogrel','Omeprazole']));
});
test('ATC hierarchy matches parents on valid levels and never substring or salt equivalents',()=>{
 for(const p of ['atc:B','atc:B01','atc:B01A','atc:B01AC','atc:B01AC04'])assert.ok(festIdentityMatches('atc:B01AC04',p));
 for(const p of ['atc:B0','atc:B01AC0','atc:B01AB','atc:B01AC40','substance:B01AC04'])assert.equal(festIdentityMatches('atc:B01AC04',p),false);
 assert.equal(festIdentityMatches('substance:salt-a','substance:salt-b'),false);
});
test('Selection limits, unknown identities and duplicates fail closed',()=>{
 for(const ids of [[],['atc:B01AC04'],['atc:B01AC04','atc:B01AC04'],['atc:B01AC04','atc:NOTREAL'],['atc:B01','atc:B01AC04'],Array(9).fill('a')])assert.throws(()=>findFestRecords(index,ids));
});
test('Three actual snapshot pairs retain provider IDs, category and complete clinical context',async()=>{
 const cases=[['atc:B01AC04','atc:A02BC01','ID_C78A4B22-5F79-4516-9D35-9F8A01264DFA'],['atc:C10AA01','atc:J01FA09','ID_5C9536F2-D3D6-4E7A-8030-9F8A012690D5'],['atc:G04BE03','atc:C01DA02','ID_0823AF95-C213-4A48-AE0F-9F8A01267E56']];
 for(const [a,b,id] of cases){const r=await loadFestResults(index,[a,b],{fetcher:fileFetch});assert.equal(r.safeToCombine,null);assert.equal(r.records[0].id,id);assert.equal(r.records[0].relevance.code,'1');assert.ok(r.records[0].consequence);assert.ok(r.records[0].management);assert.ok(r.records[0].references.length)}
});
test('Multi-material screening reports all pairs and reverse-order lookup agrees',()=>{
 const ids=['atc:B01AC04','atc:A02BC01','atc:C10AA01'];const a=findFestRecords(index,ids),b=findFestRecords(index,[...ids].reverse());assert.equal(a.pairs.length,3);assert.deepEqual(a.records.map(r=>r.id),b.records.map(r=>r.id));assert.equal(a.safeToCombine,null);
});
test('Source not-assessed status is retained even alongside a known interaction',()=>{
 const r=findFestRecords(index,['atc:C10AA01','atc:J01FA09']);assert.equal(r.pairs[0].status,'not_assessed');assert.ok(r.records.length);assert.equal(r.safeToCombine,null);
});
test('An absent source pair remains inconclusive',()=>{
 let empty;
 for(const m of index.members.filter(m=>m.selectable).slice(0,100)){if(m.id==='atc:B01AC04')continue;const r=findFestRecords(index,['atc:B01AC04',m.id]);if(!r.records.length){empty=r;break}}
 assert.ok(empty);assert.ok(['not_assessed','no_source_record'].includes(empty.pairs[0].status));assert.equal(empty.safeToCombine,null);
});
test('A shard failure or hash mismatch cannot return a partial negative result',async()=>{
 await assert.rejects(loadFestResults(index,['atc:B01AC04','atc:A02BC01'],{fetcher:async()=>new Response('',{status:503})}),/fest_download/);
 const corrupt=read('index.json.gz');corrupt[20]^=1;
 await assert.rejects(fetchFestFile('index.json.gz',{fetcher:async()=>new Response(corrupt)}),/fest_invalid_data/);
});
test('Freshness rejects stale, unavailable, future, expired and wrong snapshots',()=>{
 const now=Date.now(),s={state:'current',snapshot:manifest.snapshot,checkedAt:new Date(now).toISOString()};assert.ok(isFestStatusCurrent(s,now));
 for(const patch of [{state:'stale'},{state:'unavailable'},{snapshot:'other'},{checkedAt:'bad'},{checkedAt:new Date(now-300001).toISOString()},{checkedAt:new Date(now+60000).toISOString()}])assert.equal(isFestStatusCurrent({...s,...patch},now),false);
});
test('Reference links reject script/data URLs and credentials',()=>{
 for(const url of ['javascript:alert(1)','data:text/html,xx','https://user:password@example.com','bad'])assert.equal(safeFestUrl(url),null);
 assert.equal(safeFestUrl('https://pubmed.ncbi.nlm.nih.gov/123/'),'https://pubmed.ncbi.nlm.nih.gov/123/');
});
test('Live-source verifier requests only the fixed public URL and detects changed bytes',async()=>{
 let requested;const r=await inspectFestSource({fetcher:async(url,options)=>{requested=url;assert.equal(options.redirect,'error');return new Response('changed archive')}});
 assert.equal(requested,manifest.sourceUrl);assert.equal(r.state,'stale');assert.equal(r.snapshot,manifest.snapshot);
});
test('Live-source verifier fails on unavailable, empty and interrupted downloads',async()=>{
 for(const fetcher of [async()=>new Response('',{status:503}),async()=>new Response(''),async()=>{throw new Error('offline')}])await assert.rejects(inspectFestSource({fetcher}));
});
