

create schema pharmacy_branch_private;
revoke all on schema pharmacy_branch_private from public, anon;
grant usage on schema pharmacy_branch_private to authenticated;

create function pharmacy_branch_private.manager_role() returns text
language sql stable security definer set search_path='' as $$
 select case when u.raw_app_meta_data ? 'system_role' then u.raw_app_meta_data->>'system_role'
 when u.raw_app_meta_data->>'role'='admin' then 'system_admin' end
 from auth.users u where u.id=auth.uid() and (u.banned_until is null or u.banned_until<=now())
$$;
revoke all on function pharmacy_branch_private.manager_role() from public,anon,authenticated;
grant execute on function pharmacy_branch_private.manager_role() to authenticated;

create table public.pharmacy_branches (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid(),
  name text not null check (length(btrim(name)) between 2 and 100),
  location text not null check (length(btrim(location)) between 2 and 140),
  invite_email text not null check (
    invite_email = lower(btrim(invite_email)) and length(invite_email) <= 254
    and invite_email ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
  ),
  status text not null default 'active' check (status in ('active','paused','archived')),
  member_id uuid,
  created_at timestamptz not null default now()
);
create index pharmacy_branches_owner_idx on public.pharmacy_branches (owner_id);
create index pharmacy_branches_member_idx on public.pharmacy_branches (member_id);
alter table public.pharmacy_branches enable row level security;
revoke all on public.pharmacy_branches from public, anon, authenticated;
grant select, insert (name, location, invite_email) on public.pharmacy_branches to authenticated;

create function pharmacy_branch_private.live_email() returns text
language sql stable security definer set search_path = '' as $$
  select lower(u.email) from auth.users u join auth.sessions s on s.user_id = u.id
  where u.id = auth.uid() and s.id::text = auth.jwt()->>'session_id'
    and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until <= now())
    and (s.not_after is null or s.not_after > now())
$$;
revoke all on function pharmacy_branch_private.live_email() from public, anon;
grant execute on function pharmacy_branch_private.live_email() to authenticated;

create policy pharmacy_branches_read on public.pharmacy_branches for select to authenticated using (
  (owner_id = (select auth.uid()) and (select pharmacy_branch_private.manager_role()) in ('system_owner','system_admin'))
  or (status='active' and (select pharmacy_branch_private.manager_role())='branch_operator' and member_id = (select auth.uid()) and invite_email = (select pharmacy_branch_private.live_email()))
);
create policy pharmacy_branches_create on public.pharmacy_branches for insert to authenticated with check (
  owner_id = (select auth.uid()) and (select pharmacy_branch_private.manager_role()) in ('system_owner','system_admin')
  and member_id is null and invite_email <> (select pharmacy_branch_private.live_email())
);

create function pharmacy_branch_private.claim_branch(p_branch uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare confirmed_email text := pharmacy_branch_private.live_email();
begin
  if confirmed_email is null or not exists (select 1 from auth.users u where u.id=auth.uid()
 and u.raw_app_meta_data->>'system_role'='branch_operator') then return false; end if;
  update public.pharmacy_branches
    set member_id = auth.uid()
    where id = p_branch and status='active' and invite_email = confirmed_email
      and owner_id <> auth.uid() and (member_id is null or member_id = auth.uid());
  return found;
end
$$;
revoke all on function pharmacy_branch_private.claim_branch(uuid) from public, anon;
grant execute on function pharmacy_branch_private.claim_branch(uuid) to authenticated;

create function public.pharmacy_claim_branch(p_branch uuid) returns boolean
language sql security invoker set search_path = '' as $$
  select pharmacy_branch_private.claim_branch(p_branch)
$$;
revoke all on function public.pharmacy_claim_branch(uuid) from public, anon;
grant execute on function public.pharmacy_claim_branch(uuid) to authenticated;

create table public.pharmacy_branch_events (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.pharmacy_branches(id),
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
create index pharmacy_branch_events_day_idx on public.pharmacy_branch_events (branch_id, recorded_at desc, id desc);
create index pharmacy_branch_inventory_idx on public.pharmacy_branch_events (branch_id, lower(btrim(reference)), recorded_at desc, id desc) where kind = 'inventory';
alter table public.pharmacy_branch_events enable row level security;
revoke all on public.pharmacy_branch_events from public, anon, authenticated;
grant select, insert (id, branch_id, kind, reference, amount, cash, cost, quantity, reorder_level)
  on public.pharmacy_branch_events to authenticated;
create policy pharmacy_branch_events_read on public.pharmacy_branch_events for select to authenticated using (
  exists (select 1 from public.pharmacy_branches b where b.id = branch_id)
);
create policy pharmacy_branch_events_append on public.pharmacy_branch_events for insert to authenticated with check (
  actor_id = (select auth.uid()) and exists (select 1 from public.pharmacy_branches b where b.id = branch_id)
);

create function public.pharmacy_branch_day(p_day date, p_branch uuid default null) returns jsonb
language sql stable security invoker set search_path = '' as $$
  with branches as (
    select * from public.pharmacy_branches b where p_branch is null or b.id = p_branch
  ), daily as (
    select e.* from public.pharmacy_branch_events e join branches b on b.id = e.branch_id
    where e.recorded_at >= (p_day::timestamp at time zone 'Asia/Damascus')
      and e.recorded_at < ((p_day + 1)::timestamp at time zone 'Asia/Damascus')
  ), balances as (
    select e.branch_id, coalesce(sum(case
      when e.kind in ('sale','deposit') then e.cash else -e.cash end),0) as cash_balance
    from public.pharmacy_branch_events e join branches b on b.id = e.branch_id
    where e.recorded_at < ((p_day + 1)::timestamp at time zone 'Asia/Damascus')
    group by e.branch_id
  ), inventory as (
    select distinct on (e.branch_id, lower(btrim(e.reference))) e.*
    from public.pharmacy_branch_events e join branches b on b.id = e.branch_id
    where e.kind = 'inventory' and e.recorded_at < ((p_day + 1)::timestamp at time zone 'Asia/Damascus')
    order by e.branch_id, lower(btrim(e.reference)), e.recorded_at desc, e.id desc
  ), totals as (
    select b.id, b.name, b.location, b.status, b.invite_email, b.member_id,
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
    from branches b left join daily d on d.branch_id=b.id group by b.id,b.name,b.location,b.status,b.invite_email,b.member_id
  )
  select jsonb_build_object(
    'branches', coalesce((select jsonb_agg(to_jsonb(t) order by t.name,t.id) from totals t),'[]'::jsonb),
    'movements', coalesce((select jsonb_agg(to_jsonb(m) order by m.recorded_at desc,m.id desc) from (
      select * from daily where p_branch is not null order by recorded_at desc,id desc limit 100
    ) m),'[]'::jsonb),
    'inventory', coalesce((select jsonb_agg(to_jsonb(i) order by i.reference) from inventory i where p_branch is not null),'[]'::jsonb)
  )
$$;
revoke all on function public.pharmacy_branch_day(date,uuid) from public, anon;
grant execute on function public.pharmacy_branch_day(date,uuid) to authenticated;




drop policy pharmacy_branch_events_read on public.pharmacy_branch_events;
create policy pharmacy_branch_events_read on public.pharmacy_branch_events for select to authenticated using (
  exists (select 1 from public.pharmacy_branches b where b.id = branch_id and b.owner_id = (select auth.uid()))
);

create table public.pharmacy_branch_suppliers (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.pharmacy_branches(id),
  name text not null check (length(btrim(name)) between 2 and 120),
  phone text check (length(phone) <= 40),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);
create unique index pharmacy_branch_supplier_name on public.pharmacy_branch_suppliers (branch_id, lower(btrim(name)));
alter table public.pharmacy_branch_suppliers enable row level security;
revoke all on public.pharmacy_branch_suppliers from public, anon, authenticated;
grant select, insert (branch_id, name, phone) on public.pharmacy_branch_suppliers to authenticated;
create policy pharmacy_branch_suppliers_read on public.pharmacy_branch_suppliers for select to authenticated using (
  exists (select 1 from public.pharmacy_branches b where b.id = branch_id)
);
create policy pharmacy_branch_suppliers_create on public.pharmacy_branch_suppliers for insert to authenticated with check (
  created_by = (select auth.uid()) and exists (select 1 from public.pharmacy_branches b where b.id = branch_id)
);

create function pharmacy_branch_private.can_operate(p_branch uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.pharmacy_branches b where b.id = p_branch and b.status='active' and (
    (b.owner_id = auth.uid() and pharmacy_branch_private.manager_role() in ('system_admin','system_owner'))
    or (pharmacy_branch_private.manager_role()='branch_operator' and b.member_id = auth.uid() and b.invite_email = pharmacy_branch_private.live_email())
  ))
$$;
revoke all on function pharmacy_branch_private.can_operate(uuid) from public, anon, authenticated;

create function pharmacy_branch_private.operator_day(p_branch uuid, p_day date, p_kinds text[]) returns jsonb
language sql stable security definer set search_path = '' as $$
  with branch as (
    select id, name, location from public.pharmacy_branches where id = p_branch and pharmacy_branch_private.can_operate(p_branch)
  ), movements as (
    select e.id, e.kind, e.reference, e.recorded_at, e.amount, e.cash, e.quantity, e.reorder_level
    from public.pharmacy_branch_events e join branch b on b.id = e.branch_id
    where e.recorded_at >= (p_day::timestamp at time zone 'Asia/Damascus')
      and e.recorded_at < ((p_day + 1)::timestamp at time zone 'Asia/Damascus')
      and e.kind = any(p_kinds)
    order by e.recorded_at desc,e.id desc limit 100
  ), inventory as (
    select distinct on (lower(btrim(e.reference))) e.id, e.reference, e.quantity, e.reorder_level
    from public.pharmacy_branch_events e join branch b on b.id = e.branch_id
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
create function pharmacy_branch_private.event_saved(p_branch uuid,p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select pharmacy_branch_private.can_operate(p_branch) and exists (
    select 1 from public.pharmacy_branch_events e where e.branch_id=p_branch and e.id=p_id and e.actor_id=auth.uid()
  )
$$;
revoke all on function pharmacy_branch_private.operator_day(uuid,date,text[]), pharmacy_branch_private.event_saved(uuid,uuid) from public, anon;
grant execute on function pharmacy_branch_private.operator_day(uuid,date,text[]), pharmacy_branch_private.event_saved(uuid,uuid) to authenticated;

create function public.pharmacy_branch_operator_day(p_branch uuid,p_day date,p_kinds text[]) returns jsonb
language sql security invoker stable set search_path = '' as $$
  select pharmacy_branch_private.operator_day(p_branch,p_day,p_kinds)
$$;
create function public.pharmacy_branch_event_saved(p_branch uuid,p_id uuid) returns boolean
language sql security invoker stable set search_path = '' as $$
  select pharmacy_branch_private.event_saved(p_branch,p_id)
$$;
revoke all on function public.pharmacy_branch_operator_day(uuid,date,text[]), public.pharmacy_branch_event_saved(uuid,uuid) from public, anon;
grant execute on function public.pharmacy_branch_operator_day(uuid,date,text[]), public.pharmacy_branch_event_saved(uuid,uuid) to authenticated;



create table public.pharmacy_branch_permissions (
  branch_id uuid primary key references public.pharmacy_branches(id),
  sections text[] not null check (sections <@ array['dashboard','pos','returns','purchases','inventory','suppliers','cashbox','settings']::text[])
);
alter table public.pharmacy_branch_permissions enable row level security;
revoke all on public.pharmacy_branch_permissions from public,anon,authenticated;
grant select, insert, update on public.pharmacy_branch_permissions to authenticated;
create policy pharmacy_branch_permissions_read on public.pharmacy_branch_permissions for select to authenticated using (
  exists (select 1 from public.pharmacy_branches b where b.id=branch_id)
);
create policy pharmacy_branch_permissions_manage on public.pharmacy_branch_permissions for all to authenticated using (
  exists (select 1 from public.pharmacy_branches b where b.id=branch_id and b.owner_id=(select auth.uid()))
) with check (
  exists (select 1 from public.pharmacy_branches b where b.id=branch_id and b.owner_id=(select auth.uid()))
);

create function pharmacy_branch_private.section_for_kind(p_kind text) returns text
language sql immutable set search_path='' as $$
  select case p_kind when 'sale' then 'pos' when 'return' then 'returns' when 'purchase' then 'purchases'
  when 'inventory' then 'inventory' when 'deposit' then 'cashbox' when 'withdrawal' then 'cashbox' when 'expense' then 'cashbox' end
$$;
create function pharmacy_branch_private.can_section(p_branch uuid,p_section text) returns boolean
language sql stable security definer set search_path='' as $$
  select pharmacy_branch_private.can_operate(p_branch) and exists (
    select 1 from public.pharmacy_branches b left join public.pharmacy_branch_permissions p on p.branch_id=b.id where b.id=p_branch
    and (b.owner_id=auth.uid() or p_section=any(coalesce(p.sections,array['dashboard','pos','returns','purchases','inventory','suppliers','cashbox','settings'])))
  )
$$;
revoke all on function pharmacy_branch_private.can_section(uuid,text),pharmacy_branch_private.section_for_kind(text) from public,anon;
grant execute on function pharmacy_branch_private.can_section(uuid,text),pharmacy_branch_private.section_for_kind(text) to authenticated;

drop policy pharmacy_branch_events_append on public.pharmacy_branch_events;
create policy pharmacy_branch_events_append on public.pharmacy_branch_events for insert to authenticated with check (
  actor_id=(select auth.uid()) and pharmacy_branch_private.can_section(branch_id,pharmacy_branch_private.section_for_kind(kind))
);
drop policy pharmacy_branch_suppliers_read on public.pharmacy_branch_suppliers;
create policy pharmacy_branch_suppliers_read on public.pharmacy_branch_suppliers for select to authenticated using (
  pharmacy_branch_private.can_section(branch_id,'suppliers')
);
drop policy pharmacy_branch_suppliers_create on public.pharmacy_branch_suppliers;
create policy pharmacy_branch_suppliers_create on public.pharmacy_branch_suppliers for insert to authenticated with check (
  created_by=(select auth.uid()) and pharmacy_branch_private.can_section(branch_id,'suppliers')
);

-- The original private function must also enforce permissions for authenticated SQL callers.
alter function pharmacy_branch_private.operator_day(uuid,date,text[]) rename to operator_day_data;
revoke all on function pharmacy_branch_private.operator_day_data(uuid,date,text[]) from public,anon,authenticated;
create function pharmacy_branch_private.operator_day(p_branch uuid,p_day date,p_kinds text[]) returns jsonb
language sql stable security definer set search_path='' as $$
  select pharmacy_branch_private.operator_day_data(p_branch,p_day,array(
    select k from unnest(p_kinds) k where pharmacy_branch_private.can_section(p_branch,pharmacy_branch_private.section_for_kind(k))
  ))
$$;
revoke all on function pharmacy_branch_private.operator_day(uuid,date,text[]) from public,anon;
grant execute on function pharmacy_branch_private.operator_day(uuid,date,text[]) to authenticated;
create or replace function public.pharmacy_branch_operator_day(p_branch uuid,p_day date,p_kinds text[]) returns jsonb
language sql security invoker stable set search_path='' as $$
  select pharmacy_branch_private.operator_day(p_branch,p_day,p_kinds)
$$;

create table public.pharmacy_branch_invoice_requests (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.pharmacy_branches(id),
  event_id uuid not null,
  action text not null check(action in ('edit','delete')),
  reason text not null check(length(btrim(reason)) between 3 and 250),
  new_reference text check(length(btrim(new_reference)) between 1 and 160),
  new_amount bigint check(new_amount between 1 and 1000000000000),
  new_cash bigint check(new_cash between 0 and new_amount),
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  requested_by uuid not null default auth.uid(),
  requested_at timestamptz not null default now(),
  decided_by uuid,
  decided_at timestamptz,
  before_data jsonb not null,
  invoice_reference text generated always as (before_data->>'reference') stored,
  invoice_amount bigint generated always as ((before_data->>'amount')::bigint) stored,
  invoice_cash bigint generated always as ((before_data->>'cash')::bigint) stored,
  check ((action='delete' and new_reference is null and new_amount is null and new_cash is null)
    or (action='edit' and new_reference is not null and new_amount is not null and new_cash is not null))
);
create unique index pharmacy_branch_invoice_pending on public.pharmacy_branch_invoice_requests(event_id) where status='pending';
create index pharmacy_branch_invoice_requests_branch on public.pharmacy_branch_invoice_requests(branch_id,requested_at desc);
alter table public.pharmacy_branch_invoice_requests enable row level security;
revoke all on public.pharmacy_branch_invoice_requests from public,anon,authenticated;
grant select(id,branch_id,event_id,action,reason,new_reference,new_amount,new_cash,status,requested_by,requested_at,decided_by,decided_at,invoice_reference,invoice_amount,invoice_cash)
  on public.pharmacy_branch_invoice_requests to authenticated;
create policy pharmacy_branch_invoice_requests_read on public.pharmacy_branch_invoice_requests for select to authenticated using (
  exists (select 1 from public.pharmacy_branches b where b.id=branch_id and (b.owner_id=(select auth.uid()) or requested_by=(select auth.uid())))
);

create function pharmacy_branch_private.request_invoice(p_branch uuid,p_event uuid,p_action text,p_reason text,p_reference text,p_amount bigint,p_cash bigint) returns uuid
language plpgsql security definer set search_path='' as $$
declare invoice public.pharmacy_branch_events%rowtype; request_id uuid;
begin
  select * into invoice from public.pharmacy_branch_events
  where id=p_event and branch_id=p_branch and kind in ('sale','purchase','return');
  if not found or not pharmacy_branch_private.can_section(p_branch,pharmacy_branch_private.section_for_kind(invoice.kind)) then
    raise exception 'invoice unavailable' using errcode='42501';
  end if;
  insert into public.pharmacy_branch_invoice_requests(branch_id,event_id,action,reason,new_reference,new_amount,new_cash,before_data)
  values(p_branch,p_event,p_action,btrim(p_reason),btrim(p_reference),p_amount,p_cash,to_jsonb(invoice))
  returning id into request_id;
  return request_id;
end
$$;

create function pharmacy_branch_private.decide_invoice(p_request uuid,p_approve boolean) returns text
language plpgsql security definer set search_path='' as $$
declare req public.pharmacy_branch_invoice_requests%rowtype; current_invoice jsonb; decision text;
begin
  if p_approve is null then raise exception 'missing decision'; end if;
  select r.* into req from public.pharmacy_branch_invoice_requests r join public.pharmacy_branches b on b.id=r.branch_id
  where r.id=p_request and b.owner_id=auth.uid() and pharmacy_branch_private.manager_role() in ('system_owner','system_admin') for update of r;
  if not found then raise exception 'request unavailable' using errcode='42501'; end if;
  if req.status<>'pending' then return req.status; end if;
  decision := case when p_approve then 'approved' else 'rejected' end;
  if p_approve then
    select to_jsonb(e) into current_invoice from public.pharmacy_branch_events e where e.id=req.event_id and e.branch_id=req.branch_id for update;
    if current_invoice is distinct from req.before_data then raise exception 'invoice changed'; end if;
    if req.action='edit' then
      update public.pharmacy_branch_events set reference=req.new_reference,amount=req.new_amount,cash=req.new_cash where id=req.event_id;
    else
      delete from public.pharmacy_branch_events where id=req.event_id;
    end if;
  end if;
  update public.pharmacy_branch_invoice_requests set status=decision,decided_by=auth.uid(),decided_at=now() where id=req.id;
  return decision;
end
$$;
revoke all on function pharmacy_branch_private.request_invoice(uuid,uuid,text,text,text,bigint,bigint),pharmacy_branch_private.decide_invoice(uuid,boolean) from public,anon;
grant execute on function pharmacy_branch_private.request_invoice(uuid,uuid,text,text,text,bigint,bigint),pharmacy_branch_private.decide_invoice(uuid,boolean) to authenticated;

create function public.pharmacy_branch_request_invoice(p_branch uuid,p_event uuid,p_action text,p_reason text,p_reference text,p_amount bigint,p_cash bigint) returns uuid
language sql security invoker set search_path='' as $$
  select pharmacy_branch_private.request_invoice(p_branch,p_event,p_action,p_reason,p_reference,p_amount,p_cash)
$$;
create function public.pharmacy_branch_decide_invoice(p_request uuid,p_approve boolean) returns text
language sql security invoker set search_path='' as $$
  select pharmacy_branch_private.decide_invoice(p_request,p_approve)
$$;
revoke all on function public.pharmacy_branch_request_invoice(uuid,uuid,text,text,text,bigint,bigint),public.pharmacy_branch_decide_invoice(uuid,boolean) from public,anon;
grant execute on function public.pharmacy_branch_request_invoice(uuid,uuid,text,text,text,bigint,bigint),public.pharmacy_branch_decide_invoice(uuid,boolean) to authenticated;



alter table public.pharmacy_branch_permissions drop constraint pharmacy_branch_permissions_sections_check;
alter table public.pharmacy_branch_permissions add check (
  sections <@ array['dashboard','dashboardProfit','pos','returns','purchases','inventory','suppliers','cashbox','settings']::text[]
);

create table public.pharmacy_branch_catalog (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.pharmacy_branches(id),
  barcode text not null check (length(btrim(barcode)) between 1 and 60),
  name text not null check (length(btrim(name)) between 2 and 160),
  stock integer not null check (stock between 0 and 100000000),
  sale_price bigint not null check (sale_price between 1 and 1000000000000),
  unit_cost bigint not null check (unit_cost between 0 and 1000000000000),
  unique(branch_id,barcode)
);
alter table public.pharmacy_branch_catalog enable row level security;
revoke all on public.pharmacy_branch_catalog from public,anon,authenticated;
grant select,insert,update on public.pharmacy_branch_catalog to authenticated;
create policy pharmacy_branch_catalog_owner on public.pharmacy_branch_catalog for all to authenticated using (
  exists(select 1 from public.pharmacy_branches b where b.id=branch_id and b.owner_id=(select auth.uid()))
) with check (
  exists(select 1 from public.pharmacy_branches b where b.id=branch_id and b.owner_id=(select auth.uid()))
);

create table pharmacy_branch_private.pos_sales (
  id uuid primary key,
  branch_id uuid not null references public.pharmacy_branches(id),
  actor_id uuid not null,
  items jsonb not null,
  receipt jsonb not null,
  canceled boolean not null default false
);
alter table pharmacy_branch_private.pos_sales enable row level security;
revoke all on pharmacy_branch_private.pos_sales from public,anon,authenticated;

create function pharmacy_branch_private.pos_search(p_branch uuid,p_query text,p_exact boolean) returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(to_jsonb(p) order by p.name,p.barcode),'[]'::jsonb)
  from (select id,barcode,name,stock,sale_price,1 as parts_per_unit,'SYP'::text as sale_currency
    from public.pharmacy_branch_catalog where branch_id=p_branch and pharmacy_branch_private.can_section(p_branch,'pos')
      and case when p_exact then barcode=btrim(p_query)
        else strpos(lower(name),lower(btrim(p_query)))>0 or strpos(lower(barcode),lower(btrim(p_query)))>0 end
    order by name,barcode limit 30) p
$$;

create function pharmacy_branch_private.pos_complete(p_branch uuid,p_id uuid,p_items jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare previous pharmacy_branch_private.pos_sales%rowtype; product public.pharmacy_branch_catalog%rowtype;
 item record; lines jsonb:='[]'; total numeric:=0; cost_total numeric:=0; qty integer; receipt jsonb;
begin
  if not pharmacy_branch_private.can_section(p_branch,'pos') then raise exception 'صلاحية البيع غير متاحة' using errcode='42501'; end if;
  if p_id is null or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'الفاتورة فارغة أو تتجاوز الحد';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
  select * into previous from pharmacy_branch_private.pos_sales where id=p_id;
  if found then
    if previous.branch_id=p_branch and previous.actor_id=auth.uid() and previous.items=p_items and not previous.canceled then
      return previous.receipt;
    end if;
    raise exception 'تعذر إعادة استخدام رقم العملية';
  end if;
  for item in select * from jsonb_to_recordset(p_items) as x(product_id uuid,quantity numeric,unit_price numeric) order by product_id loop
    if item.quantity is null or item.quantity<>trunc(item.quantity) or item.quantity not between 1 and 100000000 then
      raise exception 'أدخل كمية صحيحة من العبوات';
    end if;
    qty:=item.quantity::integer;
    select * into product from public.pharmacy_branch_catalog where id=item.product_id and branch_id=p_branch for update;
    if not found or product.stock<qty then raise exception 'الرصيد غير متاح في هذا الفرع'; end if;
    if product.sale_price is distinct from item.unit_price then raise exception 'تغير سعر الصنف. أعد إضافته إلى الفاتورة'; end if;
    total:=total+product.sale_price*qty::numeric;
    cost_total:=cost_total+product.unit_cost*qty::numeric;
    lines:=lines||jsonb_build_array(jsonb_build_object('product_id',product.id,'product_name',product.name,'barcode',product.barcode,
      'quantity',qty,'unit_price',product.sale_price,'line_total',product.sale_price*qty::numeric));
    update public.pharmacy_branch_catalog set stock=stock-qty where id=product.id;
  end loop;
  insert into public.pharmacy_branch_events(id,branch_id,kind,reference,amount,cash,cost)
    values(p_id,p_branch,'sale','POS-'||left(p_id::text,8),total,total,cost_total);
  receipt:=jsonb_build_object('id',p_id,'total',total,'items',lines);
  insert into pharmacy_branch_private.pos_sales values(p_id,p_branch,auth.uid(),p_items,receipt,false);
  return receipt;
end
$$;

create function pharmacy_branch_private.pos_invoice_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare sale pharmacy_branch_private.pos_sales%rowtype; line record;
begin
  select * into sale from pharmacy_branch_private.pos_sales where id=old.id and branch_id=old.branch_id;
  if not found then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  if tg_op='UPDATE' then
    if (new.amount,new.cash,new.cost) is distinct from (old.amount,old.cash,old.cost) then
      raise exception 'يمكن تعديل مرجع فاتورة الكاشير فقط';
    end if;
    return new;
  end if;
  for line in select product_id,sum(quantity)::integer as quantity
    from jsonb_to_recordset(sale.receipt->'items') as x(product_id uuid,quantity integer)
    group by product_id order by product_id loop
    update public.pharmacy_branch_catalog set stock=stock+line.quantity where branch_id=old.branch_id and id=line.product_id;
    if not found then raise exception 'تعذر عكس المخزون'; end if;
  end loop;
  update pharmacy_branch_private.pos_sales set canceled=true where id=old.id;
  return old;
end
$$;
create trigger pharmacy_branch_pos_invoice_change before update or delete on public.pharmacy_branch_events
  for each row execute function pharmacy_branch_private.pos_invoice_change();

drop policy pharmacy_branch_events_append on public.pharmacy_branch_events;
create policy pharmacy_branch_events_append on public.pharmacy_branch_events for insert to authenticated with check (
  kind<>'sale' and actor_id=(select auth.uid()) and pharmacy_branch_private.can_section(branch_id,pharmacy_branch_private.section_for_kind(kind))
);

create or replace function pharmacy_branch_private.operator_day(p_branch uuid,p_day date,p_kinds text[]) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare payload jsonb; movements jsonb; inventory jsonb;
begin
  payload:=pharmacy_branch_private.operator_day_data(p_branch,p_day,array(
    select k from unnest(p_kinds) k where pharmacy_branch_private.can_section(p_branch,pharmacy_branch_private.section_for_kind(k))
  ));
  select coalesce(jsonb_agg(case when s.id is null then m.value else m.value||jsonb_build_object('items',s.receipt->'items') end order by m.ordinality),'[]'::jsonb)
    into movements from jsonb_array_elements(payload->'movements') with ordinality m
    left join pharmacy_branch_private.pos_sales s on s.branch_id=p_branch and s.id=(m.value->>'id')::uuid;
  payload:=jsonb_set(payload,'{movements}',movements);
  if p_day=(now() at time zone 'Asia/Damascus')::date and 'inventory'=any(p_kinds)
    and pharmacy_branch_private.can_section(p_branch,'inventory') then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'reference',name||' · '||barcode,'quantity',stock,'reorder_level',1) order by name),'[]'::jsonb)
      into inventory from public.pharmacy_branch_catalog where branch_id=p_branch;
    payload:=jsonb_set(payload,'{inventory}',payload->'inventory'||inventory);
  end if;
  return payload;
end
$$;

create function pharmacy_branch_private.dashboard(p_branch uuid,p_day date) returns jsonb
language sql stable security definer set search_path='' as $$
  with rights as (
    select pharmacy_branch_private.can_section(p_branch,'dashboard') as dashboard,
      pharmacy_branch_private.can_section(p_branch,'dashboardProfit') as profit,
      pharmacy_branch_private.can_section(p_branch,'pos') as sales,
      pharmacy_branch_private.can_section(p_branch,'inventory') as stock,
      pharmacy_branch_private.can_section(p_branch,'returns') as return_access,
      pharmacy_branch_private.can_section(p_branch,'purchases') as purchase_access,
      pharmacy_branch_private.can_section(p_branch,'cashbox') as cash_access
  ), days as (
    select p_day-i as day from generate_series(0,6) i
  ), totals as (
    select d.day, coalesce(sum(e.amount) filter(where e.kind='sale'),0) as sales,
      coalesce(sum(e.amount) filter(where e.kind='return'),0) as returns,
      count(e.id) filter(where e.kind='sale') as invoice_count,
      coalesce(sum(e.amount) filter(where e.kind='purchase'),0) as purchases,
      coalesce(sum(e.cash) filter(where e.kind in ('sale','deposit')),0) as cash_in,
      coalesce(sum(e.cash) filter(where e.kind in ('return','purchase','expense','withdrawal')),0) as cash_out,
      coalesce(sum(case e.kind when 'sale' then e.amount-e.cost when 'return' then e.cost-e.amount when 'expense' then -e.amount else 0 end),0) as profit
    from days d left join public.pharmacy_branch_events e on e.branch_id=p_branch
      and e.recorded_at >= (d.day::timestamp at time zone 'Asia/Damascus')
      and e.recorded_at < ((d.day+1)::timestamp at time zone 'Asia/Damascus')
    group by d.day
  )
  select case when r.dashboard then jsonb_build_object(
    'sales',case when r.sales then t.sales end,'netSales',case when r.sales and r.return_access then t.sales-t.returns end,
    'profit',case when r.profit then t.profit end,
    'invoice_count',case when r.sales then t.invoice_count end,
    'purchases',case when r.purchase_access then t.purchases end,
    'customer_returns',case when r.return_access then t.returns end,
    'cash_in',case when r.cash_access and r.sales then t.cash_in end,
    'cash_out',case when r.cash_access and r.return_access and r.purchase_access then t.cash_out end,
    'products',case when r.stock then (select count(*) from public.pharmacy_branch_catalog where branch_id=p_branch) end,
    'low',case when r.stock then (select count(*) from public.pharmacy_branch_catalog where branch_id=p_branch and stock<=1) end,
    'chart',case when r.sales then (select jsonb_agg(jsonb_build_object('dateKey',day,'value',sales) order by day) from totals) else '[]'::jsonb end
  ) end from totals t cross join rights r where t.day=p_day
$$;

revoke all on function pharmacy_branch_private.pos_invoice_change() from public,anon,authenticated;
revoke all on function pharmacy_branch_private.pos_search(uuid,text,boolean),pharmacy_branch_private.pos_complete(uuid,uuid,jsonb),pharmacy_branch_private.dashboard(uuid,date) from public,anon;
grant execute on function pharmacy_branch_private.pos_search(uuid,text,boolean),pharmacy_branch_private.pos_complete(uuid,uuid,jsonb),pharmacy_branch_private.dashboard(uuid,date) to authenticated;
create function public.pharmacy_branch_pos_search(p_branch uuid,p_query text,p_exact boolean default false) returns jsonb
language sql stable security invoker set search_path='' as $$ select pharmacy_branch_private.pos_search(p_branch,p_query,p_exact) $$;
create function public.pharmacy_branch_pos_complete(p_branch uuid,p_id uuid,p_items jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select pharmacy_branch_private.pos_complete(p_branch,p_id,p_items) $$;
create function public.pharmacy_branch_dashboard(p_branch uuid,p_day date) returns jsonb
language sql stable security invoker set search_path='' as $$ select pharmacy_branch_private.dashboard(p_branch,p_day) $$;
revoke all on function public.pharmacy_branch_pos_search(uuid,text,boolean),public.pharmacy_branch_pos_complete(uuid,uuid,jsonb),public.pharmacy_branch_dashboard(uuid,date) from public,anon;
grant execute on function public.pharmacy_branch_pos_search(uuid,text,boolean),public.pharmacy_branch_pos_complete(uuid,uuid,jsonb),public.pharmacy_branch_dashboard(uuid,date) to authenticated;



create function public.pharmacy_branch_update(p_branch uuid,p_name text,p_status text,p_expected_name text,p_expected_status text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if pharmacy_branch_private.manager_role() in ('system_admin','system_owner') then
    update public.pharmacy_branches set name=btrim(p_name),status=p_status
    where id=p_branch and owner_id=auth.uid() and name=p_expected_name and status=p_expected_status;
    if found then return; end if;
  end if;
  raise exception 'Branch unavailable or changed';
end $$;
revoke all on function public.pharmacy_branch_update(uuid,text,text,text,text) from public,anon,authenticated;
grant execute on function public.pharmacy_branch_update(uuid,text,text,text,text) to authenticated;
