import test from 'node:test';
import assert from 'node:assert/strict';
import {screenBilingualReviewedPairs} from '../src/clinicalBilingualScreening.js';
const src={reviewer_id:'synthetic',reviewed_at:'2026-10-25',source_reference_id:'synthetic',source_version:'1',source_document_id:'synthetic'};
const alias=(name,id)=>({...src,alias:name,language:'en',canonical_ingredient_id:id,status:'approved'});
const mapping=(product_id,ingredient_id)=>({...src,product_id,ingredient_id,status:'approved',composition_verified:true});
const product=(id,label,ingredient)=>({id,active_ingredient:label,verified_composition:{...src,status:'approved',ingredient_ids:[ingredient]}});
const rule=(id,severity='major',a='a',b='b')=>({...src,id,ingredient_a_id:a,ingredient_b_id:b,severity,mechanism:'synthetic',recommendation:'synthetic',reference_id:'synthetic',license_status:'verified',license_reference:'synthetic-test-license',status:'approved',active:true});
const run=rules=>screenBilingualReviewedPairs([product('one','Ingredient A','a'),product('two','Ingredient B','b')],[alias('Ingredient A','a'),alias('Ingredient B','b')],[mapping('one','a'),mapping('two','b')],rules);
test('identical duplicate rules produce one finding',()=>{
 const r=run([rule('one'),rule('two')]);
 assert.equal(r.findings.length,1);assert.equal(r.ruleConflicts.length,0);
 assert.equal(r.safeToCombine,null);
});
test('reversed ingredient order is deduplicated',()=>{
 const r=run([rule('one'),rule('two','major','b','a')]);
 assert.equal(r.findings.length,1);assert.equal(r.ruleConflicts.length,0);
});
test('contradictory severities quarantine pair rather than selecting a winner',()=>{
 const r=run([rule('one','major'),rule('two','minor')]);
 assert.equal(r.findings.length,0);assert.equal(r.ruleConflicts.length,1);
 assert.equal(r.status,'incomplete');assert.equal(r.productionEnabled,false);
});
