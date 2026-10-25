import test from 'node:test';
import assert from 'node:assert/strict';
import {parseBilingualReviewCsv} from '../src/clinicalReviewCsvIntake.js';
import {exportBilingualReviewTemplateCsv} from '../src/clinicalAliasReviewPackage.js';
test('parser rejects files over 5 MiB before processing records',()=>{
 assert.throws(()=>parseBilingualReviewCsv('x'.repeat(5*1024*1024+1)),/5 MB limit/);
});
test('parser accepts exactly one ordinary review template row',()=>{
 const csv=exportBilingualReviewTemplateCsv([{alias:'Test Ingredient',language:'en'}]);
 const records=parseBilingualReviewCsv(csv);
 assert.equal(records.length,1);
 assert.equal(records[0].alias,'Test Ingredient');
});
test('CSV double quotes and Arabic text round-trip safely',()=>{
 const csv=exportBilingualReviewTemplateCsv([{alias:'مادة "تجريبية"',language:'ar'}]);
 assert.equal(parseBilingualReviewCsv(csv)[0].alias,'مادة "تجريبية"');
});
test('rejects truncated review rows instead of accepting partial data',()=>{
 const csv=exportBilingualReviewTemplateCsv([{alias:'Test',language:'en'}]);
 const lines=csv.split('\r\n');
 assert.throws(()=>parseBilingualReviewCsv(lines[0]+'\r\n"Test","en"'),/column count/);
});
