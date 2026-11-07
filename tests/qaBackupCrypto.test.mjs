import test from 'node:test';
import assert from 'node:assert/strict';
import {encryptQaBackup,decryptQaBackup,validateQaBackup} from '../src/qaBackupCrypto.js';
const data={format:'pharmacy-qa-application-backup-v1',project_ref:'vpjxdsprfcpqclnhbeoh',auth_credentials_included:false,tables:[{schema:'public',name:'products',row_count:1,rows:[{name:'صنف اصطناعي'}]}],functions:[],storage_files:[],storage_inventory:[]};
const pass='Synthetic backup passphrase 2026';
test('QA backup roundtrip preserves Arabic rows and never asserts restore readiness',async()=>{
 const envelope=await encryptQaBackup(data,pass,pass);assert.ok(!JSON.stringify(envelope).includes('صنف'));
 const result=await decryptQaBackup(envelope,pass);assert.deepEqual(result.data,data);assert.deepEqual(result.summary,{tables:1,rows:1,files:0,restoreVerified:false});
 const another=await encryptQaBackup(data,pass,pass);assert.notEqual(envelope.ciphertext,another.ciphertext);
});
test('wrong passwords and modified ciphertext cannot decrypt a backup',async()=>{
 const envelope=await encryptQaBackup(data,pass,pass);
 await assert.rejects(decryptQaBackup(envelope,pass+'wrong'),/backup_decryption_failed/);
 const tampered={...envelope,ciphertext:(envelope.ciphertext[0]==='A'?'B':'A')+envelope.ciphertext.slice(1)};
 await assert.rejects(decryptQaBackup(tampered,pass),/backup_decryption_failed/);
});
test('production archives, incomplete rows, unsafe KDF settings and weak phrases fail closed',async()=>{
 assert.throws(()=>validateQaBackup({...data,project_ref:'eewjjzgwoaxhojnjvzgq'}),/invalid_archive/);
 assert.throws(()=>validateQaBackup({...data,tables:[{...data.tables[0],row_count:2}]}),/invalid_archive/);
 await assert.rejects(encryptQaBackup(data,'short','short'),/invalid_passphrase/);
 await assert.rejects(encryptQaBackup(data,pass,'different'),/passphrase_mismatch/);
 const envelope=await encryptQaBackup(data,pass,pass);await assert.rejects(decryptQaBackup({...envelope,iterations:1},pass),/invalid_archive/);
});
