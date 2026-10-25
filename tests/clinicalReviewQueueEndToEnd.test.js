import test from 'node:test';
import assert from 'node:assert/strict';
import {buildClinicalReviewQueue,summarizeClinicalReviewQueue,exportClinicalReviewQueueCsv} from '../src/clinicalCatalogReviewQueue.js';
import {buildIngredientAliasCandidates,summarizeIngredientAliasCandidates,exportIngredientAliasCandidatesCsv} from '../src/clinicalAliasCandidates.js';
const products=[
 {id:1,name:'Missing',barcode:'1',active_ingredient:'',strength:'',dosage_form:''},
 {id:2,name:'Mixed',barcode:'2',active_ingredient:'Test مادة',strength:'5 mg',dosage_form:'tablet'},
 {id:3,name:'Arabic',barcode:'3',active_ingredient:'مادة',strength:'5 mg',dosage_form:'tablet'},
 {id:4,name:'Missing form',barcode:'4',active_ingredient:'Test Ingredient',strength:'5 mg',dosage_form:''},
 {id:5,name:'Complete',barcode:'5',active_ingredient:'Test Ingredient',strength:'5 mg',dosage_form:'tablet'}
];
test('all five catalog review priorities remain ordered and unapproved',()=>{
 const queue=buildClinicalReviewQueue(products);
 assert.deepEqual(queue.map(x=>x.priority),[1,2,3,4,5]);
 assert.ok(queue.every(x=>x.review_status==='pending'&&x.clinical_approved===false));
 const s=summarizeClinicalReviewQueue(queue);
 assert.equal(s.total,5);assert.equal(s.needsReview,4);assert.equal(s.approved,0);
 assert.deepEqual(s.priorities.map(x=>x.count),[1,1,1,1,1]);
});
test('review queue CSV protects formula injection and retains Unicode',()=>{
 const queue=buildClinicalReviewQueue([{id:9,name:'=HYPERLINK(1)',barcode:'@scan',active_ingredient:'مادة',strength:'',dosage_form:''}]);
 const csv=exportClinicalReviewQueueCsv(queue);
 assert.ok(csv.includes("'=HYPERLINK(1)"));
 assert.ok(csv.includes("'@scan"));
 assert.ok(csv.includes('مادة'));
});
test('alias candidates are never approved or automatically translated',()=>{
 const aliases=buildIngredientAliasCandidates(products);
 const summary=summarizeIngredientAliasCandidates(aliases);
 assert.equal(summary.approved,0);
 assert.equal(summary.automaticallyTranslated,0);
 assert.ok(aliases.every(x=>x.status==='candidate'&&x.clinical_approved===false&&x.canonical_ingredient_id===null));
 assert.ok(exportIngredientAliasCandidatesCsv(aliases).includes('مادة'));
});
