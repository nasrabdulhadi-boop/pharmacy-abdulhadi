import test from 'node:test';
import assert from 'node:assert/strict';
import {getBackupCenterStatus,normalizeBackupState} from '../src/systemBackupPolicy.js';
test('backup actions remain disabled for every preview state',()=>{
 for(const state of ['not_configured','pending_verification','verified','failed','unknown']){
  const status=getBackupCenterStatus({backupState:state,restoreTestPassed:true,serverAuthorizationVerified:true});
  assert.equal(status.canDownloadBackup,false);
  assert.equal(status.canRestore,false);
  assert.equal(status.requiresSeparateEnvironment,true);
 }
});
test('invalid state fails closed',()=>{
 assert.equal(normalizeBackupState('active'),'not_configured');
 assert.equal(getBackupCenterStatus().state,'not_configured');
});
