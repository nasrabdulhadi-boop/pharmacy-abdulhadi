import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {reviewPrimaryLabelPacket,exportPrimaryLabelReviewCsv} from '../src/clinicalPrimaryLabelReview.js';
import {clinicalRuleReleaseReady} from '../src/clinicalRuleEngine.js';
const packet=JSON.parse(readFileSync(new URL('../docs/CLINICAL_PRIMARY_LABEL_CASES_2026-10-26.json',import.meta.url),'utf8'));
const altered=change=>({...packet,cases:[{...packet.cases[0],...change}]});
test('three primary-label candidates remain unapproved and cannot become runtime rules',()=>{
 const result=reviewPrimaryLabelPacket(packet);
 assert.equal(result.cases.length,3);assert.equal(result.rejectedCount,0);assert.equal(result.conflictCount,0);
 assert.equal(result.clinicalRulesActivated,0);assert.equal(result.clinicallyApproved,false);assert.equal(result.productionEnabled,false);
 assert.ok(result.cases.every(row=>row.review_status==='pending'&&!row.clinical_approved&&!clinicalRuleReleaseReady(row)));
 assert.ok(packet.cases.every(row=>row.original_text.split(/\s+/).length<=25));
});
test('unofficial, credential-bearing or mismatched primary-label links are rejected',()=>{
 for(const change of [{source_url:'javascript:alert(1)'},{source_url:'https://dailymed.nlm.nih.gov.example.invalid/'},{source_url:'https://user:secret@dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid='+packet.cases[0].label_set_id},{source_xml_url:packet.cases[1].source_xml_url},{source_url:packet.cases[1].source_url}])assert.equal(reviewPrimaryLabelPacket(altered(change)).cases.length,0);
});
test('invalid dates, provenance, long excerpts or self-declared approvals do not enter the workbench',()=>{
 for(const change of [{effective_time:'20260230'},{retrieved_at:'not-a-date'},{source_sha256:'unknown'},{section_id:'missing'},{original_text:'word '.repeat(26)},{clinical_approved:true},{review_status:'approved'}])assert.equal(reviewPrimaryLabelPacket(altered(change)).cases.length,0);
});
test('conflicting source-record reuse quarantines both versions rather than choosing a pair',()=>{
 const result=reviewPrimaryLabelPacket({...packet,cases:[...packet.cases,{...packet.cases[0],ingredient_b:'synthetic-conflict'}]});
 assert.equal(result.conflictCount,1);assert.equal(result.cases.length,2);assert.equal(result.cases.some(x=>x.source_record_id===packet.cases[0].source_record_id),false);
});
test('packet activation flags and malformed containers fail closed',()=>{
 for(const input of [null,{}, {...packet,clinicalRulesActivated:1},{...packet,productionEnabled:true},{...packet,cases:{}}])assert.deepEqual(reviewPrimaryLabelPacket(input).cases,[]);
});
test('review CSV leaves reviewer fields empty and neutralizes self-declared spreadsheet formulas',()=>{
 const csv=exportPrimaryLabelReviewCsv(reviewPrimaryLabelPacket(altered({original_text:'=2+2'})));
 assert.ok(csv.includes('"\'=2+2"'));assert.ok(csv.includes('"pending","","",""'));
 assert.equal(csv.split('\r\n').length,2);assert.equal(packet.cases[0].review_status,'pending');
});
