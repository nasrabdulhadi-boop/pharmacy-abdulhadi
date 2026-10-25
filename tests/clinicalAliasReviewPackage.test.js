import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectBilingualReviewPackage,exportBilingualReviewTemplateCsv} from '../src/clinicalAliasReviewPackage.js';
const candidate=alias=>({alias,language:'ar'});
const approved=(alias,id)=>({alias,language:'ar',canonical_ingredient_id:id,status:'approved',reviewer_id:'synthetic-reviewer',reviewed_at:'2026-10-25',source_reference_id:'synthetic-source',source_version:'test',source_document_id:'synthetic-doc'});
test('review template leaves approval and source fields empty',()=>{
 const csv=exportBilingualReviewTemplateCsv([candidate('باراسيتامول')]);
 assert.ok(csv.includes('باراسيتامول'));
 assert.ok(csv.includes('candidate'));
 assert.ok(!csv.includes('approved'));
});
test('unreviewed and unknown aliases are not accepted',()=>{
 const result=inspectBilingualReviewPackage([{...approved('باراسيتامول','a'),status:'candidate'},approved('غير معروف','a')],[candidate('باراسيتامول')]);
 assert.equal(result.accepted.length,0);
 assert.equal(result.rejected.length,1);
 assert.equal(result.unrecognized.length,1);
});
test('conflicting canonical mappings are quarantined',()=>{
 const result=inspectBilingualReviewPackage([approved('باراسيتامول','a'),approved('باراسيتامول','b')],[candidate('باراسيتامول')]);
 assert.equal(result.conflicts.length,1);
 assert.equal(result.accepted.length,0);
 assert.equal(result.clinicalRulesActivated,0);
 assert.equal(result.eligibleForProduction,false);
});
