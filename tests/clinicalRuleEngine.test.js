import test from 'node:test';
import assert from 'node:assert/strict';
import {validateClinicalRule,validateIngredientMapping,evaluateReviewedClinicalRules,clinicalReviewReadiness,clinicalRuleReleaseReady} from '../src/clinicalRuleEngine.js';
const rule={id:'test-1',ingredient_a_id:'ing-a',ingredient_b_id:'ing-b',severity:'major',mechanism:'Synthetic test mechanism',recommendation:'Synthetic test recommendation',reference_id:'ref-test',source_document_id:'synthetic-reference',source_version:'test-1',reviewed_at:'2026-10-25',reviewer_id:'reviewer-test',license_status:'verified',license_reference:'synthetic-test-license',status:'approved',active:true};
const mapped=(id,ingredient)=>({product_id:id,ingredient_id:ingredient,status:'approved',reviewer_id:'reviewer-test',reviewed_at:'2026-10-25',composition_verified:true,source_reference_id:'label-test',source_document_id:'synthetic-label',source_version:'test-1'});
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
 assert.equal(result.status,'limited_approved_rule_screening');
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

test('mapping requires evidence and approval',()=>{
 assert.equal(validateIngredientMapping(mapped('p1','ing-a')).valid,true);
 assert.equal(validateIngredientMapping({...mapped('p1','ing-a'),source_reference_id:null}).valid,false);
});

test('empty clinical evidence cannot be ready',()=>{
 const state=clinicalReviewReadiness([],[]);
 assert.equal(state.clinicallyReady,false);
 assert.equal(state.rulesApproved,0);
});
test('unreviewed rules and mappings are reported separately',()=>{
 const state=clinicalReviewReadiness([{...mapped('p1','ing-a'),status:'pending'}],[{...rule,status:'draft'}]);
 assert.equal(state.mappingProblems.length,1);
 assert.equal(state.ruleProblems.length,1);
 assert.equal(state.clinicallyReady,false);
});

test('source locator is mandatory',()=>{
 assert.equal(validateClinicalRule({...rule,source_document_id:null}).valid,false);
 assert.equal(validateIngredientMapping({...mapped('p1','ing-a'),source_document_id:null}).valid,false);
});
test('approved metadata does not alone authorize clinical release',()=>{
 const state=clinicalReviewReadiness([mapped('p1','ing-a')],[rule]);
 assert.equal(state.evidenceRecordsValid,true);
 assert.equal(state.clinicallyReady,false);
});

test('unlicensed synthetic rule cannot pass the clinical release gate',()=>{
 const unlicensed={...rule,license_status:'unverified',license_reference:null};
 assert.equal(clinicalRuleReleaseReady(unlicensed),false);
 assert.equal(clinicalRuleReleaseReady(rule),true);
 // Research-only evaluation also refuses unlicensed rules.
 const result=evaluateReviewedClinicalRules([{id:'p1'},{id:'p2'}],[mapped('p1','ing-a'),mapped('p2','ing-b')],[unlicensed]);
 assert.equal(result.findings.length,0);
 assert.equal(result.approvedRuleCount,0);
 assert.equal(clinicalReviewReadiness([mapped('p1','ing-a')],[unlicensed]).clinicallyReady,false);
});

test('readiness reports unlicensed evidence as incomplete even with approved structural metadata',()=>{
 const state=clinicalReviewReadiness([mapped('p1','ing-a')],[{...rule,license_status:'unknown'}]);
 assert.equal(state.rulesApproved,0);assert.equal(state.evidenceRecordsValid,false);
 assert.equal(state.ruleProblems[0].problems.includes('missing verified license metadata'),true);
});
test('malformed input containers and mapping rows never crash the prototype',()=>{
 assert.equal(evaluateReviewedClinicalRules({},null,{}).findings.length,0);
 assert.equal(evaluateReviewedClinicalRules([{id:'p'}],[null,{}],[null]).status,'incomplete');
});

test('both engine paths quarantine reused rule IDs and conflicting severity for the same pair',()=>{
 const products=[{id:'p1'},{id:'p2'}],mappings=[mapped('p1','ing-a'),mapped('p2','ing-b')];
 for(const rules of [[rule,{...rule,ingredient_a_id:'ing-c'}],[rule,{...rule,id:'different-id',severity:'minor'}]]){
  const result=evaluateReviewedClinicalRules(products,mappings,rules);
  assert.equal(result.status,'incomplete');assert.equal(result.findings.length,0);
  assert.equal(result.productionEnabled,false);assert.equal(result.safeToCombine,null);
 }
});
test('basic engine does not silently deduplicate conflicting product or mapping identities',()=>{
 const mappings=[mapped('p1','ing-a'),mapped('p2','ing-b')];
 const duplicateProduct=evaluateReviewedClinicalRules([{id:'p1'},{id:'p1'},{id:'p2'}],mappings,[rule]);
 assert.equal(duplicateProduct.findings.length,0);assert.equal(duplicateProduct.status,'incomplete');
 const duplicateMapping=evaluateReviewedClinicalRules([{id:'p1'},{id:'p2'}],[...mappings,mapped('p1','ing-a')],[rule]);
 assert.equal(duplicateMapping.findings.length,0);assert.equal(duplicateMapping.status,'incomplete');
});

test('non-text clinical explanations cannot qualify a reviewed rule',()=>{
 assert.equal(validateClinicalRule({...rule,mechanism:{}}).valid,false);
 assert.equal(validateClinicalRule({...rule,recommendation:['synthetic']}).valid,false);
});
