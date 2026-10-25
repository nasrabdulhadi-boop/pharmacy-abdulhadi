import test from 'node:test';
import assert from 'node:assert/strict';
import {screenBilingualReviewedPairs} from '../src/clinicalBilingualScreening.js';
const provenance={reviewer_id:'synthetic',reviewed_at:'2026-10-25',source_reference_id:'synthetic',source_version:'1',source_document_id:'synthetic-doc'};
const alias=(alias,language,id)=>({...provenance,alias,language,canonical_ingredient_id:id,status:'approved'});
const mapping=(product_id,ingredient_id)=>({...provenance,product_id,ingredient_id,status:'approved',composition_verified:true});
const product=(id,ids,labels,active_ingredient='')=>({id,active_ingredient,verified_composition:{...provenance,status:'approved',ingredient_ids:ids,reviewed_ingredient_aliases:labels}});
const rule={...provenance,id:'synthetic-rule',ingredient_a_id:'a',ingredient_b_id:'b',severity:'major',mechanism:'synthetic',recommendation:'synthetic',reference_id:'synthetic',license_status:'verified',license_reference:'synthetic-test-license',status:'approved',active:true};
const other=product('other',['b'],[],'Ingredient B');
const aliases=[alias('مادة ا','ar','a'),alias('Ingredient C','en','c'),alias('Ingredient B','en','b')];
const mappings=[mapping('combo','a'),mapping('combo','c'),mapping('other','b')];
test('duplicate reviewed combination labels fail closed',()=>{
 const combo=product('combo',['a','c'],['مادة ا','مادة ا']);
 const r=screenBilingualReviewedPairs([combo,other],aliases,mappings,[rule]);
 assert.equal(r.findings.length,0);
 assert.equal(r.unresolved.some(x=>x.productId==='combo'),true);
 assert.equal(r.safeToCombine,null);
});
test('conflicting alias inside combination fails closed',()=>{
 const combo=product('combo',['a','c'],['مادة ا','Ingredient C']);
 const r=screenBilingualReviewedPairs([combo,other],[...aliases,alias('مادة ا','ar','other-id')],mappings,[rule]);
 assert.equal(r.findings.length,0);
 assert.equal(r.unresolved.some(x=>x.productId==='combo'),true);
});
test('combination with complete bilingual aliases remains research only',()=>{
 const combo=product('combo',['a','c'],['مادة ا','Ingredient C']);
 const r=screenBilingualReviewedPairs([combo,other],aliases,mappings,[rule]);
 assert.equal(r.findings.length,1);
 assert.equal(r.productionEnabled,false);
 assert.equal(r.safeToCombine,null);
 assert.equal(r.coverage,'not_exhaustive');
});
