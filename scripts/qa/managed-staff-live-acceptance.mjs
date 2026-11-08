// Only disposable QA namespace. No production writes or credential output.
import fs from'node:fs';import assert from'node:assert/strict';import{randomUUID,randomBytes}from'node:crypto';import{createClient}from'@supabase/supabase-js';
const file=process.env.QA_ACCOUNT_FIXTURES,f=JSON.parse(fs.readFileSync(file,'utf8'));assert.equal(f.environment,'isolated-qa');assert.match(f.namespace,/^qa-staff-[a-f0-9]{12}$/);const QA='https://vpjxdsprfcpqclnhbeoh.supabase.co',checks=[],clients=[];
const check=(name,ok)=>{assert.ok(ok,name);checks.push(name);};
const client=()=>{const c=createClient(QA,f.key,{auth:{persistSession:false,autoRefreshToken:false},global:{fetch:(u,o)=>fetch(u,{...o,signal:AbortSignal.timeout(45000)})}});clients.push(c);return c;};
const login=async label=>{const u=f.users.find(x=>x.label===label),c=client(),r=await c.auth.signInWithPassword({email:u.email,password:u.password});check(label+' actual login',!r.error);return c;};
f.created||=[];const save=()=>fs.writeFileSync(file,JSON.stringify(f),{mode:0o600});
try{
 const manager=await login('manager'),other=await login('other'),employee=await login('employee'),support=await login('support');
 for(const [label,role]of [['newemployee','employee'],['newtech','technical_support']]){
  const email=f.namespace+'-'+label+'@example.invalid',password='Qa!'+randomBytes(24).toString('hex');
  const r=await manager.functions.invoke('qa-admin-staff-account',{body:{action:'create',request_id:randomUUID(),email,role,password,profile:{full_name:'حساب اصطناعي '+label,phone:'0000000',job_title:'اختبار فقط',employee_code:label,start_date:'2026-11-08',notes:'Synthetic acceptance only'}}});
  if(r.error){let diagnostic;try{diagnostic=await r.error.context.clone().json()}catch{}console.log({createStatus:r.error.context?.status,diagnostic});}
  check(label+' provisioned by manager',!r.error&&r.data?.completed===true);
  const created={id:r.data.user_id,email,password,label};f.created.push(created);save();
  const c=client(),signed=await c.auth.signInWithPassword({email,password});check(label+' can sign in',!signed.error);check(label+' exact assigned live role',(await c.rpc('qa_my_role')).data===role);
 }
 const t=f.created[0];let listed=await manager.rpc('qa_admin_accounts');check('manager sees full name and own linkage',listed.data.some(x=>x.id===t.id&&x.manager_id===f.users.find(x=>x.label==='manager').id&&x.staff_profile.full_name==='حساب اصطناعي newemployee'&&x.can_manage_profile));
 const updated=await manager.rpc('qa_admin_save_staff_profile',{p_target:t.id,p_profile:{full_name:'اسم موظف معدل',phone:'000111',address:'عنوان اصطناعي',job_title:'موظف',employee_code:'TEST',start_date:'2026-11-08',notes:'تعديل اصطناعي'}});check('manager edits personal staff record',!updated.error&&updated.data===true);
 check('another manager cannot list linked staff',!(await other.rpc('qa_admin_accounts')).data.some(x=>x.id===t.id));
 for(const [name,args]of [['qa_admin_save_staff_profile',{p_target:t.id,p_profile:{full_name:'Wrong manager'}}],['qa_admin_set_role',{p_user_id:t.id,p_role:'technical_support'}]])check('another manager denied '+name,(await other.rpc(name,args)).error?.code==='42501');
 for(const [label,proof]of [['missing',undefined],['incorrect','Incorrect-Only123!']]){const r=await manager.functions.invoke('qa-admin-staff-account',{body:{action:'password',request_id:randomUUID(),target_id:t.id,password:'NotApplied-Only123!',...(proof?{manager_password:proof}:{})}});check(label+' manager confirmation rejected',r.error?.context?.status===(proof?403:400));}
 check('incorrect confirmation leaves employee session active',(await clients[4].rpc('qa_my_role')).data==='employee');
 check('direct reset reservation without proof denied',(await manager.rpc('qa_admin_reserve_staff',{p_id:randomUUID(),p_action:'password',p_email:null,p_role:null,p_target:t.id,p_profile:null})).error?.code==='42501');
 const password='Reset!'+randomBytes(24).toString('hex');const reset=await manager.functions.invoke('qa-admin-staff-account',{body:{action:'password',request_id:randomUUID(),target_id:t.id,password,manager_password:f.users.find(x=>x.label==='manager').password}});check('manager resets linked account password',!reset.error&&reset.data?.completed===true);
 check('manager session survives confirmation',(await manager.rpc('qa_my_role')).data==='system_admin');
 check('old employee session revoked',(await clients[4].rpc('qa_my_role')).data===null);
 const oldLogin=await client().auth.signInWithPassword({email:t.email,password:t.password});check('old password rejected',!!oldLogin.error);
 const newLogin=await client().auth.signInWithPassword({email:t.email,password});check('new password accepted',!newLogin.error);t.password=password;save();
 for(const [label,c]of [['employee',employee],['support',support],['another manager',other]]){const r=await c.functions.invoke('qa-admin-staff-account',{body:{action:'password',request_id:randomUUID(),target_id:t.id,manager_password:'wrong',password:'Denied!'+randomBytes(24).toString('hex')}});check(label+' cannot reset target password',r.error?.context?.status===403);}
 check('staff personal record persists',(await manager.rpc('qa_admin_accounts')).data.find(x=>x.id===t.id)?.staff_profile.phone==='000111');
 const disabled=await manager.rpc('qa_admin_set_role',{p_user_id:t.id,p_role:'disabled'});check('manager disables linked account',!disabled.error&&disabled.data===true);
 console.log({passed:checks.length,failed:0});
}catch(e){console.error({passed:checks.length,failed:1,error:e.message});process.exitCode=1;}finally{for(const c of clients)await c.auth.signOut({scope:'global'}).catch(()=>{});fs.writeFileSync('/tmp/managed-staff-live-results.json',JSON.stringify({checks},null,2),{mode:0o600});}
