import test from 'node:test';
import assert from 'node:assert/strict';
import {createBilingualAliasIndex,resolveBilingualIngredient} from '../src/clinicalBilingualMapping.js';
import {inspectBilingualReviewPackage} from '../src/clinicalAliasReviewPackage.js';
import {parseBilingualReviewCsv} from '../src/clinicalReviewCsvIntake.js';
import {exportBilingualReviewTemplateCsv} from '../src/clinicalAliasReviewPackage.js';
const row=(alias,id)=>({alias,language:'ar',canonical_ingredient_id:id,status:'approved',reviewer_id:'reviewer',reviewed_at:'2026-10-25',source_reference_id:'reference',source_version:'1',source_document_id:'document'});
test('three-way conflicting aliases never resolve to an ingredient',()=>{
 const aliases=[row('مادة اختبار','a'),row('مادة اختبار','b'),row('مادة اختبار','a')];
 const r=createBilingualAliasIndex(aliases);
 assert.equal(resolveBilingualIngredient('مادة اختبار',r.index).canonicalIngredientId,null);
 assert.equal(resolveBilingualIngredient('مادة اختبار',r.index).status,'ambiguous');
});
test('normalized Arabic alias collisions quarantine all competing records',()=>{
 const r=inspectBilingualReviewPackage([row('إختبار','a'),row('اختبار','b')],[{alias:'اختبار'}]);
 assert.equal(r.accepted.length,0);
 assert.equal(r.conflicts.length,1);
 assert.equal(r.eligibleForProduction,false);
});
test('CSV embedded CRLF remains inside quoted alias field',()=>{
 const csv=exportBilingualReviewTemplateCsv([{alias:'مادة\r\nتجريبية',language:'ar'}]);
 const rows=parseBilingualReviewCsv(csv);
 assert.equal(rows.length,1);
 assert.equal(rows[0].alias,'مادة\r\nتجريبية');
});
test('CSV rejects unclosed quotes without approving any record',()=>{
 const csv=exportBilingualReviewTemplateCsv([{alias:'test',language:'en'}]);
 assert.throws(()=>parseBilingualReviewCsv(csv+'\r\n"unclosed'),/Unclosed CSV quotation/);
});
