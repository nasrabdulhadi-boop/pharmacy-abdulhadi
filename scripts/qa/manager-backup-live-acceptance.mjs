// Full QA export is explicitly authorized by the user. Never exports production.
import fs from 'node:fs';import assert from 'node:assert/strict';import {randomBytes} from 'node:crypto';import {createClient} from '@supabase/supabase-js';import {encryptQaBackup,decryptQaBackup} from '../../src/qaBackupCrypto.js';
const f=JSON.parse(fs.readFileSync(process.env.QA_ACCOUNT_FIXTURES,'utf8'));assert.equal(f.environment,'isolated-qa');assert.match(f.namespace,/^qa-language-[a-f0-9]{12}$/);
const url='https://vpjxdsprfcpqclnhbeoh.supabase.co',checks=[];const check=(name,ok)=>{assert.ok(ok,name);checks.push({name,passed:true});};
try{for(const label of ['manager','employee','support']){
 const u=f.users.find(u=>u.label===label),c=createClient(url,f.key,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(u,o)=>fetch(u,{...o,signal:AbortSignal.timeout(90000)})}});
 try{const login=await c.auth.signInWithPassword({email:u.email,password:u.password});check(label+' actual QA login',!login.error);
 const direct=await c.rpc('qa_admin_backup_snapshot');const exported=await c.functions.invoke('qa-admin-application-backup',{body:{}});
 if(label!=='manager'){check(label+' cannot read snapshot',direct.error?.code==='42501');check(label+' cannot export backup',exported.error?.context?.status===403);continue;}
 check('manager can read snapshot',!direct.error&&direct.data?.auth_credentials_included===false);
 if(exported.error)console.log({backupStatus:exported.error.context?.status});
 check('manager can export a complete application backup',!exported.error&&exported.data?.export_complete===true&&!!exported.data.export_audit_id);
 const phrase=randomBytes(32).toString('base64url'),archive=await encryptQaBackup(exported.data,phrase,phrase),verified=await decryptQaBackup(archive,phrase);
 check('manager archive retains exact data',JSON.stringify(verified.data)===JSON.stringify(exported.data));check('backup excludes authentication credentials',verified.data.auth_credentials_included===false);check('restore is not falsely asserted',verified.summary.restoreVerified===false);
 const dir='/workspace/scratch/5865afe06d3d/private-qa-export';fs.mkdirSync(dir,{recursive:true,mode:0o700});fs.writeFileSync(dir+'/qa-manager-backup.json',JSON.stringify(archive),{mode:0o600});fs.writeFileSync(dir+'/qa-manager-backup-key.txt',phrase,{mode:0o600});
 fs.writeFileSync('/tmp/qa-manager-backup-summary.json',JSON.stringify({tables:verified.summary.tables,rows:verified.summary.rows,files:verified.summary.files,encryptedFileBytes:fs.statSync(dir+'/qa-manager-backup.json').size,authCredentialsIncluded:false,fullRestoreVerified:false}),{mode:0o600});
 }finally{await c.auth.signOut({scope:'global'});}
}console.log({passed:checks.length,failed:0});}catch(error){console.error({passed:checks.length,error:error.message});process.exitCode=1;}finally{fs.writeFileSync('/tmp/qa-manager-backup-live-results.json',JSON.stringify({checks},null,2),{mode:0o600});}
