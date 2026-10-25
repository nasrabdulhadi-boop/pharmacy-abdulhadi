import test from 'node:test';
import assert from 'node:assert/strict';
import {parseBilingualReviewCsv} from '../src/clinicalReviewCsvIntake.js';
import {exportBilingualReviewTemplateCsv} from '../src/clinicalAliasReviewPackage.js';
const valid=exportBilingualReviewTemplateCsv([{alias:'مادة تجريبية',language:'ar'}]);
test('rejects text after a closing CSV quote',()=>{
 assert.throws(()=>parseBilingualReviewCsv(valid.replace('"مادة تجريبية"','"مادة تجريبية"extra')),/Unexpected text/);
});
test('rejects unescaped quotes inside unquoted fields',()=>{
 assert.throws(()=>parseBilingualReviewCsv(valid.replace('"مادة تجريبية"','مادة" تجريبية')),/quotation/);
});
test('quoted newlines and commas round-trip without shifting columns',()=>{
 const csv=exportBilingualReviewTemplateCsv([{alias:'اسم,\nمركب',language:'ar'}]);
 const rows=parseBilingualReviewCsv(csv);
 assert.equal(rows.length,1);
 assert.equal(rows[0].alias,'اسم,\nمركب');
});
test('empty and BOM-only inputs fail closed',()=>{
 assert.throws(()=>parseBilingualReviewCsv('\uFEFF'),/Empty CSV/);
});
