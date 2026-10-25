import test from 'node:test';
import assert from 'node:assert/strict';
import {screenBilingualReviewedPairs} from '../src/clinicalBilingualScreening.js';
const source={reviewer_id:'synthetic-reviewer',reviewed_at:'2026-10-25',source_reference_id:'synthetic-label',source_version:'test',source_document_id:'synthetic-document'};
const alias=(alias,language,id)=>({...source,alias,language,canonical_ingredient_id:id,status:'approved'});
const mapping=(product_id,ingredient_id)=>({...source,product_id,ingredient_id,status:'approved',composition_verified:true});
const product=(id,ingredient,ids)=>({id,active_ingredient:ingredient,verified_composition:{...source,status:'approved',ingredient_ids:ids}});
const rule={...source,id:'synthetic-interaction',ingredient_a_id:'ing-a',ingredient_b_id:'ing-b',severity:'major',mechanism:'Synthetic mechanism',recommendation:'Synthetic recommendation',reference_id:'synthetic-reference',license_status:'verified',license_reference:'synthetic-test-license',status:'approved',active:true};
test('reviewed Arabic and English aliases can match a synthetic interaction rule',()=>{
 const result=screenBilingualReviewedPairs([product('ar','مادة ا',['ing-a']),product('en','Ingredient B',['ing-b'])],
  [alias('مادة ا','ar','ing-a'),alias('Ingredient B','en','ing-b')],[mapping('ar','ing-a'),mapping('en','ing-b')],[rule]);
 assert.equal(result.findings.length,1);
 assert.equal(result.findings[0].rule_id,'synthetic-interaction');
 assert.equal(result.safeToCombine,null);
 assert.equal(result.productionEnabled,false);
});
test('partially mapped combination is unresolved and cannot produce clinical finding',()=>{
 const result=screenBilingualReviewedPairs([product('combo','',['ing-a','ing-c']),product('en','Ingredient B',['ing-b'])],
 [alias('Ingredient B','en','ing-b')],[mapping('combo','ing-a'),mapping('en','ing-b')],[rule]);
 assert.equal(result.findings.length,0);
 assert.equal(result.unresolved.some(x=>x.productId==='combo'),true);
});
test('unknown Arabic alias fails closed despite otherwise approved composition',()=>{
 const result=screenBilingualReviewedPairs([product('ar','اسم غير موثق',['ing-a']),product('en','Ingredient B',['ing-b'])],
 [alias('Ingredient B','en','ing-b')],[mapping('ar','ing-a'),mapping('en','ing-b')],[rule]);
 assert.equal(result.findings.length,0);
 assert.equal(result.status,'incomplete');
});

test('fully reviewed bilingual combination can be screened against synthetic rules',()=>{
 const combo=product('combo','',['ing-a','ing-c']);
 combo.verified_composition.reviewed_ingredient_aliases=['مادة ا','Ingredient C'];
 const result=screenBilingualReviewedPairs([combo,product('other','Ingredient B',['ing-b'])],
  [alias('مادة ا','ar','ing-a'),alias('Ingredient C','en','ing-c'),alias('Ingredient B','en','ing-b')],
  [mapping('combo','ing-a'),mapping('combo','ing-c'),mapping('other','ing-b')],[rule]);
 assert.equal(result.findings.length,1);
 assert.equal(result.unresolved.length,0);
});
test('combination with missing reviewed alias cannot be screened',()=>{
 const combo=product('combo','',['ing-a','ing-c']);
 combo.verified_composition.reviewed_ingredient_aliases=['مادة ا'];
 const result=screenBilingualReviewedPairs([combo,product('other','Ingredient B',['ing-b'])],
  [alias('مادة ا','ar','ing-a'),alias('Ingredient B','en','ing-b')],
  [mapping('combo','ing-a'),mapping('combo','ing-c'),mapping('other','ing-b')],[rule]);
 assert.equal(result.findings.length,0);
 assert.equal(result.unresolved.some(x=>x.reason==='combination_aliases_not_fully_verified'),true);
});
