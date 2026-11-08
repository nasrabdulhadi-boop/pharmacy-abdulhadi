-- QA only. Attempts contain no password, PIN, bearer token or email.
create table if not exists pharmacy_qa_private.staff_password_checks(
 id uuid primary key,actor_id uuid not null,session_id uuid not null,target_id uuid not null,
 created_at timestamptz not null default now(),verified_at timestamptz,consumed boolean not null default false
);
alter table pharmacy_qa_private.staff_password_checks enable row level security;
revoke all on pharmacy_qa_private.staff_password_checks from public,anon,authenticated;
create index if not exists qa_staff_checks_actor_time on pharmacy_qa_private.staff_password_checks(actor_id,created_at desc);
create or replace function public.qa_admin_begin_staff_password_check(p_id uuid,p_target uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare ar text:=public.qa_current_system_role();
begin
 if ar is null or ar not in ('system_owner','system_admin') or p_id is null or p_target=auth.uid() then raise exception 'not_authorized' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('qa_staff_check:'||auth.uid()::text,0));
 if not exists(select 1 from pharmacy_qa_private.staff_profiles p join auth.users u on u.id=p.user_id where p.user_id=p_target and (ar='system_owner' or p.manager_id=auth.uid()) and u.raw_app_meta_data->>'system_role' in ('employee','technical_support','disabled')) then raise exception 'protected_account' using errcode='42501';end if;
 if (select count(*) from pharmacy_qa_private.staff_password_checks where actor_id=auth.uid() and created_at>now()-interval '15 minutes')>=5 then raise exception 'rate_limited' using errcode='54000';end if;
 insert into pharmacy_qa_private.staff_password_checks(id,actor_id,session_id,target_id) values(p_id,auth.uid(),(auth.jwt()->>'session_id')::uuid,p_target);
 perform pharmacy_qa_private.write_audit('staff_password_confirmation_requested','auth.users',p_target::text,jsonb_build_object('request_id',p_id,'password_recorded',false));return true;
end $$;
create or replace function public.qa_service_verify_staff_password_check(p_id uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare c pharmacy_qa_private.staff_password_checks%rowtype;ar text;
begin
 select * into c from pharmacy_qa_private.staff_password_checks where id=p_id for update;
 if not found or c.consumed or c.verified_at is not null or c.created_at<now()-interval '90 seconds' then raise exception 'confirmation_required' using errcode='42501';end if;
 select case when u.raw_app_meta_data ? 'system_role' then u.raw_app_meta_data->>'system_role' when u.raw_app_meta_data->>'role'='admin' then 'system_admin' end into ar
 from auth.users u join auth.sessions s on s.user_id=u.id where u.id=c.actor_id and s.id=c.session_id and (s.not_after is null or s.not_after>now()) and (u.banned_until is null or u.banned_until<=now());
 if ar is null or ar not in ('system_owner','system_admin') or not exists(select 1 from pharmacy_qa_private.staff_profiles where user_id=c.target_id and (ar='system_owner' or manager_id=c.actor_id)) then raise exception 'not_authorized' using errcode='42501';end if;
 update pharmacy_qa_private.staff_password_checks set verified_at=now() where id=p_id;return true;
end $$;
revoke all on function public.qa_admin_begin_staff_password_check(uuid,uuid) from public,anon;
grant execute on function public.qa_admin_begin_staff_password_check(uuid,uuid) to authenticated;
revoke all on function public.qa_service_verify_staff_password_check(uuid) from public,anon,authenticated;
grant execute on function public.qa_service_verify_staff_password_check(uuid) to service_role;

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
  perform 1 from pharmacy_qa_private.staff_password_checks where id=p_id and actor_id=auth.uid() and session_id=(auth.jwt()->>'session_id')::uuid and target_id=p_target and verified_at is not null and created_at>now()-interval '90 seconds' and not consumed for update;
  if not found then raise exception 'confirmation_required' using errcode='42501';end if;
  update pharmacy_qa_private.staff_password_checks set consumed=true where id=p_id;
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
