import test from 'node:test';
import assert from 'node:assert/strict';
import {buildClinicalReviewQueue} from '../src/clinicalCatalogReviewQueue.js';
import {buildIngredientAliasCandidates} from '../src/clinicalAliasCandidates.js';
import {parseIngredientField} from '../src/clinicalPreviewEngine.js';
// De-identified ingredient-field patterns observed in a read-only sample of the live catalog.
// These are test fixtures, not verified ingredient identities or clinical assertions.
const cases=[
 ['nystatin 100,000i.u.','review'],
 ['carvedilol','parsed'],
 ['كلوبيتازول','parsed'],
 ['sulfamethoxazole + trimethoprim','parsed'],
 ['betahistine 8mg / tab','review'],
 ['cetrimide + chlorhexidine','parsed'],
 ['aspirin + caffeine + vitC','parsed'],
 ['diclofenacSodium','parsed'],
 ['ephedrine + loratadine','parsed']
];
test('live catalog ingredient patterns remain conservatively parsed',()=>{
 for(const [ingredient,expected] of cases){
  assert.equal(parseIngredientField(ingredient).status,expected,ingredient);
 }
});
test('dose-bearing ingredients are queued for review rather than auto-normalized',()=>{
 const rows=buildClinicalReviewQueue([{id:1,name:'Sample A',active_ingredient:'nystatin 100,000i.u.',strength:'',dosage_form:'susp'},{id:2,name:'Sample B',active_ingredient:'betahistine 8mg / tab',strength:'',dosage_form:'tablet'}]);
 assert.ok(rows.every(x=>x.priority===2&&x.clinical_approved===false));
});
test('realistic Arabic and English names remain separate candidates',()=>{
 const rows=buildIngredientAliasCandidates([{id:1,name:'Sample A',active_ingredient:'كلوبيتازول'},{id:2,name:'Sample B',active_ingredient:'clobetasol'}]);
 assert.equal(rows.length,2);
 assert.ok(rows.every(x=>x.canonical_ingredient_id===null&&!x.clinical_approved));
});
