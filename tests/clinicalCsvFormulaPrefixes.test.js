import test from 'node:test';
import assert from 'node:assert/strict';
import {clinicalAuditCsv} from '../src/clinicalPreviewEngine.js';
import {exportBilingualReviewTemplateCsv} from '../src/clinicalAliasReviewPackage.js';
import {exportClinicalReviewQueueCsv} from '../src/clinicalCatalogReviewQueue.js';
import {exportIngredientAliasCandidatesCsv} from '../src/clinicalAliasCandidates.js';
import {clinicalCsvCell} from '../src/clinicalCsv.js';
test('all clinical exports escape formulas hidden behind whitespace and Unicode controls',()=>{
 for(const value of [' =1+1','\t=1','\n@SUM(1)','\u200b+cmd','\u202e-1']){
  const exports=[clinicalAuditCsv([{id:'x',name:value}]),exportBilingualReviewTemplateCsv([{alias:value,language:'en'}]),exportClinicalReviewQueueCsv([{product_name:value,reasons:[]}]),exportIngredientAliasCandidatesCsv([{alias:value,example_products:[]}])];
  for(const csv of exports)assert.ok(csv.includes('"\''+value),JSON.stringify(value));
 }
});
test('ordinary Arabic, quotes and multiline descriptions retain their text and valid CSV quoting',()=>{
 assert.equal(clinicalCsvCell('دواء "أ"'),'"دواء ""أ"""');
 assert.equal(clinicalCsvCell('مادة\nثانية'),'"مادة\nثانية"');
});
