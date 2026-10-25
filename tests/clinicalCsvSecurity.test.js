import test from 'node:test';
import assert from 'node:assert/strict';
import {parseBilingualReviewCsv,inspectBilingualReviewCsv} from '../src/clinicalReviewCsvIntake.js';
import {exportBilingualReviewTemplateCsv} from '../src/clinicalAliasReviewPackage.js';
import {buildIngredientAliasCandidates} from '../src/clinicalAliasCandidates.js';
const candidates=buildIngredientAliasCandidates([{id:1,name:'دواء',active_ingredient:'مادة تجريبية'}]);
const base=exportBilingualReviewTemplateCsv(candidates);
test('rejects empty and malformed CSV safely',()=>{
 assert.throws(()=>parseBilingualReviewCsv(''),/Empty CSV/);
 assert.throws(()=>parseBilingualReviewCsv('wrong,header\n1,2'),/headers/);
 assert.throws(()=>parseBilingualReviewCsv(base+'\r\n"unterminated'),/quotation/);
});
test('CSV inspection does not activate clinical rules for candidate records',()=>{
 const r=inspectBilingualReviewCsv(base,candidates);
 assert.equal(r.total,1);
 assert.equal(r.acceptedCount,0);
 assert.equal(r.clinicalRulesActivated,0);
 assert.equal(r.productionEnabled,false);
});
test('rejects duplicate unescaped columns rather than silently truncating',()=>{
 const corrupted=base.replace('"candidate"','"candidate","extra"');
 assert.throws(()=>parseBilingualReviewCsv(corrupted),/column count/);
});
test('handles empty candidate list without approving an unknown alias',()=>{
 const r=inspectBilingualReviewCsv(base,[]);
 assert.equal(r.acceptedCount,0);
 assert.equal(r.productionEnabled,false);
});
