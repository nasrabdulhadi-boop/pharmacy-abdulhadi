-- Test-only export route. It can read exactly one explicitly tagged synthetic record and PNG.
create table if not exists pharmacy_qa_private.backup_export_probe(
 id uuid primary key default gen_random_uuid(),
 actor_id uuid not null,
 fixture_namespace text not null check(fixture_namespace ~ '^admin-close-[a-f0-9]{12}$'),
 quantity integer not null default 1 check(quantity between 0 and 10)
);
alter table pharmacy_qa_private.backup_export_probe enable row level security;
revoke all on pharmacy_qa_private.backup_export_probe from public,anon,authenticated;
create or replace function public.qa_admin_backup_probe_snapshot(p_probe_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $function$
declare probe pharmacy_qa_private.backup_export_probe;
begin
 if public.qa_current_system_role() is distinct from 'system_owner' then raise exception 'not_authorized' using errcode='42501';end if;
 select p.* into probe from pharmacy_qa_private.backup_export_probe p join auth.users u on u.id=p.actor_id
 where p.id=p_probe_id and p.actor_id=auth.uid() and u.raw_app_meta_data->>'qa_fixture_namespace'=p.fixture_namespace;
 if not found then raise exception 'synthetic_probe_not_found' using errcode='42501';end if;
 return jsonb_build_object('format','pharmacy-qa-application-backup-v1','project_ref','vpjxdsprfcpqclnhbeoh','scope','synthetic-probe-only','created_at',now(),
 'tables',jsonb_build_array(jsonb_build_object('schema','pharmacy_qa_private','name','backup_export_probe','row_count',1,'rows',jsonb_build_array(jsonb_build_object('id',probe.id,'name','QA backup probe (synthetic)','quantity',probe.quantity)))),
 'functions','[]'::jsonb,'storage_inventory',(select coalesce(jsonb_agg(jsonb_build_object('bucket_id',o.bucket_id,'name',o.name,'updated_at',o.updated_at,'metadata',o.metadata)),'[]') from storage.objects o
 where o.bucket_id='supplier-preview-prescriptions' and o.name='qa-backup-test/'||probe.fixture_namespace||'/pixel.png'),
 'auth_credentials_included',false,'restore_verified',false);
end $function$;
revoke all on function public.qa_admin_backup_probe_snapshot(uuid) from public,anon;
grant execute on function public.qa_admin_backup_probe_snapshot(uuid) to authenticated;
