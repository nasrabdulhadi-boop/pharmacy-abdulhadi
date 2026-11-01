-- QA ONLY: existing Auth rows, live server roles, protected ownership and transactional audit.
create or replace function public.qa_admin_accounts() returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_role text:=public.qa_current_system_role(); result jsonb;
begin
 if actor_role is null or actor_role not in ('system_owner','system_admin') then raise exception 'not_authorized' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into result from(
 select u.id,u.email,case when u.raw_app_meta_data ? 'system_role' then u.raw_app_meta_data->>'system_role' when u.raw_app_meta_data->>'role'='admin' then 'system_admin' else null end as system_role,
 (u.banned_until is not null and u.banned_until>now()) as banned
 from auth.users u where actor_role='system_owner' or u.id=auth.uid() or
 (coalesce(u.raw_app_meta_data->>'system_role','') not in ('system_owner','system_admin') and not (not(u.raw_app_meta_data ? 'system_role') and coalesce(u.raw_app_meta_data->>'role','')='admin'))
 order by u.created_at,u.id limit 100)x;
 perform pharmacy_qa_private.write_audit('system_accounts_viewed','auth.users',null,jsonb_build_object('source','server_read','rows',jsonb_array_length(result)));
 return result;
end $$;
create or replace function public.qa_admin_set_role(p_user_id uuid,p_role text) returns boolean
language plpgsql security definer set search_path='' as $$
declare actor_role text:=public.qa_current_system_role(); target_role text; old_metadata jsonb;
begin
 if actor_role is null or actor_role not in ('system_owner','system_admin') then raise exception 'not_authorized' using errcode='42501';end if;
 if p_user_id is null or p_user_id=auth.uid() or p_role is null or p_role not in ('system_admin','employee','technical_support','disabled') then raise exception 'protected_account_or_role' using errcode='42501';end if;
 select raw_app_meta_data into old_metadata from auth.users where id=p_user_id for update;
 if not found then raise exception 'account_not_found' using errcode='22023';end if;
 target_role:=case when old_metadata ? 'system_role' then old_metadata->>'system_role' when old_metadata->>'role'='admin' then 'system_admin' else null end;
 if target_role='system_owner' or (actor_role='system_admin' and (target_role='system_admin' or p_role='system_admin')) then raise exception 'protected_account_or_role' using errcode='42501';end if;
 if target_role is not distinct from p_role then return false;end if;
 update auth.users set raw_app_meta_data=(coalesce(raw_app_meta_data,'{}')-'role')||jsonb_build_object('system_role',p_role),updated_at=now() where id=p_user_id;
 delete from auth.sessions where user_id=p_user_id;
 perform pharmacy_qa_private.write_audit('system_role_changed','auth.users',p_user_id::text,jsonb_build_object('source','server_transaction','before_role',target_role,'after_role',p_role,'sessions_revoked',true));
 return true;
end $$;
revoke all on function public.qa_admin_accounts(),public.qa_admin_set_role(uuid,text) from public,anon;
grant execute on function public.qa_admin_accounts(),public.qa_admin_set_role(uuid,text) to authenticated;
