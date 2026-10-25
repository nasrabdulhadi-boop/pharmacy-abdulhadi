import test from 'node:test';
import assert from 'node:assert/strict';
import {auditClinicalCatalog,buildIngredientReviewQueue,prioritizeClinicalReview,summarizeIngredientReview} from '../src/clinicalPreviewEngine.js';
import {buildIngredientAliasCandidates} from '../src/clinicalAliasCandidates.js';
const rows=Array.from({length:18000},(_,i)=>({
 id:'catalog-'+i,name:'Synthetic medicine '+i,
 active_ingredient:i%11===0?'':i%7===0?'Test 5mg':i%3===0?'مادة تجريبية':'Test Ingredient',
 strength:i%5===0?'':'10 mg',dosage_form:i%13===0?'':'tablet'
}));
test('18k synthetic catalog audit preserves totals and deterministic results',()=>{
 const audit=auditClinicalCatalog(rows);
 assert.equal(audit.counts.total,18000);
 assert.equal(audit.counts.missingIngredient,rows.filter(x=>!x.active_ingredient).length);
 assert.equal(audit.counts.parseable+audit.counts.manualReview+audit.counts.missingIngredient,18000);
 assert.ok(audit.issues.length<=60);
 assert.deepEqual(auditClinicalCatalog(rows).counts,audit.counts);
});
test('18k synthetic catalog review queues stay bounded and unapproved',()=>{
 const queue=buildIngredientReviewQueue(rows);
 const review=prioritizeClinicalReview(rows);
 const summary=summarizeIngredientReview(rows);
 const candidates=buildIngredientAliasCandidates(rows);
 assert.equal(summary.products,18000);
 assert.equal(review.length,summary.needingReview);
 assert.ok(queue.every(x=>x.status==='unverified'));
 assert.ok(candidates.length>0);
 assert.ok(candidates.length<18000);
});
