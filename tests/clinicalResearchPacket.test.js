import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parseBilingualReviewCsv,inspectBilingualReviewCsv} from '../src/clinicalReviewCsvIntake.js';
test('shipped research pilot is unapproved and cannot activate local or clinical aliases',()=>{
 const csv=readFileSync(new URL('../docs/CLINICAL_BILINGUAL_PILOT_REVIEW_2026-10-25.csv',import.meta.url),'utf8');
 const rows=parseBilingualReviewCsv(csv);
 assert.equal(rows.length,34);assert.ok(rows.every(row=>row.status==='candidate'&&!row.reviewer_id&&!row.reviewed_at));
 const inspection=inspectBilingualReviewCsv(csv,rows.map(row=>({alias:row.alias})));
 assert.equal(inspection.acceptedCount,0);assert.equal(inspection.rejected.length,34);
 assert.deepEqual(inspection.sandboxAliases,[]);assert.equal(inspection.productionEnabled,false);
});
