-- Isolated QA only. Personal staff records are private, never employee-editable claims.
create table if not exists pharmacy_qa_private.staff_profiles(
 user_id uuid primary key references auth.users(id) on delete cascade,
 manager_id uuid not null, profile jsonb not null,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table if not exists pharmacy_qa_private.staff_commands(
 id uuid primary key,actor_id uuid not null,session_id uuid not null,
 action text not null check(action in ('create','password')),email text,target_id uuid,
 requested_role text not null check(requested_role in ('employee','technical_support','disabled')),
 profile jsonb,status text not null default 'pending' check(status in ('pending','completed','failed')),
 created_at timestamptz not null default now()
);
alter table pharmacy_qa_private.staff_profiles enable row level security;
alter table pharmacy_qa_private.staff_commands enable row level security;
revoke all on pharmacy_qa_private.staff_profiles,pharmacy_qa_private.staff_commands from public,anon,authenticated;
create unique index if not exists qa_staff_pending_email on pharmacy_qa_private.staff_commands(email) where action='create' and status='pending';
create unique index if not exists qa_staff_pending_password on pharmacy_qa_private.staff_commands(target_id) where action='password' and status='pending';
create index if not exists qa_staff_manager on pharmacy_qa_private.staff_profiles(manager_id);
create index if not exists qa_staff_command_actor_time on pharmacy_qa_private.staff_commands(actor_id,created_at desc);

create or replace function pharmacy_qa_private.clean_staff_profile(p jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare k text; v text; result jsonb:='{}'; lim integer;
begin
 if p is null or jsonb_typeof(p)<>'object' or length(p::text)>6000 or exists(select 1 from jsonb_object_keys(p) x where x not in ('full_name','phone','address','job_title','employee_code','start_date','notes')) then raise exception 'invalid_profile' using errcode='22023';end if;
 foreach k in array array['full_name','phone','address','job_title','employee_code','start_date','notes'] loop
  if p ? k and jsonb_typeof(p->k)<>'string' then raise exception 'invalid_profile' using errcode='22023';end if;
  v:=btrim(coalesce(p->>k,''));lim:=case k when 'notes' then 2000 when 'address' then 500 when 'phone' then 40 when 'start_date' then 10 else 120 end;
  if length(v)>lim or (k='full_name' and length(v)<2) or (k='start_date' and v<>'' and (v !~ '^\d{4}-\d{2}-\d{2}$' or to_char(v::date,'YYYY-MM-DD')<>v)) then raise exception 'invalid_profile' using errcode='22023';end if;
  result:=result||jsonb_build_object(k,v);
 end loop;return result;
end $$;
revoke all on function pharmacy_qa_private.clean_staff_profile(jsonb) from public,anon,authenticated;

create or replace function public.qa_admin_reserve_staff(p_id uuid,p_action text,p_email text,p_role text,p_target uuid,p_profile jsonb) returns boolean
language plpgsql security definer set search_path='' as $$
declare ar text:=public.qa_current_system_role(); tr text; normalized text:=lower(btrim(p_email)); clean jsonb;
begin
 if ar is null or ar not in ('system_owner','system_admin') or p_id is null or p_action is null or p_action not in ('create','password') then raise exception 'not_authorized' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('qa_staff_actor:'||auth.uid()::text,0));
 if (select count(*) from pharmacy_qa_private.staff_commands where actor_id=auth.uid() and created_at>now()-interval '1 hour')>=20 then raise exception 'rate_limited' using errcode='54000';end if;
 if p_action='create' then
  if p_role is null or p_role not in ('employee','technical_support') then raise exception 'not_authorized' using errcode='42501';end if;
  if normalized is null or length(normalized)>254 or normalized !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or p_target is not null then raise exception 'invalid_request' using errcode='22023';end if;
  clean:=pharmacy_qa_private.clean_staff_profile(p_profile);
  perform pg_advisory_xact_lock(hashtextextended('qa_invite_email:'||normalized,0));
  if exists(select 1 from auth.users where lower(email)=normalized) or exists(select 1 from pharmacy_qa_private.account_invitations where email=normalized and status='reserved' and created_at>now()-interval '5 minutes') then raise exception 'account_exists' using errcode='23505';end if;
  update pharmacy_qa_private.staff_commands set status='failed' where action='create' and email=normalized and status='pending' and created_at<now()-interval '5 minutes';
 else
  if p_target is null or p_target=auth.uid() then raise exception 'protected_account' using errcode='42501';end if;
  select u.raw_app_meta_data->>'system_role' into tr from auth.users u join pharmacy_qa_private.staff_profiles p on p.user_id=u.id where u.id=p_target and (ar='system_owner' or p.manager_id=auth.uid()) for update of u,p;
  if tr is null or tr not in ('employee','technical_support','disabled') then raise exception 'protected_account' using errcode='42501';end if;
  -- Do not expire a password command and restore access to a potentially partial reset.
  if exists(select 1 from pharmacy_qa_private.staff_commands where target_id=p_target and action='password' and status='pending') then raise exception 'operation_pending' using errcode='23505';end if;
 end if;
 insert into pharmacy_qa_private.staff_commands(id,actor_id,session_id,action,email,target_id,requested_role,profile)
 values(p_id,auth.uid(),(auth.jwt()->>'session_id')::uuid,p_action,case when p_action='create' then normalized end,p_target,case when p_action='create' then p_role else tr end,clean);
 if p_action='password' then
  update auth.users set raw_app_meta_data=(coalesce(raw_app_meta_data,'{}')-'role')||jsonb_build_object('system_role','disabled'),updated_at=now() where id=p_target;
  delete from auth.sessions where user_id=p_target;
 end if;
 perform pharmacy_qa_private.write_audit('staff_'||p_action||'_started','auth.users',p_target::text,jsonb_build_object('request_id',p_id,'password_recorded',false));
 return true;
end $$;

create or replace function public.qa_service_complete_staff(p_id uuid,p_target uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare c pharmacy_qa_private.staff_commands%rowtype; ar text; u auth.users%rowtype;
begin
 select * into c from pharmacy_qa_private.staff_commands where id=p_id for update;
 if not found or c.status<>'pending' or c.created_at<now()-interval '5 minutes' then raise exception 'invalid_request' using errcode='42501';end if;
 select case when a.raw_app_meta_data ? 'system_role' then a.raw_app_meta_data->>'system_role' when a.raw_app_meta_data->>'role'='admin' then 'system_admin' end into ar
 from auth.users a join auth.sessions s on s.user_id=a.id where a.id=c.actor_id and s.id=c.session_id and (s.not_after is null or s.not_after>now()) and (a.banned_until is null or a.banned_until<=now()) for share of a,s;
 if ar is null or ar not in ('system_owner','system_admin') then raise exception 'not_authorized' using errcode='42501';end if;
 select * into u from auth.users where id=p_target for update;
 if not found or u.raw_app_meta_data->>'system_role' is distinct from 'disabled' then raise exception 'protected_account' using errcode='42501';end if;
 if c.action='create' then
  if lower(u.email)<>c.email or u.created_at<c.created_at or u.raw_app_meta_data->>'qa_staff_request' is distinct from c.id::text or u.raw_app_meta_data->>'qa_staff_manager' is distinct from c.actor_id::text then raise exception 'protected_account' using errcode='42501';end if;
  insert into pharmacy_qa_private.staff_profiles(user_id,manager_id,profile) values(p_target,c.actor_id,c.profile);
 else
  if p_target is distinct from c.target_id or not exists(select 1 from pharmacy_qa_private.staff_profiles where user_id=p_target and (ar='system_owner' or manager_id=c.actor_id)) then raise exception 'protected_account' using errcode='42501';end if;
 end if;
 update auth.users set raw_app_meta_data=(coalesce(raw_app_meta_data,'{}')-'role')||jsonb_build_object('system_role',c.requested_role),banned_until=case when c.action='create' then null else banned_until end,updated_at=now() where id=p_target;
 delete from auth.sessions where user_id=p_target;
 update pharmacy_qa_private.staff_commands set status='completed',target_id=p_target where id=p_id;
 insert into pharmacy_qa_private.audit_events(id,actor_id,actor_email,actor_role,action,entity_type,entity_id,details)
 select gen_random_uuid(),a.id,a.email,ar,'staff_'||c.action||'_completed','auth.users',p_target::text,jsonb_build_object('request_id',p_id,'assigned_role',c.requested_role,'sessions_revoked',true,'password_recorded',false) from auth.users a where a.id=c.actor_id;
 return true;
end $$;

create or replace function public.qa_admin_save_staff_profile(p_target uuid,p_profile jsonb) returns boolean
language plpgsql security definer set search_path='' as $$
declare ar text:=public.qa_current_system_role();clean jsonb;
begin
 if ar is null or ar not in ('system_owner','system_admin') or p_target=auth.uid() then raise exception 'not_authorized' using errcode='42501';end if;
 perform 1 from auth.users u join pharmacy_qa_private.staff_profiles p on p.user_id=u.id where u.id=p_target and u.raw_app_meta_data->>'system_role' in ('employee','technical_support','disabled') and (ar='system_owner' or p.manager_id=auth.uid()) for update of u,p;
 if not found then raise exception 'protected_account' using errcode='42501';end if;
 clean:=pharmacy_qa_private.clean_staff_profile(p_profile);
 update pharmacy_qa_private.staff_profiles set profile=clean,updated_at=now() where user_id=p_target;
 perform pharmacy_qa_private.write_audit('staff_profile_updated','auth.users',p_target::text,jsonb_build_object('fields',array['full_name','phone','address','job_title','employee_code','start_date','notes']));return true;
end $$;
revoke all on function public.qa_admin_reserve_staff(uuid,text,text,text,uuid,jsonb),public.qa_admin_save_staff_profile(uuid,jsonb) from public,anon;
grant execute on function public.qa_admin_reserve_staff(uuid,text,text,text,uuid,jsonb),public.qa_admin_save_staff_profile(uuid,jsonb) to authenticated;
revoke all on function public.qa_service_complete_staff(uuid,uuid) from public,anon,authenticated;
grant execute on function public.qa_service_complete_staff(uuid,uuid) to service_role;

-- QA ONLY: existing Auth rows, live server roles, protected ownership and transactional audit.
create or replace function public.qa_admin_accounts() returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor_role text:=public.qa_current_system_role(); result jsonb;
begin
 if actor_role is null or actor_role not in ('system_owner','system_admin') then raise exception 'not_authorized' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into result from(
 select u.id,u.email,case when u.raw_app_meta_data ? 'system_role' then u.raw_app_meta_data->>'system_role' when u.raw_app_meta_data->>'role'='admin' then 'system_admin' else null end as system_role,
 p.manager_id,p.profile as staff_profile,(p.manager_id=auth.uid() or actor_role='system_owner') and p.user_id is not null as can_manage_profile,u.created_at,
 (u.banned_until is not null and u.banned_until>now()) as banned
 from auth.users u left join pharmacy_qa_private.staff_profiles p on p.user_id=u.id where actor_role='system_owner' or u.id=auth.uid() or
 (coalesce(u.raw_app_meta_data->>'system_role','') not in ('system_owner','system_admin') and not (not(u.raw_app_meta_data ? 'system_role') and coalesce(u.raw_app_meta_data->>'role','')='admin') and (p.user_id is null or p.manager_id=auth.uid()))
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
 if actor_role='system_admin' and exists(select 1 from pharmacy_qa_private.staff_profiles where user_id=p_user_id and manager_id<>auth.uid()) then raise exception 'protected_account' using errcode='42501';end if;
 if exists(select 1 from pharmacy_qa_private.staff_commands where target_id=p_user_id and action='password' and status='pending') then raise exception 'operation_pending' using errcode='42501';end if;
 if old_metadata ? 'qa_staff_request' and not exists(select 1 from pharmacy_qa_private.staff_profiles where user_id=p_user_id) then raise exception 'incomplete_account' using errcode='42501';end if;
 if target_role is not distinct from p_role then return false;end if;
 update auth.users set raw_app_meta_data=(coalesce(raw_app_meta_data,'{}')-'role')||jsonb_build_object('system_role',p_role),updated_at=now() where id=p_user_id;
 delete from auth.sessions where user_id=p_user_id;
 perform pharmacy_qa_private.write_audit('system_role_changed','auth.users',p_user_id::text,jsonb_build_object('source','server_transaction','before_role',target_role,'after_role',p_role,'sessions_revoked',true));
 return true;
end $$;
revoke all on function public.qa_admin_accounts(),public.qa_admin_set_role(uuid,text) from public,anon;
grant execute on function public.qa_admin_accounts(),public.qa_admin_set_role(uuid,text) to authenticated;
create or replace function public.qa_service_fail_staff(p_id uuid) returns boolean
language sql security definer set search_path='' as $$
 update pharmacy_qa_private.staff_commands set status='failed' where id=p_id and status='pending' returning true;
$$;
revoke all on function public.qa_service_fail_staff(uuid) from public,anon,authenticated;
grant execute on function public.qa_service_fail_staff(uuid) to service_role;
