import test from 'node:test';
import assert from 'node:assert/strict';
import {validateBilingualAlias} from '../src/clinicalBilingualMapping.js';
import {validReviewDate,validSourceUrl} from '../src/clinicalProvenance.js';
import {clinicalRuleReleaseReady,validateIngredientMapping} from '../src/clinicalRuleEngine.js';
const row={alias:'Synthetic',language:'en',canonical_ingredient_id:'test-a',status:'approved',reviewer_id:'synthetic',reviewed_at:'2026-10-25',source_reference_id:'ref',source_version:'1',source_document_id:'doc'};
test('whitespace, object values, impossible dates and unsafe locators cannot qualify alias metadata',()=>{
 for(const patch of [{reviewer_id:' '},{reviewed_at:'yesterday'},{reviewed_at:'2026-02-30'},{source_reference_id:' '},{source_version:{}},{canonical_ingredient_id:' test-a '},{source_document_id:' '},{source_url:'javascript:alert(1)'},{source_url:'https://user:password@example.org'},{alias:{}}]){
  assert.equal(validateBilingualAlias({...row,...patch}).valid,false,JSON.stringify(patch));
 }
 assert.equal(validateBilingualAlias(row).valid,true);
});
test('valid dated reviews accept calendar dates and explicit timezone timestamps',()=>{
 for(const date of ['2024-02-29','2026-10-25T13:45:00Z','2026-10-25T13:45:00+03:00'])assert.equal(validReviewDate(date),true,date);
 for(const date of ['2025-02-29','2026-13-01','2026-10-25T24:00:00Z','2026-10-25T13:45:00',''])assert.equal(validReviewDate(date),false,date);
 assert.equal(validSourceUrl('https://example.org/label?id=1'),true);
 assert.equal(validSourceUrl('file:///etc/passwd'),false);
});
test('whitespace cannot pass mapping evidence or rule licensing checks',()=>{
 assert.equal(validateIngredientMapping({...row,product_id:'p',ingredient_id:'a',composition_verified:true,source_reference_id:' '}).valid,false);
 const rule={id:'r',ingredient_a_id:'a',ingredient_b_id:'b',severity:'major',mechanism:'synthetic',recommendation:'synthetic',reference_id:'ref',source_version:'1',source_document_id:'doc',reviewer_id:'synthetic',reviewed_at:'2026-10-25',status:'approved',active:true,license_status:'verified',license_reference:{}};
 assert.equal(clinicalRuleReleaseReady(rule),false);
});
