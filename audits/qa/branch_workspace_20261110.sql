-- Isolated QA only. The existing single-pharmacy tables are independent of this workspace.
begin;
create schema qa_branch_private;
revoke all on schema qa_branch_private from public, anon;
grant usage on schema qa_branch_private to authenticated;

create table public.qa_branches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  name text not null check (length(btrim(name)) between 2 and 100),
  location text not null check (length(btrim(location)) between 2 and 140),
  invite_email text not null check (
    invite_email = lower(btrim(invite_email)) and length(invite_email) <= 254
    and invite_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
  ),
  member_id uuid,
  created_at timestamptz not null default now()
);
create index qa_branches_owner_idx on public.qa_branches (owner_id);
create index qa_branches_member_idx on public.qa_branches (member_id);
alter table public.qa_branches enable row level security;
revoke all on public.qa_branches from public, anon, authenticated;
grant select, insert (name, location, invite_email) on public.qa_branches to authenticated;

create function qa_branch_private.live_email() returns text
language sql stable security definer set search_path = '' as $$
  select lower(u.email) from auth.users u join auth.sessions s on s.user_id = u.id
  where u.id = auth.uid() and s.id::text = auth.jwt()->>'session_id'
    and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until <= now())
    and (s.not_after is null or s.not_after > now())
$$;
revoke all on function qa_branch_private.live_email() from public, anon;
grant execute on function qa_branch_private.live_email() to authenticated;

create policy qa_branches_read on public.qa_branches for select to authenticated using (
  (owner_id = (select auth.uid()) and (select public.qa_current_system_role()) in ('system_owner','system_admin'))
  or (member_id = (select auth.uid()) and invite_email = (select qa_branch_private.live_email()))
);
create policy qa_branches_create on public.qa_branches for insert to authenticated with check (
  owner_id = (select auth.uid()) and (select public.qa_current_system_role()) in ('system_owner','system_admin')
  and member_id is null and invite_email <> (select qa_branch_private.live_email())
);

create function qa_branch_private.claim_branch(p_branch uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare confirmed_email text := qa_branch_private.live_email();
begin
  if confirmed_email is null then return false; end if;
  update public.qa_branches
    set member_id = auth.uid()
    where id = p_branch and invite_email = confirmed_email
      and owner_id <> auth.uid() and (member_id is null or member_id = auth.uid());
  return found;
end
$$;
revoke all on function qa_branch_private.claim_branch(uuid) from public, anon;
grant execute on function qa_branch_private.claim_branch(uuid) to authenticated;

create function public.qa_claim_branch(p_branch uuid) returns boolean
language sql security invoker set search_path = '' as $$
  select qa_branch_private.claim_branch(p_branch)
$$;
revoke all on function public.qa_claim_branch(uuid) from public, anon;
grant execute on function public.qa_claim_branch(uuid) to authenticated;

create table public.qa_branch_events (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.qa_branches(id),
  actor_id uuid not null default auth.uid(),
  recorded_at timestamptz not null default now(),
  kind text not null check (kind in ('sale','return','purchase','expense','deposit','withdrawal','inventory')),
  reference text not null check (length(btrim(reference)) between 1 and 160),
  amount bigint not null default 0 check (amount between 0 and 1000000000000),
  cash bigint not null default 0 check (cash between 0 and amount),
  cost bigint not null default 0 check (cost between 0 and 1000000000000),
  quantity integer check (quantity between 0 and 100000000),
  reorder_level integer check (reorder_level between 0 and 100000000),
  check (
    (kind = 'inventory' and amount = 0 and cash = 0 and cost = 0 and quantity is not null and reorder_level is not null)
    or (kind <> 'inventory' and amount > 0 and quantity is null and reorder_level is null
      and (kind in ('sale','return') or cost = 0)
      and (kind not in ('expense','deposit','withdrawal') or cash = amount))
  )
);
create index qa_branch_events_day_idx on public.qa_branch_events (branch_id, recorded_at desc, id desc);
create index qa_branch_inventory_idx on public.qa_branch_events (branch_id, lower(btrim(reference)), recorded_at desc, id desc) where kind = 'inventory';
alter table public.qa_branch_events enable row level security;
revoke all on public.qa_branch_events from public, anon, authenticated;
grant select, insert (id, branch_id, kind, reference, amount, cash, cost, quantity, reorder_level)
  on public.qa_branch_events to authenticated;
create policy qa_branch_events_read on public.qa_branch_events for select to authenticated using (
  exists (select 1 from public.qa_branches b where b.id = branch_id)
);
create policy qa_branch_events_append on public.qa_branch_events for insert to authenticated with check (
  actor_id = (select auth.uid()) and exists (select 1 from public.qa_branches b where b.id = branch_id)
);

create function public.qa_branch_day(p_day date, p_branch uuid default null) returns jsonb
language sql stable security invoker set search_path = '' as $$
  with branches as (
    select * from public.qa_branches b where p_branch is null or b.id = p_branch
  ), daily as (
    select e.* from public.qa_branch_events e join branches b on b.id = e.branch_id
    where e.recorded_at >= (p_day::timestamp at time zone 'Asia/Damascus')
      and e.recorded_at < ((p_day + 1)::timestamp at time zone 'Asia/Damascus')
  ), balances as (
    select e.branch_id, coalesce(sum(case
      when e.kind in ('sale','deposit') then e.cash else -e.cash end),0) as cash_balance
    from public.qa_branch_events e join branches b on b.id = e.branch_id
    where e.recorded_at < ((p_day + 1)::timestamp at time zone 'Asia/Damascus')
    group by e.branch_id
  ), inventory as (
    select distinct on (e.branch_id, lower(btrim(e.reference))) e.*
    from public.qa_branch_events e join branches b on b.id = e.branch_id
    where e.kind = 'inventory' and e.recorded_at < ((p_day + 1)::timestamp at time zone 'Asia/Damascus')
    order by e.branch_id, lower(btrim(e.reference)), e.recorded_at desc, e.id desc
  ), totals as (
    select b.id, b.name, b.location, b.invite_email, b.member_id,
      coalesce(sum(d.amount) filter (where d.kind='sale'),0)::text as sales,
      coalesce(sum(d.amount) filter (where d.kind='return'),0)::text as returns,
      count(*) filter (where d.kind='sale') as invoices,
      count(*) filter (where d.kind='return') as return_count,
      coalesce(sum(d.amount) filter (where d.kind='purchase'),0)::text as purchases,
      coalesce(sum(case when d.kind='sale' then d.amount-d.cost when d.kind='return' then d.cost-d.amount
        when d.kind='expense' then -d.amount else 0 end),0)::text as profit,
      coalesce(sum(d.cash) filter (where d.kind in ('sale','deposit')),0)::text as cash_in,
      coalesce(sum(d.cash) filter (where d.kind in ('return','purchase','expense')),0)::text as cash_paid,
      coalesce(sum(d.cash) filter (where d.kind='withdrawal'),0)::text as cash_withdrawn,
      coalesce((select cash_balance from balances where branch_id=b.id),0)::text as cash_balance,
      (select count(*) from inventory i where i.branch_id=b.id and i.quantity<=i.reorder_level) as shortages
    from branches b left join daily d on d.branch_id=b.id group by b.id,b.name,b.location,b.invite_email,b.member_id
  )
  select jsonb_build_object(
    'branches', coalesce((select jsonb_agg(to_jsonb(t) order by t.name,t.id) from totals t),'[]'::jsonb),
    'movements', coalesce((select jsonb_agg(to_jsonb(m) order by m.recorded_at desc,m.id desc) from (
      select * from daily where p_branch is not null order by recorded_at desc,id desc limit 100
    ) m),'[]'::jsonb),
    'inventory', coalesce((select jsonb_agg(to_jsonb(i) order by i.reference) from inventory i where p_branch is not null),'[]'::jsonb)
  )
$$;
revoke all on function public.qa_branch_day(date,uuid) from public, anon;
grant execute on function public.qa_branch_day(date,uuid) to authenticated;
commit;
