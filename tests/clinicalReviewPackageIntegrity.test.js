import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectBilingualReviewPackage} from '../src/clinicalAliasReviewPackage.js';
import {validateBilingualAlias} from '../src/clinicalBilingualMapping.js';
const approved=(alias,id='ingredient-1')=>({alias,language:'en',canonical_ingredient_id:id,status:'approved',source_reference_id:'reference-1',source_version:'v1',source_url:'https://example.org/evidence',reviewer_id:'reviewer-1',reviewed_at:'2026-10-25'});
test('duplicate reviewed aliases are rejected rather than counted twice',()=>{
 const r=inspectBilingualReviewPackage([approved('sample'),approved('sample')],[{alias:'sample'}]);
 assert.equal(r.accepted.length,1);
 assert.equal(r.rejected.length,1);
 assert.equal(r.eligibleForProduction,false);
 assert.equal(r.clinicalRulesActivated,0);
});
test('unknown reviewed alias remains unrecognized',()=>{
 const r=inspectBilingualReviewPackage([approved('unknown')],[{alias:'known'}]);
 assert.equal(r.accepted.length,0);
 assert.equal(r.unrecognized.length,1);
});
test('missing source locator or pharmacist metadata blocks alias',()=>{
 assert.equal(validateBilingualAlias({...approved('sample'),source_url:'',source_document_id:''}).valid,false);
 assert.equal(validateBilingualAlias({...approved('sample'),reviewer_id:''}).valid,false);
});
