import test from 'node:test';
import assert from 'node:assert/strict';
import {encryptArchive,decryptArchive,validateArchive} from '../src/managerArchive.js';
const archive={format:'pharmacy-manager-data-v1',tables:[{name:'sales',row_count:1,rows:[{total:'103.500',id:'9007199254740993'}]}]};
const phrase='a synthetic passphrase for testing';
test('encrypted pharmacy data round-trips with exact amounts and identifiers',async()=>{
 const envelope=await encryptArchive(archive,phrase,phrase);
 assert.deepEqual((await decryptArchive(envelope,phrase)).data,archive);
 await assert.rejects(decryptArchive(envelope,phrase+'!'));
 await assert.rejects(decryptArchive({...envelope,plaintext_sha256:'invalid'},phrase));
});
test('rejects a damaged manifest, duplicate tables and mismatched passphrase',async()=>{
 assert.throws(()=>validateArchive({...archive,tables:[...archive.tables,...archive.tables]}));
 assert.throws(()=>validateArchive({...archive,tables:[{...archive.tables[0],row_count:2}]}));
 await assert.rejects(encryptArchive(archive,phrase,'other'));
});
