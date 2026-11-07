// Exports ONLY the new, explicitly tagged synthetic probe row and its synthetic PNG.
// Never calls the full QA snapshot function. No real account metadata or application rows are exported.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {encryptQaBackup,decryptQaBackup} from '../../src/qaBackupCrypto.js';
const fixture=JSON.parse(fs.readFileSync(process.env.QA_ACCOUNT_FIXTURES,'utf8'));
assert.equal(fixture.environment,'isolated-qa');
assert.match(fixture.probeId,/^[a-f0-9-]{36}$/);
const url='https://vpjxdsprfcpqclnhbeoh.supabase.co',results=[];
const check=(name,ok)=>{assert.ok(ok,name);results.push({name,passed:true});};
try{
 for(const label of ['owner','manager','employee','support','unknown']){
  const user=fixture.users.find(u=>u.label===label);
  const client=createClient(url,fixture.key,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(url,options)=>fetch(url,{...options,signal:AbortSignal.timeout(30000)})}});
  const signed=await client.auth.signInWithPassword({email:user.email,password:user.password});assert.equal(signed.error,null,'QA login '+label);
  const direct=await client.rpc('qa_admin_backup_probe_snapshot',{p_probe_id:fixture.probeId});
  if(label!=='owner'){check(label+' cannot call backup snapshot',direct.error?.code==='42501');}
  const response=await client.functions.invoke('qa-admin-application-backup',{body:{mode:'synthetic_probe',probe_id:fixture.probeId}});
  if(label!=='owner'){check(label+' cannot export Storage or application data',response.error?.context?.status===403);continue;}
  check('owner can read application snapshot without credentials',!direct.error&&direct.data?.auth_credentials_included===false);
  if(response.error){const context=response.error.context;console.error({backupStatus:context?.status,body:context?await context.text():null});}
  check('owner export includes server completion and audit evidence',!response.error&&response.data?.export_complete===true&&!!response.data?.export_audit_id);
  const data=response.data;
  check('Storage object bytes are included rather than metadata only',data.storage_files.length===data.storage_inventory.length&&data.storage_files.some(f=>f.name.startsWith('qa-backup-test/')));
  const passphrase='Disposable QA backup encryption test 2026';
  const archive=await encryptQaBackup(data,passphrase,passphrase);
  const verified=await decryptQaBackup(archive,passphrase);
  check('explicit synthetic probe rows and Storage bytes survive encrypted archive verification',JSON.stringify(verified.data)===JSON.stringify(data)&&verified.summary.files>0);
  check('archive verification never claims a completed restore',verified.summary.restoreVerified===false);
  await assert.rejects(decryptQaBackup(archive,passphrase+'wrong'));check('wrong archive passphrase is rejected',true);
  // Intentionally do not write account metadata, fixture credentials or backup rows to the repository.
 }
 console.log(JSON.stringify({passed:results.length,failed:0,fullRestoreTested:false}));
}catch(error){console.error(JSON.stringify({passed:results.length,error:error.message}));process.exitCode=1;}
finally{fs.writeFileSync('/tmp/admin-backup-live-results.json',JSON.stringify({results},null,2),{mode:0o600});}
