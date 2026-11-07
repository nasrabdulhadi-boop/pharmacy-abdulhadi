-- QA application backup only. Does not read Auth passwords, tokens, Vault or other schemas.
create or replace function public.qa_admin_backup_snapshot() returns jsonb
language plpgsql stable security definer set search_path='' as $function$
declare actor_role text:=public.qa_current_system_role(); t record; data_rows jsonb; tables_json jsonb:='[]'; row_total bigint; result jsonb;
 schemas constant text[]:=array['public','pharmacy_qa_private','pharmacy_supplier_stage','supplier_currency_qa'];
begin
 if actor_role is distinct from 'system_owner' then raise exception 'not_authorized' using errcode='42501';end if;
 for t in select c.oid,c.relname,n.nspname,c.relrowsecurity,c.relforcerowsecurity,c.relacl::text as grants
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname=any(schemas) and c.relkind='r' order by n.nspname,c.relname
 loop
  execute format('select count(*) from %I.%I',t.nspname,t.relname) into row_total;
  if row_total>50000 then raise exception 'qa_backup_table_limit';end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text),''[]''::jsonb) from %I.%I r',t.nspname,t.relname) into data_rows;
  tables_json:=tables_json||jsonb_build_array(jsonb_build_object(
   'schema',t.nspname,'name',t.relname,'rls',t.relrowsecurity,'force_rls',t.relforcerowsecurity,'grants',t.grants,
   'columns',(select coalesce(jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'identity',a.attidentity,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum),'[]') from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=t.oid and a.attnum>0 and not a.attisdropped),
   'constraints',(select coalesce(jsonb_agg(jsonb_build_object('name',c.conname,'definition',pg_get_constraintdef(c.oid)) order by c.conname),'[]') from pg_constraint c where c.conrelid=t.oid),
   'indexes',(select coalesce(jsonb_agg(indexdef order by indexname),'[]') from pg_indexes where schemaname=t.nspname and tablename=t.relname),
   'policies',(select coalesce(jsonb_agg(to_jsonb(p) order by p.policyname),'[]') from pg_policies p where p.schemaname=t.nspname and p.tablename=t.relname),
   'triggers',(select coalesce(jsonb_agg(pg_get_triggerdef(tr.oid) order by tr.tgname),'[]') from pg_trigger tr where tr.tgrelid=t.oid and not tr.tgisinternal),
   'row_count',row_total,'rows',data_rows
  ));
 end loop;
 result:=jsonb_build_object('format','pharmacy-qa-application-backup-v1','project_ref','vpjxdsprfcpqclnhbeoh',
  'created_at',now(),'scope','application schemas and Storage; excludes Auth credentials, sessions and platform configuration',
  'schemas',schemas,'tables',tables_json,
  'functions',(select coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'grants',p.proacl::text) order by n.nspname,p.proname,p.oid),'[]') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname=any(schemas) and p.prokind='f'),
  'sequences',(select coalesce(jsonb_agg(to_jsonb(s) order by s.schemaname,s.sequencename),'[]') from pg_sequences s where s.schemaname=any(schemas)),
  'storage_inventory',(select coalesce(jsonb_agg(jsonb_build_object('bucket_id',o.bucket_id,'name',o.name,'updated_at',o.updated_at,'metadata',o.metadata) order by o.bucket_id,o.name),'[]') from storage.objects o where o.bucket_id='supplier-preview-prescriptions'),
  'storage_buckets',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'public',b.public,'file_size_limit',b.file_size_limit,'allowed_mime_types',b.allowed_mime_types)),'[]') from storage.buckets b where b.id='supplier-preview-prescriptions'),
  'auth_metadata',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,'app_metadata',u.raw_app_meta_data,'user_metadata',u.raw_user_meta_data,'created_at',u.created_at,'banned_until',u.banned_until) order by u.id),'[]') from auth.users u),
  'auth_credentials_included',false,'restore_verified',false);
 if pg_column_size(result)>5000000 then raise exception 'qa_backup_size_limit';end if;
 return result;
end $function$;
revoke all on function public.qa_admin_backup_snapshot() from public,anon;
grant execute on function public.qa_admin_backup_snapshot() to authenticated;

-- Only the trusted Edge service may record a completed server export.
create or replace function public.qa_record_completed_backup_export(p_actor uuid,p_sha256 text,p_tables integer,p_files integer) returns uuid
language plpgsql security definer set search_path='' as $function$
declare event_id uuid:=gen_random_uuid();
begin
 if p_sha256 is null or p_sha256 !~ '^[a-f0-9]{64}$' or p_tables<1 or p_files<0 or p_files>30 then raise exception 'invalid_export_evidence';end if;
 if not exists(select 1 from auth.users where id=p_actor and raw_app_meta_data->>'system_role'='system_owner' and (banned_until is null or banned_until<=now()))then raise exception 'not_authorized' using errcode='42501';end if;
 insert into pharmacy_qa_private.audit_events(id,actor_id,actor_email,actor_role,action,entity_type,entity_id,details)
 select event_id,u.id,u.email,'system_owner','qa_application_backup_exported','backup',event_id::text,
 jsonb_build_object('source','trusted_edge_service','source_sha256',p_sha256,'tables',p_tables,'files',p_files,'auth_credentials_included',false,'restore_verified',false)
 from auth.users u where u.id=p_actor;
 return event_id;
end $function$;
revoke all on function public.qa_record_completed_backup_export(uuid,text,integer,integer) from public,anon,authenticated;
grant execute on function public.qa_record_completed_backup_export(uuid,text,integer,integer) to service_role;
