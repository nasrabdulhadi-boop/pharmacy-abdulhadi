import test from 'node:test';
import assert from 'node:assert/strict';
import {screenBilingualReviewedPairs} from '../src/clinicalBilingualScreening.js';
const src={reviewer_id:'synthetic',reviewed_at:'2026-10-25',source_reference_id:'synthetic',source_version:'1',source_document_id:'synthetic-doc'};
const alias=(alias,language,id)=>({...src,alias,language,canonical_ingredient_id:id,status:'approved'});
const mapping=(product_id,ingredient_id)=>({...src,product_id,ingredient_id,status:'approved',composition_verified:true});
const rule={...src,id:'synthetic',ingredient_a_id:'a',ingredient_b_id:'b',severity:'major',mechanism:'synthetic',recommendation:'synthetic',reference_id:'synthetic',license_status:'verified',license_reference:'synthetic-test-license',status:'approved',active:true};
const prod=(id,label,ids)=>({id,active_ingredient:label,verified_composition:{...src,status:'approved',ingredient_ids:ids}});
const aliases=[alias('مادة ا','ar','a'),alias('Ingredient B','en','b')];
test('missing composition manifest never yields a reassuring conclusion',()=>{
 const r=screenBilingualReviewedPairs([{id:'a',active_ingredient:'مادة ا'},prod('b','Ingredient B',['b'])],aliases,[mapping('a','a'),mapping('b','b')],[rule]);
 assert.equal(r.status,'incomplete');assert.equal(r.findings.length,0);
 assert.equal(r.safeToCombine,null);assert.equal(r.productionEnabled,false);
 assert.ok(r.unresolved.some(x=>x.reason==='composition_not_fully_verified'));
});
test('unapproved manifest remains unresolved despite reviewed aliases and mappings',()=>{
 const a=prod('a','مادة ا',['a']);a.verified_composition.status='candidate';
 const r=screenBilingualReviewedPairs([a,prod('b','Ingredient B',['b'])],aliases,[mapping('a','a'),mapping('b','b')],[rule]);
 assert.equal(r.findings.length,0);assert.equal(r.status,'incomplete');
});
test('incomplete mapping cannot generate a synthetic interaction finding',()=>{
 const r=screenBilingualReviewedPairs([prod('a','مادة ا',['a']),prod('b','Ingredient B',['b'])],aliases,[mapping('b','b')],[rule]);
 assert.equal(r.findings.length,0);
 assert.ok(r.unresolved.some(x=>x.reason==='incomplete_ingredient_mappings'));
});
test('no reviewed rules never implies no interactions',()=>{
 const r=screenBilingualReviewedPairs([prod('a','مادة ا',['a']),prod('b','Ingredient B',['b'])],aliases,[mapping('a','a'),mapping('b','b')],[]);
 assert.equal(r.status,'no_approved_rules');assert.equal(r.findings.length,0);
 assert.equal(r.safeToCombine,null);assert.equal(r.coverage,'not_exhaustive');
});
