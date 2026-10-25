import test from 'node:test';
import assert from 'node:assert/strict';
import {validateEvidenceCandidate,inspectEvidenceCandidates} from '../src/clinicalEvidenceIntake.js';
const sample={source_id:'synthetic',source_version:'test-1',source_record_id:'r1',ingredient_a:'A',ingredient_b:'B',evidence_kind:'research',original_text:'Synthetic evidence for testing only',source_url:'https://example.org/test',license_status:'unknown'};
test('requires source traceability and explicit license assessment',()=>{
 assert.equal(validateEvidenceCandidate(sample).valid,true);
 assert.equal(validateEvidenceCandidate({...sample,source_url:''}).valid,false);
 assert.equal(validateEvidenceCandidate({...sample,license_status:''}).valid,false);
});
test('detects duplicate and conflicting source record without activating rules',()=>{
 const result=inspectEvidenceCandidates([sample,{...sample},{...sample,ingredient_b:'C'}]);
 assert.equal(result.accepted.length,0);
 assert.equal(result.duplicates.length,2);
 assert.equal(result.conflicts.length,1);
 assert.equal(result.clinicalRulesActivated,0);
 assert.equal(result.quarantinedRecordCount,1);
});
test('rejects incomplete source records',()=>{
 const result=inspectEvidenceCandidates([{...sample,original_text:''}]);
 assert.equal(result.invalid.length,1);
 assert.equal(result.accepted.length,0);
});

test('identical source duplicates retain one research candidate but never approve it',()=>{
 const result=inspectEvidenceCandidates([sample,{...sample}]);
 assert.equal(result.accepted.length,1);assert.equal(result.accepted[0].clinical_approved,false);
 assert.equal(result.accepted[0].review_status,'pending');assert.equal(result.conflicts.length,0);
});
test('malformed non-text evidence and non-web source locators are rejected',()=>{
 for(const patch of [{source_id:{}},{source_version:[]},{source_record_id:true},{original_text:{}},{ingredient_a:{}},{source_url:'javascript:alert(1)'}]){
  assert.equal(validateEvidenceCandidate({...sample,...patch}).valid,false,JSON.stringify(patch));
 }
});
test('source identifiers containing separators do not collide accidentally',()=>{
 const result=inspectEvidenceCandidates([{...sample,source_id:'a::b',source_version:'c'}, {...sample,source_id:'a',source_version:'b::c'}]);
 assert.equal(result.accepted.length,2);assert.equal(result.duplicates.length,0);
});
