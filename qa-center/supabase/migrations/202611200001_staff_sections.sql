create table pharmacy_qa_private.staff_sections (
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null, sections text[] not null
);
alter table pharmacy_qa_private.staff_sections enable row level security;
revoke all on pharmacy_qa_private.staff_sections from public,anon,authenticated;
create function pharmacy_qa_private.section_options(r text) returns text[] language sql immutable as $$
 select case r when 'employee' then array['dashboard','pos','pharmacyProducts','inventory','smart','purchases','suppliers','orders','returns','debtors']
 when 'technical_support' then array['dashboard','systemCenter'] else array[]::text[] end
$$;
create function public.qa_staff_sections(p_user uuid default auth.uid()) returns text[] language plpgsql stable security definer set search_path='' as $$
declare r text; choices text[];
begin
 if auth.uid() is null or p_user is null then raise exception 'not authorized'; end if;
 if p_user<>auth.uid() and not (coalesce(public.qa_current_system_role()='system_owner',false) or
 (coalesce(public.qa_current_system_role()='system_admin',false) and exists(select from pharmacy_qa_private.staff_profiles where user_id=p_user and manager_id=auth.uid()))) then raise exception 'not authorized';end if;
 select raw_app_meta_data->>'system_role' into r from auth.users where id=p_user;
 select sections into choices from pharmacy_qa_private.staff_sections where user_id=p_user and role=r;
 return coalesce(choices,pharmacy_qa_private.section_options(r));
end $$;
create function public.qa_set_staff_sections(p_user uuid,p_role text,p_sections text[]) returns void language plpgsql security definer set search_path='' as $$
declare r text;
begin
 if auth.uid() is null or p_user=auth.uid() or not coalesce(public.qa_current_system_role() in ('system_admin','system_owner'),false) then raise exception 'not authorized';end if;
 if public.qa_current_system_role()<>'system_owner' and not exists(select from pharmacy_qa_private.staff_profiles where user_id=p_user and manager_id=auth.uid()) then raise exception 'not authorized';end if;
 select raw_app_meta_data->>'system_role' into r from auth.users where id=p_user for update;
 if r is distinct from p_role or r not in ('employee','technical_support') or r is null or p_sections is null or not(p_sections <@ pharmacy_qa_private.section_options(r)) then raise exception 'invalid permissions';end if;
 insert into pharmacy_qa_private.staff_sections values(p_user,r,p_sections) on conflict(user_id) do update set role=excluded.role,sections=excluded.sections;
 perform pharmacy_qa_private.write_audit('staff_sections_changed','auth.users',p_user::text,jsonb_build_object('sections',p_sections));
end $$;
revoke all on function public.qa_staff_sections(uuid),public.qa_set_staff_sections(uuid,text,text[]) from public,anon;
grant execute on function public.qa_staff_sections(uuid),public.qa_set_staff_sections(uuid,text,text[]) to authenticated;

create function pharmacy_qa_private.require_staff_section(section_id text) returns void language plpgsql stable security definer set search_path='' as $$
begin
 if public.qa_current_system_role() in ('employee','technical_support') and not coalesce(section_id=any(public.qa_staff_sections()),false)
 then raise exception 'section denied' using errcode='42501';end if;
end $$;
revoke all on function pharmacy_qa_private.require_staff_section(text) from public,anon;
grant execute on function pharmacy_qa_private.require_staff_section(text) to authenticated;
do $guards$
declare rec record;def text;updated text;
begin
 for rec in select p.oid,p.proname from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in (
 'qa_employee_create_purchase','qa_employee_execute_workspace','qa_submit_workspace_bundle','qa_submit_employee_operation','qa_submit_sandbox_operation','qa_create_debtor','qa_list_debtors','qa_debtor_ledger','qa_record_debtor_payment','qa_save_workspace_product','qa_sync_offline_sale') loop
 def:=pg_get_functiondef(rec.oid);
 updated:=regexp_replace(def,'(\mbegin\M)', E'\\1\n perform pharmacy_qa_private.require_staff_section(' ||
 case when rec.proname in ('qa_employee_execute_workspace','qa_submit_workspace_bundle','qa_submit_employee_operation','qa_submit_sandbox_operation') then
 'case p_operation when ''sale'' then ''pos'' when ''purchase_draft'' then ''purchases'' when ''return_request'' then ''returns'' when ''order_process'' then ''orders'' when ''inventory_count'' then ''inventory'' when ''product_create'' then ''pharmacyProducts'' else ''inventory'' end'
 when rec.proname='qa_employee_create_purchase' then '''purchases''' when rec.proname='qa_save_workspace_product' then '''pharmacyProducts''' when rec.proname='qa_sync_offline_sale' then '''pos''' else '''debtors''' end ||');','i');
 if updated=def then raise exception 'missing guard point %',rec.proname;end if;
 execute updated;
 end loop;
end $guards$;
do $health$
declare def text;
begin
 def:=pg_get_functiondef('public.qa_support_health()'::regprocedure);
 if strpos(def,'where auth.uid() is not null')=0 then raise exception 'Unexpected health definition';end if;
 execute replace(def,'where auth.uid() is not null',
  'where (public.qa_current_system_role() is distinct from ''technical_support'' or public.qa_staff_sections() && array[''dashboard'',''systemCenter'']) and auth.uid() is not null');
end $health$;
