-- QA only. Financial reporting remains available through the owner report.
begin;
drop policy qa_branch_events_read on public.qa_branch_events;
create policy qa_branch_events_read on public.qa_branch_events for select to authenticated using (
  exists (select 1 from public.qa_branches b where b.id = branch_id and b.owner_id = (select auth.uid()))
);

create table public.qa_branch_suppliers (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.qa_branches(id),
  name text not null check (length(btrim(name)) between 2 and 120),
  phone text check (length(phone) <= 40),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);
create unique index qa_branch_supplier_name on public.qa_branch_suppliers (branch_id, lower(btrim(name)));
alter table public.qa_branch_suppliers enable row level security;
revoke all on public.qa_branch_suppliers from public, anon, authenticated;
grant select, insert (branch_id, name, phone) on public.qa_branch_suppliers to authenticated;
create policy qa_branch_suppliers_read on public.qa_branch_suppliers for select to authenticated using (
  exists (select 1 from public.qa_branches b where b.id = branch_id)
);
create policy qa_branch_suppliers_create on public.qa_branch_suppliers for insert to authenticated with check (
  created_by = (select auth.uid()) and exists (select 1 from public.qa_branches b where b.id = branch_id)
);

create function qa_branch_private.can_operate(p_branch uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.qa_branches b where b.id = p_branch and (
    (b.owner_id = auth.uid() and public.qa_current_system_role() in ('system_admin','system_owner'))
    or (b.member_id = auth.uid() and b.invite_email = qa_branch_private.live_email())
  ))
$$;
revoke all on function qa_branch_private.can_operate(uuid) from public, anon, authenticated;

create function qa_branch_private.operator_day(p_branch uuid, p_day date, p_kinds text[]) returns jsonb
language sql stable security definer set search_path = '' as $$
  with branch as (
    select id, name, location from public.qa_branches where id = p_branch and qa_branch_private.can_operate(p_branch)
  ), movements as (
    select e.id, e.kind, e.reference, e.recorded_at, e.amount, e.cash, e.quantity, e.reorder_level
    from public.qa_branch_events e join branch b on b.id = e.branch_id
    where e.recorded_at >= (p_day::timestamp at time zone 'Asia/Damascus')
      and e.recorded_at < ((p_day + 1)::timestamp at time zone 'Asia/Damascus')
      and e.kind = any(p_kinds)
    order by e.recorded_at desc,e.id desc limit 100
  ), inventory as (
    select distinct on (lower(btrim(e.reference))) e.id, e.reference, e.quantity, e.reorder_level
    from public.qa_branch_events e join branch b on b.id = e.branch_id
    where e.kind='inventory' and 'inventory'=any(p_kinds)
      and e.recorded_at < ((p_day + 1)::timestamp at time zone 'Asia/Damascus')
    order by lower(btrim(e.reference)), e.recorded_at desc,e.id desc
  )
  select jsonb_build_object(
    'branch', (select to_jsonb(b) from branch b),
    'movements', coalesce((select jsonb_agg(to_jsonb(m) order by m.recorded_at desc,m.id desc) from movements m),'[]'::jsonb),
    'inventory', coalesce((select jsonb_agg(to_jsonb(i) order by i.reference) from inventory i),'[]'::jsonb)
  )
$$;
create function qa_branch_private.event_saved(p_branch uuid,p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select qa_branch_private.can_operate(p_branch) and exists (
    select 1 from public.qa_branch_events e where e.branch_id=p_branch and e.id=p_id and e.actor_id=auth.uid()
  )
$$;
revoke all on function qa_branch_private.operator_day(uuid,date,text[]), qa_branch_private.event_saved(uuid,uuid) from public, anon;
grant execute on function qa_branch_private.operator_day(uuid,date,text[]), qa_branch_private.event_saved(uuid,uuid) to authenticated;

create function public.qa_branch_operator_day(p_branch uuid,p_day date,p_kinds text[]) returns jsonb
language sql security invoker stable set search_path = '' as $$
  select qa_branch_private.operator_day(p_branch,p_day,p_kinds)
$$;
create function public.qa_branch_event_saved(p_branch uuid,p_id uuid) returns boolean
language sql security invoker stable set search_path = '' as $$
  select qa_branch_private.event_saved(p_branch,p_id)
$$;
revoke all on function public.qa_branch_operator_day(uuid,date,text[]), public.qa_branch_event_saved(uuid,uuid) from public, anon;
grant execute on function public.qa_branch_operator_day(uuid,date,text[]), public.qa_branch_event_saved(uuid,uuid) to authenticated;
commit;
