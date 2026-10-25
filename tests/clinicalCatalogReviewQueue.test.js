import test from 'node:test';
import assert from 'node:assert/strict';
import {buildClinicalReviewQueue,summarizeClinicalReviewQueue,exportClinicalReviewQueueCsv} from '../src/clinicalCatalogReviewQueue.js';
test('missing ingredients are first and never auto-approved',()=>{
 const queue=buildClinicalReviewQueue([{id:1,name:'Known',active_ingredient:'Paracetamol',strength:'500 mg',dosage_form:'tablet'},{id:2,name:'Missing',active_ingredient:'',strength:'',dosage_form:''}]);
 assert.equal(queue[0].product_id,2);
 assert.equal(queue[0].priority,1);
 assert.equal(queue[0].clinical_approved,false);
 assert.equal(summarizeClinicalReviewQueue(queue).missingIngredient,1);
});
test('Arabic and mixed-script ingredients enter review queue',()=>{
 const queue=buildClinicalReviewQueue([{id:1,name:'Arabic',active_ingredient:'باراسيتامول',strength:'500',dosage_form:'حب'},{id:2,name:'Mixed',active_ingredient:'باراسيتامول Paracetamol',strength:'500',dosage_form:'tablet'}]);
 assert.equal(queue.find(x=>x.product_id===1).priority,3);
 assert.equal(queue.find(x=>x.product_id===2).priority,2);
});
test('CSV quotes formula-like values and preserves Arabic',()=>{
 const csv=exportClinicalReviewQueueCsv(buildClinicalReviewQueue([{id:3,name:'=HYPERLINK("x")',barcode:'123',active_ingredient:'مادة',strength:'',dosage_form:''}]));
 assert.ok(csv.startsWith('\uFEFF'));
 assert.ok(csv.includes('مادة'));
 assert.ok(csv.includes("'=HYPERLINK"));
});
