-- QA only. Manual invitations generate no email and never persist bearer links.
create table if not exists pharmacy_qa_private.account_invitations(
 id uuid primary key,actor_id uuid not null,actor_session_id uuid not null,email text not null,
 requested_role text not null check(requested_role in ('system_admin','employee','technical_support')),
 status text not null default 'reserved' check(status in ('reserved','prepared','failed','expired')),
 target_id uuid,created_at timestamptz not null default now(),prepared_at timestamptz,
 check(email=lower(btrim(email)) and length(email)<=254)
);
alter table pharmacy_qa_private.account_invitations enable row level security;
revoke all on pharmacy_qa_private.account_invitations from public,anon,authenticated;
create unique index if not exists qa_invitation_active_email on pharmacy_qa_private.account_invitations(email) where status in ('reserved','prepared');
create index if not exists qa_invitation_actor_time on pharmacy_qa_private.account_invitations(actor_id,created_at desc);

create or replace function public.qa_admin_reserve_invitation(p_id uuid,p_email text,p_role text) returns boolean
language plpgsql security definer set search_path='' as $f$
declare actor_role text:=public.qa_current_system_role(); normalized text:=lower(btrim(p_email));
begin
 if actor_role is null or actor_role not in ('system_owner','system_admin') or p_role is null or p_role not in ('system_admin','employee','technical_support') or (p_role='system_admin' and actor_role<>'system_owner') then raise exception 'not_authorized' using errcode='42501';end if;
 if p_id is null or normalized is null or length(normalized)>254 or normalized !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'invalid_invitation' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('qa_invite_actor:'||auth.uid()::text,0));
 perform pg_advisory_xact_lock(hashtextextended('qa_invite_email:'||normalized,0));
 if exists(select 1 from auth.users where lower(email)=normalized) then raise exception 'existing_account' using errcode='23505';end if;
 if (select count(*) from pharmacy_qa_private.account_invitations where actor_id=auth.uid() and created_at>now()-interval '1 hour')>=10 then raise exception 'invitation_rate_limit' using errcode='54000';end if;
 update pharmacy_qa_private.account_invitations set status='expired' where email=normalized and status='prepared' and not exists(select 1 from auth.users u where u.id=target_id);
 update pharmacy_qa_private.account_invitations set status='expired' where email=normalized and status='reserved' and created_at<now()-interval '5 minutes';
 insert into pharmacy_qa_private.account_invitations(id,actor_id,actor_session_id,email,requested_role)
 values(p_id,auth.uid(),(auth.jwt()->>'session_id')::uuid,normalized,p_role);
 return true;
end $f$;
revoke all on function public.qa_admin_reserve_invitation(uuid,text,text) from public,anon;
grant execute on function public.qa_admin_reserve_invitation(uuid,text,text) to authenticated;

-- The service can finalize only a fresh reservation made by a still-authorized live session.
create or replace function public.qa_service_finalize_invitation(p_id uuid,p_target uuid) returns boolean
language plpgsql security definer set search_path='' as $f$
declare invitation pharmacy_qa_private.account_invitations%rowtype; actor_role text; target auth.users%rowtype;
begin
 select * into invitation from pharmacy_qa_private.account_invitations where id=p_id for update;
 if not found or invitation.status<>'reserved' or invitation.created_at<now()-interval '5 minutes' then raise exception 'invalid_invitation' using errcode='42501';end if;
 select case when u.raw_app_meta_data ? 'system_role' then u.raw_app_meta_data->>'system_role' when u.raw_app_meta_data->>'role'='admin' then 'system_admin' end into actor_role from auth.users u join auth.sessions s on s.user_id=u.id
 where u.id=invitation.actor_id and s.id=invitation.actor_session_id and (s.not_after is null or s.not_after>now()) and (u.banned_until is null or u.banned_until<=now()) for share of u,s;
 if actor_role is null or actor_role not in ('system_owner','system_admin') or (invitation.requested_role='system_admin' and actor_role<>'system_owner') then raise exception 'not_authorized' using errcode='42501';end if;
 select * into target from auth.users where id=p_target for update;
 if not found or lower(target.email)<>invitation.email or target.created_at<invitation.created_at or target.invited_at is null or target.email_confirmed_at is not null or target.raw_user_meta_data->>'qa_invitation_id' is distinct from p_id::text or target.raw_app_meta_data ? 'system_role' or target.raw_app_meta_data ? 'role' then raise exception 'protected_account' using errcode='42501';end if;
 update auth.users set raw_app_meta_data=coalesce(raw_app_meta_data,'{}')||jsonb_build_object('system_role',invitation.requested_role,'qa_invitation_id',p_id),updated_at=now() where id=p_target;
 delete from auth.sessions where user_id=p_target;
 update pharmacy_qa_private.account_invitations set status='prepared',target_id=p_target,prepared_at=now() where id=p_id;
 insert into pharmacy_qa_private.audit_events(id,actor_id,actor_email,actor_role,action,entity_type,entity_id,details)
 select gen_random_uuid(),u.id,u.email,actor_role,'system_invitation_prepared','auth.users',p_target::text,jsonb_build_object('invitation_id',p_id,'assigned_role',invitation.requested_role,'delivery','manual_link','email_sent',false) from auth.users u where u.id=invitation.actor_id;
 return true;
end $f$;
create or replace function public.qa_service_fail_invitation(p_id uuid) returns boolean
language sql security definer set search_path='' as $f$
 update pharmacy_qa_private.account_invitations set status='failed' where id=p_id and status='reserved' returning true;
$f$;
revoke all on function public.qa_service_finalize_invitation(uuid,uuid),public.qa_service_fail_invitation(uuid) from public,anon,authenticated;
grant execute on function public.qa_service_finalize_invitation(uuid,uuid),public.qa_service_fail_invitation(uuid) to service_role;
