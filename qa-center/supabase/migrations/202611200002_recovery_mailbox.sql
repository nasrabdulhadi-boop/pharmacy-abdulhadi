create table public.qa_verified_recovery_mailboxes(
 manager_id uuid primary key references auth.users on delete cascade,
 mailbox_id uuid unique not null references auth.users on delete cascade,
 email text not null, verified_at timestamptz not null default now(),
 check(manager_id<>mailbox_id)
);
alter table public.qa_verified_recovery_mailboxes enable row level security;
revoke all on public.qa_verified_recovery_mailboxes from public,anon,authenticated;
grant select(manager_id,email,verified_at) on public.qa_verified_recovery_mailboxes to authenticated;
create policy own_recovery_mailbox on public.qa_verified_recovery_mailboxes for select to authenticated using(manager_id=auth.uid() and public.qa_current_system_role() in ('system_owner','system_admin'));
grant select,insert,update on public.qa_verified_recovery_mailboxes to service_role;
