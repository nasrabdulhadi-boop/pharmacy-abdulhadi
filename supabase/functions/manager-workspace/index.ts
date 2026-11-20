import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
const url=Deno.env.get('SUPABASE_URL');
const key=JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')||'{}').default||Deno.env.get('SUPABASE_ANON_KEY');
const secret=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const fresh={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
const issuer='pharmacy_manager_v1',restrictedRole='pharmacy_workspace_only';
const sectionsAllowed=['dashboard','pos','products','siteProducts','smart','inventory','purchases','suppliers','debtors','supplierDebts','prescriptions','requests','offers','orders','returns','customers','cashbox','financial','reports','daily','security','diagnostics','corrections','operations','branches','admin'];
const rights={employee:sectionsAllowed,support:sectionsAllowed};
const origins=new Set(['https://pharmacy-abdulhadi.vercel.app','https://pharmacy-abdulhadi-naser9.vercel.app','https://pharmacy-abdulhadi-i8qkqspk2-naser9.vercel.app']);
const manager=u=>u&&u.role==='authenticated'&&['system_admin','system_owner'].includes(u.app_metadata.system_role??(u.app_metadata.role==='admin'?'system_admin':''));
const mailbox=u=>u?.role===restrictedRole&&u.app_metadata?.workspace_issuer===issuer&&u.app_metadata?.staff_kind==='mailbox';
Deno.serve(async req=>{
 const origin=req.headers.get('origin')||'';
 const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Vary':'Origin','Cache-Control':'no-store'};
 const reply=(data,status=200)=>Response.json(data,{status,headers});
 if(url!=='https://eewjjzgwoaxhojnjvzgq.supabase.co'||!origins.has(origin))return new Response(null,{status:403});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply({},405);
 try{
 const raw=await req.text();if(raw.length>500000)return reply({},400);
 const b=JSON.parse(raw),auth=createClient(url,key,fresh),service=createClient(url,secret,fresh);
 const token=(req.headers.get('authorization')||'').replace(/^Bearer /i,'');
 const user=token?(await auth.auth.getUser(token)).data.user:null;
 const email=String(b.email||'').trim().toLowerCase();
 const denied=()=>reply({error:'تعذّر التحقق من الطلب.'},403);
 if(b.action==='file'){
  const m=user?.app_metadata;
  if(user?.role!==restrictedRole||m?.workspace_issuer!==issuer||!['employee','support'].includes(m.staff_kind)||!m.sections?.includes('prescriptions')||typeof b.path!=='string')return denied();
  const bucket=service.storage.from('prescriptions');
  if(b.op==='upload'){
   if(m.staff_kind==='support'&&!m.sections.includes('operations')||!b.path.startsWith('staff/'+user.id+'/')||!/^staff\/[a-f0-9-]+\/[a-zA-Z0-9_.-]{1,240}$/.test(b.path))return denied();
   const r=await bucket.createSignedUploadUrl(b.path);return r.error?denied():reply({result:r.data});
  }
  const row=await service.from('prescriptions').select('id').eq('file_path',b.path).limit(1);
  if(!row.data?.length)return denied();
  const r=await bucket.createSignedUrl(b.path,90);return r.error?denied():reply({result:r.data});
 }
 if(b.action==='table'){
  const meta=user?.app_metadata;
  if(user?.role!==restrictedRole||meta?.workspace_issuer!==issuer||!['support','employee'].includes(meta.staff_kind))return denied();
  const sections=Array.isArray(meta.sections)?meta.sections:[];
  const {table,steps}=b;
  const tables={
   pharmacy_branches:['branches'],orders:['dashboard'],prescriptions:['dashboard','prescriptions'],medicine_requests:['requests'],offers:['offers'],
   batches:['inventory','products','siteProducts'],products:['products','siteProducts'],sale_items:['financial'],
   pos_shortcut_preferences:['pos'],audit_logs:['security']
  };
  if(!Object.hasOwn(tables,table)||!tables[table].some(x=>sections.includes(x))||!Array.isArray(steps)||!steps.length||steps.length>12)return denied();
  const [first,...rest]=steps;
  const [operation,value]=first;
  let query=service.from(table);
  const selected={pharmacy_branches:['name,location,status'],orders:['id,status,created_at'],prescriptions:sections.includes('prescriptions')?['*','id,status,created_at']:['id,status,created_at'],medicine_requests:['*'],offers:['*'],products:['*','id,name,barcode,active'],batches:['id,purchase_currency,original_purchase_price','product_id,purchase_id,purchase_item_id,purchase_currency,original_purchase_price,purchase_price'],sale_items:['id,batch_id,unit_cost,unit_price,quantity,price_currency,price_fx_rate,sales!inner(created_at,currency,fx_rate)'],pos_shortcut_preferences:['items'],audit_logs:['*']};
  if(operation==='select'){
   if(!selected[table].includes(value))return denied();
   query=query.select(value);
   if(table==='pharmacy_branches')query=query.eq('owner_id',meta.manager_id);
   if(table==='pos_shortcut_preferences')query=query.eq('user_id',user.id);
  }else{
   if(meta.staff_kind==='support'&&!sections.includes('operations'))return denied();
   const writes={batches:{insert:['product_id','expiry_date','quantity','purchase_price','purchase_currency','purchase_fx_rate','original_purchase_price','received_date'],update:['expiry_date','purchase_price','purchase_currency','purchase_fx_rate','original_purchase_price']},offers:{insert:['title','description','active'],update:['active'],delete:[]},medicine_requests:{update:['status']},prescriptions:{insert:['file_path','file_name','mime_type','file_size','created_by','status'],update:['status']},pos_shortcut_preferences:{upsert:['user_id','items','updated_at']}};
   if(!Object.hasOwn(writes,table)||!Object.hasOwn(writes[table],operation)||table==='prescriptions'&&!sections.includes('prescriptions'))return denied();
   if(operation==='update'||operation==='delete'){
    if(rest.length!==1||rest[0][0]!=='eq'||rest[0][1]!=='id'||!/^[0-9a-f-]{36}$/i.test(rest[0][2]))return denied();
   }else if(rest.length)return denied();
   if(table!=='pos_shortcut_preferences'){
    const r=await service.rpc('manager_staff_change',{ws_actor:user.id,tab:table,op:operation,target:rest[0]?.[2]||null,val:value||{}});
    return r.error?reply({error:'تعذّر الحفظ. تحقق من صلاحية العملية والبيانات.'},400):reply({result:null});
   }
   if(operation==='delete'){if(!sections.includes('corrections'))return denied();query=query.delete();}
   else{
    if(!value||Object.keys(value).some(k=>!writes[table][operation].includes(k)))return denied();
    if(table==='pos_shortcut_preferences'&&value.user_id!==user.id)return denied();
    query=operation==='upsert'?query.upsert(value,{onConflict:'user_id'}):query[operation](value);
   }
  }
  for(const [method,col,arg] of rest){
   if(['single','maybeSingle'].includes(method)){query=query[method]();continue;}
   if(method==='limit'){if(!Number.isInteger(col)||col<1||col>2000)return denied();query=query.limit(col);continue;}
   if(method==='range'){if(!Number.isInteger(col)||!Number.isInteger(arg)||col<0||arg<col||arg-col>2000)return denied();query=query.range(col,arg);continue;}
   if(method==='or'&&table==='batches'&&col==='batch_number.is.null,batch_number.not.ilike.%bonus%'){query=query.or(col);continue;}
   if(!['id','product_id','active','user_id','created_at','sales.created_at','name','updated_at'].includes(col)||!['eq','in','gte','lt','order'].includes(method))return denied();
   query=method==='order'?query.order(col,{ascending:arg?.ascending!==false,nullsFirst:arg?.nullsFirst===true}):query[method](col,arg);
  }
  const r=await query;return r.error?reply({error:'تعذرت العملية على هذا القسم.'},400):reply({result:r.data});
 }
 if(b.action==='rpc'){
  if(user?.role!==restrictedRole||user.app_metadata?.workspace_issuer!==issuer||!['support','employee'].includes(user.app_metadata.staff_kind))return denied();
  if(typeof b.fn!=='string'||!/^([a-z][a-z0-9_]{1,60})$/.test(b.fn)||!b.args||Array.isArray(b.args)||typeof b.args!=='object')return denied();
  const r=await service.rpc('ws_'+b.fn,{...b.args,ws_actor:user.id});
  if(r.error)return reply({error:r.error.code==='42501'?'صلاحيات هذا الحساب لا تسمح بهذه العملية.':'تعذر إتمام العملية: '+r.error.message},400);
  return reply({result:r.data});
 }
 if(b.action==='command'){
  if(user?.role!==restrictedRole||user?.app_metadata?.workspace_issuer!==issuer)return denied();
  const r=await service.rpc('manager_staff_command',{p_actor:user.id,p_request:b.request,p_op:b.op,p_payload:b.payload});
  return r.error?denied():reply({result:r.data});
 }
 if(b.action==='view'){
  if(!user||user.role!==restrictedRole||user.app_metadata.workspace_issuer!==issuer||!Object.hasOwn(rights,user.app_metadata.staff_kind))return denied();
  if(!b.section)return reply({name:user.app_metadata.staff_name,sections:user.app_metadata.sections||[]});
  const r=await service.rpc('manager_staff_view',{p_actor:user.id,p_section:b.section,p_search:String(b.search||'')});
  return r.error?denied():reply({rows:r.data});
 }
 if(b.action==='recover'||b.action==='link'){
  if(b.action==='link'&&!manager(user))return denied();
  if(typeof b.password!=='string'||new TextEncoder().encode(b.password).length>72)return denied();
  if(b.action==='recover'&&b.password.length<12)return denied();
  const verified=b.proof?null:await auth.auth.verifyOtp({email,token:String(b.code),type:'email'});
  const jwt=b.proof||verified?.data.session?.access_token;
  const proof=jwt?(await auth.auth.getUser(jwt)).data.user:null;
  if(!mailbox(proof)||!proof.email_confirmed_at||proof.email!==email)return denied();
  const claims=JSON.parse(atob(jwt.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));
  if(!claims.amr?.some(a=>['otp','magiclink'].includes(a.method)&&a.timestamp*1000>Date.now()-600000))return denied();
  const consume=async()=>{const r=await service.rpc('manager_consume_mail_session',{p_user:proof.id,p_session:claims.session_id});return !r.error&&r.data===true;};
  if(b.action==='link'){
   if(proof.app_metadata.manager_id!==user.id)return denied();
   const check=await createClient(url,key,fresh).auth.signInWithPassword({email:user.email,password:b.password});
   if(check.error||check.data.user?.id!==user.id)return denied();
   if(!await consume())return denied();
   const r=await service.from('manager_recovery_contacts').upsert({manager_id:user.id,mailbox_id:proof.id,email,verified_at:new Date().toISOString()});
   return r.error?denied():reply({ok:true});
  }
  const row=await service.from('manager_recovery_contacts').select('manager_id').eq('mailbox_id',proof.id).eq('email',email).single();
  if(row.error)return denied();
  const target=(await service.auth.admin.getUserById(row.data.manager_id)).data.user;
  if(!manager(target)||target.factors?.some(f=>f.status==='verified')||Date.parse(target.banned_until)>Date.now())return denied();
  if(!await consume())return denied();
  const changed=await service.auth.admin.updateUserById(target.id,{password:b.password});
  return changed.error?denied():reply({ok:true});
 }
 if(!manager(user))return denied();
 if(b.action==='contact'){const r=await service.from('manager_recovery_contacts').select('email').eq('manager_id',user.id).maybeSingle();return r.error?denied():reply({email:r.data?.email||''});}
 if(b.action==='prepareMailbox'){
  if(!email||email===user.email||typeof b.current!=='string')return denied();
  const check=await createClient(url,key,fresh).auth.signInWithPassword({email:user.email,password:b.current});if(check.error||check.data.user?.id!==user.id)return denied();
  const find=await service.rpc('manager_find_mailbox',{p_manager:user.id,p_email:email});
  if(find.error)return denied();
  if(!find.data){const made=await service.auth.admin.createUser({email,role:restrictedRole,email_confirm:true,app_metadata:{workspace_issuer:issuer,manager_id:user.id,staff_kind:'mailbox'}});if(made.error)return denied();}
  return reply({ok:true});
 }
 if(!Object.hasOwn(rights,b.kind)||!Array.isArray(b.sections)||b.sections.some(s=>!rights[b.kind].includes(s)))return denied();
 const sections=[...new Set(b.sections)];
 if(b.action==='save'){
  const target=(await service.auth.admin.getUserById(b.id)).data.user;
  if(!target||target.role!==restrictedRole||target.app_metadata.workspace_issuer!==issuer||target.app_metadata.manager_id!==user.id||target.app_metadata.staff_kind!==b.kind)return denied();
  const r=await service.auth.admin.updateUserById(target.id,{app_metadata:{...target.app_metadata,sections}});return r.error?denied():reply({ok:true});
 }
 if(b.action!=='create'||typeof b.name!=='string'||!b.name.trim()||b.name.length>100||typeof b.password!=='string'||b.password.length<12||new TextEncoder().encode(b.password).length>72)return denied();
 const r=await service.auth.admin.createUser({email,password:b.password,role:restrictedRole,email_confirm:true,app_metadata:{workspace_issuer:issuer,manager_id:user.id,staff_kind:b.kind,staff_name:b.name.trim(),sections}});
 if(r.error){
  const reason={email_exists:'هذا البريد مرتبط بحساب موجود. اختر بريداً آخر أو عدّل الحساب الموجود.',weak_password:'اختر كلمة مرور أقوى من 12 محرفاً على الأقل.',email_address_invalid:'عنوان البريد غير صالح.'};
  return reply({error:reason[r.error.code]||'تعذّر إنشاء الحساب في خدمة تسجيل الدخول. رمز الخطأ: '+(r.error.code||r.error.status)},400);
 }
 return reply({ok:true});
 }catch{return reply({error:'تعذّر تنفيذ الطلب.'},400);}
});
