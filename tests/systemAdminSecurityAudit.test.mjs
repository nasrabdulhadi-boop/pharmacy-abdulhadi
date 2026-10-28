import test from 'node:test';
import assert from 'node:assert/strict';
import {assessStagingAuthorization,QA_AUTHORIZATION_FINDINGS} from '../src/systemAdminSecurityAudit.js';
const clean={environment:'isolated-staging',hasEmailAdminBypass:false,hasPublicDefinerExecute:false,hasSensitiveSchemaCoverage:true,testedRoles:['system_owner','system_admin','technical_support'],directApiDenyTestsPassed:true,rpcDenyTestsPassed:true,revocationTestsPassed:true};
test('actual QA findings block release',()=>{
 const result=assessStagingAuthorization(QA_AUTHORIZATION_FINDINGS);
 assert.equal(result.ready,false);
 assert.ok(result.issues.includes('email_admin_bypass'));
 assert.ok(result.issues.includes('incomplete_sensitive_schema'));
});
test('missing data and incomplete checks always fail closed',()=>{
 assert.equal(assessStagingAuthorization(null).ready,false);
 for(const key of Object.keys(clean)){
  const copy={...clean};delete copy[key];
  assert.equal(assessStagingAuthorization(copy).ready,false,key);
 }
});
test('only explicit passing evidence for all gates is ready',()=>{
 assert.deepEqual(assessStagingAuthorization(clean),{ready:true,issues:[]});
 assert.equal(assessStagingAuthorization({...clean,environment:'production'}).ready,false);
});
