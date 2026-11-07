-- QA ONLY. Apply only to vpjxdsprfcpqclnhbeoh after rollback-only regression checks.
-- Preserves every row, private schema and operational RPC. No production statements.
do $guard$
declare target record;
begin
 if not exists(select 1 from pg_namespace where nspname='pharmacy_qa_private')
  or to_regprocedure('public.qa_current_system_role()') is null then
  raise exception 'isolated QA schema required';
 end if;
 for target in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r' and not c.relrowsecurity
 loop
  execute format('alter table public.%I enable row level security',target.relname);
  execute format('revoke all on table public.%I from public, anon, authenticated',target.relname);
 end loop;
end $guard$;

create or replace function public.qa_admin_center_status() returns jsonb
language plpgsql stable security definer set search_path='' as $function$
declare actor_role text:=public.qa_current_system_role(); result jsonb;
begin
 if actor_role is null or actor_role not in ('system_owner','system_admin') then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 select jsonb_build_object('schema_version',1,
  'unprotected_public_tables',count(*) filter(where not c.relrowsecurity),
  'anonymous_sensitive_tables',count(*) filter(where c.relname<>'products' and
   (has_table_privilege('anon',c.oid,'SELECT') or has_table_privilege('anon',c.oid,'INSERT')
    or has_table_privilege('anon',c.oid,'UPDATE') or has_table_privilege('anon',c.oid,'DELETE')
    or has_table_privilege('anon',c.oid,'TRUNCATE'))),
  'checked_at',now()) into result
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind='r';
 return result;
end $function$;
revoke all on function public.qa_admin_center_status() from public,anon;
grant execute on function public.qa_admin_center_status() to authenticated;
