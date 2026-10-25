import test from 'node:test';
import assert from 'node:assert/strict';
import {parseBilingualReviewCsv,inspectBilingualReviewCsv} from '../src/clinicalReviewCsvIntake.js';
import {exportBilingualReviewTemplateCsv} from '../src/clinicalAliasReviewPackage.js';
test('template round-trips Arabic and quoted punctuation',()=>{
 const csv=exportBilingualReviewTemplateCsv([{alias:'مادة, "اختبار"',language:'ar'}]);
 const rows=parseBilingualReviewCsv(csv);
 assert.equal(rows[0].alias,'مادة, "اختبار"');
 assert.equal(rows[0].status,'candidate');
});
test('unapproved template is not clinically accepted',()=>{
 const csv=exportBilingualReviewTemplateCsv([{alias:'باراسيتامول',language:'ar'}]);
 const result=inspectBilingualReviewCsv(csv,[{alias:'باراسيتامول'}]);
 assert.equal(result.acceptedCount,0);
 assert.equal(result.rejected.length,1);
 assert.equal(result.productionEnabled,false);
});
test('malformed or unexpected CSV is rejected',()=>{
 assert.throws(()=>parseBilingualReviewCsv('alias,language\na,b'),/headers/);
 assert.throws(()=>parseBilingualReviewCsv('alias,"unclosed'),/quotation/);
});
