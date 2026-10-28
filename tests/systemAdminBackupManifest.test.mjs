import test from 'node:test';
import assert from 'node:assert/strict';
import {validateBackupManifest,makeBackupReadinessReport} from '../src/systemAdminBackupManifest.js';
const sections=Object.fromEntries(['schema','policies','functions','table_counts','storage_inventory'].map(name=>[name,{verified:true,sha256:'a'.repeat(64)}]));
const sample={format:'pharmacy-admin-backup-v1',environment:'isolated-staging',created_at:'2026-10-29T00:00:00Z',includes_patient_data:false,sections};
test('rejects empty or production manifests',()=>{
 assert.equal(validateBackupManifest(null).ok,false);
 assert.equal(validateBackupManifest({...sample,environment:'production'}).ok,false);
 assert.equal(validateBackupManifest({...sample,includes_patient_data:true}).ok,false);
});
test('rejects missing or unverified manifest sections',()=>{
 assert.equal(validateBackupManifest({...sample,sections:{...sections,schema:{verified:false,sha256:'a'.repeat(64)}}}).ok,false);
 assert.equal(validateBackupManifest({...sample,sections:{schema:sections.schema}}).ok,false);
 assert.equal(validateBackupManifest({...sample,sections:{...sections,functions:{verified:true,sha256:'unsafe'}}}).ok,false);
});
test('manifest validation never implies an actual restore test',()=>{
 assert.equal(validateBackupManifest(sample).ok,true);
 assert.deepEqual(makeBackupReadinessReport(sample),{manifestValid:true,restoreTested:false,productionReady:false,errors:[]});
});
