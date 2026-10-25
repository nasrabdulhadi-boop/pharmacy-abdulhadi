import test from 'node:test';
import assert from 'node:assert/strict';
import {parseBilingualReviewCsv,inspectBilingualReviewCsv} from '../src/clinicalReviewCsvIntake.js';
import {exportBilingualReviewTemplateCsv} from '../src/clinicalAliasReviewPackage.js';
import {buildClinicalReviewQueue} from '../src/clinicalCatalogReviewQueue.js';
import {buildIngredientAliasCandidates} from '../src/clinicalAliasCandidates.js';
test('CRLF Arabic review template round-trip remains unapproved',()=>{
 const candidates=buildIngredientAliasCandidates([{id:1,name:'دواء تجريبي',active_ingredient:'مادة تجريبية',strength:'',dosage_form:''}]);
 const csv=exportBilingualReviewTemplateCsv(candidates).replace(/\r\n/g,'\n').replace(/\n/g,'\r\n');
 const parsed=parseBilingualReviewCsv(csv);
 assert.equal(parsed.length,1);
 assert.equal(parsed[0].alias,'مادة تجريبية');
 const result=inspectBilingualReviewCsv(csv,candidates);
 assert.equal(result.acceptedCount,0);
 assert.equal(result.productionEnabled,false);
});
test('CSV parser rejects extra columns and unterminated quoted fields',()=>{
 const csv=exportBilingualReviewTemplateCsv([{alias:'مادة',language:'ar'}]);
 assert.throws(()=>parseBilingualReviewCsv(csv.replace('"candidate"','"candidate","extra"')),/column count/);
 assert.throws(()=>parseBilingualReviewCsv(csv+'\r\n"unterminated'),/quotation/);
});
test('missing ingredient has highest review priority and no clinical approval',()=>{
 const rows=buildClinicalReviewQueue([{id:'missing',name:'مجهول',active_ingredient:'',strength:'',dosage_form:''},{id:'known',name:'Test',active_ingredient:'Ingredient X',strength:'10 mg',dosage_form:'tablet'}]);
 assert.equal(rows[0].product_id,'missing');
 assert.equal(rows[0].priority,1);
 assert.ok(rows.every(r=>r.clinical_approved===false));
});
