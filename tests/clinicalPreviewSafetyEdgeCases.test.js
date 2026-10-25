import test from 'node:test';
import assert from 'node:assert/strict';
import {parseIngredientField,screenExactIngredientOverlap,auditClinicalCatalog} from '../src/clinicalPreviewEngine.js';
import {parseBilingualReviewCsv} from '../src/clinicalReviewCsvIntake.js';

const header='alias,language,canonical_ingredient_id,status,source_reference_id,source_version,source_url,source_document_id,reviewer_id,reviewed_at';
test('missing or ambiguous ingredients never count as verified overlap',()=>{
 for(const raw of ['', 'A/B', 'A, B', 'A + ', 'A 500mg', 'A (salt)']){
  assert.notEqual(parseIngredientField(raw).status,'parsed',raw);
 }
 const result=screenExactIngredientOverlap([{id:1,name:'Unmapped',active_ingredient:'A/B'},{id:2,name:'Mapped',active_ingredient:'A'}]);
 assert.equal(result.overlaps.length,0);
 assert.equal(result.unresolved.length,1);
});
test('catalog audit counts missing data without claiming clinical coverage',()=>{
 const r=auditClinicalCatalog([{id:1,name:'Test',active_ingredient:'',strength:'',dosage_form:''}]);
 assert.equal(r.counts.total,1);
 assert.equal(r.counts.missingIngredient,1);
 assert.equal(r.counts.parseable,0);
});
test('CSV parser rejects wrong headers and malformed quoted records',()=>{
 assert.throws(()=>parseBilingualReviewCsv('alias,wrong\nA,B'));
 assert.throws(()=>parseBilingualReviewCsv(header+'\n"unclosed'));
 assert.throws(()=>parseBilingualReviewCsv(header+'\n"ok"unexpected,x'));
});
test('CSV parser accepts quoted comma as one field',()=>{
 const row='"acetylsalicylic, acid",en,123,pending,ref,v1,url,doc,reviewer,2026-10-25';
 const parsed=parseBilingualReviewCsv(header+'\n'+row);
 assert.equal(parsed.length,1);
 assert.equal(parsed[0].alias,'acetylsalicylic, acid');
});
