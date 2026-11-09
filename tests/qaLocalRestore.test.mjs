import test from 'node:test';
import assert from 'node:assert/strict';
import {encryptQaBackup} from '../src/qaBackupCrypto.js';
import {rehearseQaArchive} from '../scripts/qa/restore-qa-archive-local.mjs';
const phrase='Synthetic local restore passphrase 2026';
function fixture(){return {format:'pharmacy-qa-application-backup-v1',project_ref:'vpjxdsprfcpqclnhbeoh',auth_credentials_included:false,numeric_encoding:'decimal-string-v1',schemas:['pharmacy_qa_private'],tables:[{schema:'pharmacy_qa_private',name:'precision_fixture',rls:true,force_rls:false,columns:[{name:'id',type:'bigint',not_null:true},{name:'amount',type:'numeric(30,12)',not_null:true},{name:'double_amount',type:'numeric',generated:'s',default:'amount * 2'}],constraints:[{name:'precision_fixture_pkey',definition:'PRIMARY KEY (id)'},{name:'amount_positive',definition:'CHECK (amount > 0)'}],indexes:[],policies:[],triggers:[],rows:[{id:'9223372036854775807',amount:'999999999999999999.123456789012',double_amount:'1999999999999999998.246913578024'}],row_count:1}],functions:[],sequences:[{schemaname:'pharmacy_qa_private',sequencename:'precision_fixture_seq',data_type:'bigint',increment_by:'1',min_value:'1',max_value:'9223372036854775807',start_value:'1',cache_size:'1',cycle:false,last_value:'9223372036854775806'}],storage_inventory:[],storage_files:[]};}
test('local restore preserves maximum bigint and exact decimal values, generated columns and constraints',async()=>{
 const f=fixture(),archive=await encryptQaBackup(f,phrase,phrase),result=await rehearseQaArchive(archive,phrase);
 assert.equal(result.allRowsMatch,true);assert.equal(result.tables,1);assert.equal(result.constraints,2);assert.equal(result.sequences,1);assert.equal(result.platformRestoreVerified,false);assert.equal(result.authRuntimeRestored,false);assert.equal(result.grantsRestored,false);
});
test('local restore fails on a row that violates its restored accounting constraint',async()=>{
 const f=fixture();f.tables[0].rows[0].amount='-1';f.tables[0].rows[0].double_amount='-2';
 const archive=await encryptQaBackup(f,phrase,phrase);
 await assert.rejects(rehearseQaArchive(archive,phrase),error=>error.safeSummary?.failedAt==='constraints'&&error.safeSummary.sqlState==='23514');
});
test('legacy numeric encoding is refused instead of claiming exact recovery',async()=>{
 const f=fixture();delete f.numeric_encoding;
 const archive=await encryptQaBackup(f,phrase,phrase);
 await assert.rejects(rehearseQaArchive(archive,phrase),/archive_requires_exact_decimal_encoding/);
});

test('downloaded recovery can be reopened independently and queried', async () => {
 const {PGlite} = await import('@electric-sql/pglite');
 const {restoreQaArchive} = await import('../src/qaRestoreArchive.js');
 const archive = await encryptQaBackup(fixture(), phrase, phrase);
 const {result, database} = await restoreQaArchive(archive, phrase, {
  createDatabase: () => new PGlite(),
  saveDatabase: true,
  reopenDatabase: database => new PGlite({loadDataDir: database}),
 });
 assert.equal(result.allRowsMatch, true);
 assert.equal(result.localRestartVerified, true);
 assert.equal(result.platformRestoreVerified, false);
 const recovered = new PGlite({loadDataDir: database});
 try {
  const {rows} = await recovered.query('select id::text, amount::text, double_amount::text from pharmacy_qa_private.precision_fixture');
  assert.deepEqual(rows, fixture().tables[0].rows);
 } finally {
  await recovered.close();
 }
});

test('a failed restart with missing rows blocks a recovery result', async () => {
 const {PGlite} = await import('@electric-sql/pglite');
 const {restoreQaArchive} = await import('../src/qaRestoreArchive.js');
 const archive = await encryptQaBackup(fixture(), phrase, phrase);
 await assert.rejects(restoreQaArchive(archive, phrase, {
  createDatabase: () => new PGlite(),
  saveDatabase: true,
  reopenDatabase: () => ({
   query: async () => ({rows: [{rows: []}]}),
   close: async () => {},
  }),
 }), /row_digest_mismatch/);
});
