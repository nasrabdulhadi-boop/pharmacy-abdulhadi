import test from 'node:test';
import assert from 'node:assert/strict';
import {validateClinicalRule,evaluateReviewedClinicalRules} from '../src/clinicalRuleEngine.js';
const rule={id:'test-1',ingredient_a_id:'ing-a',ingredient_b_id:'ing-b',severity:'major',mechanism:'Synthetic test mechanism',recommendation:'Synthetic test recommendation',reference_id:'ref-test',source_version:'test-1',reviewed_at:'2026-10-25',reviewer_id:'reviewer-test',status:'approved',active:true};
const mapped=(id,ingredient)=>({product_id:id,ingredient_id:ingredient,status:'approved',reviewer_id:'reviewer-test',reviewed_at:'2026-10-25',composition_verified:true});
test('rejects rules lacking approval, reference or reviewer',()=>{
 assert.equal(validateClinicalRule({...rule,status:'draft'}).valid,false);
 assert.equal(validateClinicalRule({...rule,reference_id:null}).valid,false);
 assert.equal(validateClinicalRule({...rule,reviewer_id:null}).valid,false);
 assert.equal(validateClinicalRule({...rule,active:false}).valid,false);
});
test('no real rules yields explicit unavailable status',()=>{
 const result=evaluateReviewedClinicalRules([{id:'p1'},{id:'p2'}],[mapped('p1','ing-a'),mapped('p2','ing-b')],[]);
 assert.equal(result.status,'no_approved_rules');
 assert.equal(result.findings.length,0);
});
test('synthetic approved rule matches both directions in test only',()=>{
 const result=evaluateReviewedClinicalRules([{id:'p1'},{id:'p2'}],[mapped('p1','ing-b'),mapped('p2','ing-a')],[rule]);
 assert.equal(result.status,'rules_evaluated');
 assert.equal(result.findings.length,1);
 assert.equal(result.findings[0].rule_id,'test-1');
});
test('unverified combination mapping fails closed',()=>{
 const result=evaluateReviewedClinicalRules([{id:'p1'},{id:'p2'}],[{...mapped('p1','ing-a'),composition_verified:false},mapped('p2','ing-b')],[rule]);
 assert.equal(result.status,'incomplete');
 assert.deepEqual(result.unmappedProductIds,['p1']);
 assert.equal(result.findings.length,0);
});
test('draft and inactive rules never generate findings',()=>{
 const result=evaluateReviewedClinicalRules([{id:'p1'},{id:'p2'}],[mapped('p1','ing-a'),mapped('p2','ing-b')],[{...rule,status:'draft'},{...rule,id:'test-2',active:false}]);
 assert.equal(result.status,'no_approved_rules');
 assert.equal(result.findings.length,0);
});
