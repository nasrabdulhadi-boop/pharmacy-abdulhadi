// Actual QA Auth/HTTP checks. Fixture credentials stay in an untracked private file.
// Does not send email, touch production, or modify pre-existing users.
import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createClient} from '@supabase/supabase-js';
import {saveOwnQaProfile,signOutOtherQaSessions} from '../../src/systemAdminProfileActions.js';
import {updateOwnQaPassword} from '../../src/qaAccountActions.js';
const url='https://vpjxdsprfcpqclnhbeoh.supabase.co';
const path=process.env.QA_ACCOUNT_FIXTURES;
if(!path)throw new Error('QA_ACCOUNT_FIXTURES must reference disposable test users');
const fixtures=JSON.parse(fs.readFileSync(path,'utf8'));
assert.equal(fixtures.environment,'isolated-qa');
assert.equal(fixtures.users.length,5);
assert.ok(fixtures.users.every(u=>u.email.startsWith('admin-close-')&&u.email.endsWith('@example.com')));
const results=[],clients=new Map(),check=(name,condition)=>{assert.ok(condition,name);results.push({name,passed:true});fs.writeFileSync('/tmp/admin-center-live-progress.json',JSON.stringify({passed:results.length,last:name}),{mode:0o600});};
const makeClient=()=>createClient(url,fixtures.key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},global:{fetch:(url,options)=>fetch(url,{...options,signal:AbortSignal.timeout(15000)})}});
async function login(label,password){
 const user=fixtures.users.find(u=>u.label===label),client=makeClient();
 const r=await client.auth.signInWithPassword({email:user.email,password:password||user.password});
 assert.equal(r.error,null,label+' Auth login');
 return client;
}
try{
 for(const user of fixtures.users){
  const client=await login(user.label);clients.set(user.label,client);
  const expected={owner:'system_owner',manager:'system_admin',employee:'employee',support:'technical_support',unknown:null}[user.label];
  const role=await client.rpc('qa_my_role');
  check(user.label+' real signed session uses the server role',!role.error&&role.data===expected);
 }
 const owner=clients.get('owner'),manager=clients.get('manager');
 for(const label of ['owner','manager']){
  const r=await clients.get(label).rpc('qa_admin_center_status');
  check(label+' live security status denies direct sensitive access',!r.error&&r.data?.unprotected_public_tables===0&&r.data?.anonymous_sensitive_tables===0);
  const list=await clients.get(label).rpc('qa_admin_accounts');
  check(label+' account list contains current disposable account',!list.error&&list.data.some(u=>u.id===fixtures.users.find(u=>u.label===label).id));
 }
 for(const label of ['employee','support','unknown']){
  for(const rpc of ['qa_admin_accounts','qa_admin_center_status']){
   const r=await clients.get(label).rpc(rpc);check(label+' denied '+rpc,r.error?.code==='42501');
  }
 }
 const support=await clients.get('support').rpc('qa_workspace_snapshot');
 check('support snapshot exposes only technical status and role',!support.error&&JSON.stringify(Object.keys(support.data).sort())===JSON.stringify(['health','role']));
 for(const label of ['support','employee','unknown','anonymous']){
  const client=label==='anonymous'?makeClient():clients.get(label);
  for(const table of ['audit_logs','batches','cashbox_entries','debtors','debtor_transactions','inventory_count_items','inventory_counts','orders','prescriptions','purchase_items','purchases','returns','sale_items','sales','stock_movements','supplier_payments','suppliers']){
   const r=await client.from(table).select('id').limit(1);
   check(label+' direct REST denied '+table,r.error?.code==='42501'||r.status===401||r.status===403);
  }
 }
 const identity=fixtures.users.find(u=>u.label==='manager').id;
 await saveOwnQaProfile({client:manager,projectUrl:url,previewEnabled:true,expectedUserId:identity,name:'QA profile acceptance'});
 const profile=await manager.auth.getUser();check('display name is saved by actual Auth',!profile.error&&profile.data.user.user_metadata.full_name==='QA profile acceptance');
 await manager.auth.updateUser({data:{system_role:'system_owner'}});
 const unchanged=await manager.rpc('qa_my_role');check('user-editable metadata cannot elevate account',!unchanged.error&&unchanged.data==='system_admin');
 const oldOther=await login('manager');
 await signOutOtherQaSessions({client:manager,projectUrl:url,previewEnabled:true,expectedUserId:identity});
 const current=await manager.rpc('qa_my_role'),revoked=await oldOther.rpc('qa_my_role');
 check('other sessions are revoked but current session remains live',!current.error&&current.data==='system_admin'&&!revoked.error&&revoked.data===null);
 const employeeId=fixtures.users.find(u=>u.label==='employee').id;
 const elevated=await clients.get('manager').rpc('qa_admin_set_role',{p_user_id:employeeId,p_role:'system_admin'});
 check('manager cannot elevate another account to administrator',elevated.error?.code==='42501');
 const change=await owner.rpc('qa_admin_set_role',{p_user_id:employeeId,p_role:'technical_support'});
 check('owner can update disposable employee role',!change.error&&change.data===true);
 const stale=await clients.get('employee').rpc('qa_my_role');check('old employee JWT loses role immediately after change',!stale.error&&stale.data===null);
 const restore=await owner.rpc('qa_admin_set_role',{p_user_id:employeeId,p_role:'employee'});
 check('disposable employee role restored',!restore.error&&restore.data===true);
 const user=fixtures.users.find(u=>u.label==='manager'),nextPassword=user.password+'-changed';
 await updateOwnQaPassword({client:manager,previewEnabled:true,projectUrl:url,password:nextPassword,confirmation:nextPassword,expectedUserId:identity});
 const newer=await login('manager',nextPassword);const verified=await newer.auth.getUser();
 check('new password signs into the same disposable identity',!verified.error&&verified.data.user.id===identity);
 user.password=nextPassword;fs.writeFileSync(path,JSON.stringify(fixtures),{mode:0o600});
 console.log(JSON.stringify({passed:results.length,failed:0,mailDeliveryTested:false}));
}catch(error){console.error(JSON.stringify({passed:results.length,error:error.message}));process.exitCode=1;}
finally{fs.writeFileSync('/tmp/admin-center-live-results.json',JSON.stringify({results},null,2),{mode:0o600});}
