begin;
create table public.qa_branch_permissions (
  branch_id uuid primary key references public.qa_branches(id),
  sections text[] not null check (sections <@ array['dashboard','pos','returns','purchases','inventory','suppliers','cashbox','settings']::text[])
);
alter table public.qa_branch_permissions enable row level security;
revoke all on public.qa_branch_permissions from public,anon,authenticated;
grant select, insert, update on public.qa_branch_permissions to authenticated;
create policy qa_branch_permissions_read on public.qa_branch_permissions for select to authenticated using (
  exists (select 1 from public.qa_branches b where b.id=branch_id)
);
create policy qa_branch_permissions_manage on public.qa_branch_permissions for all to authenticated using (
  exists (select 1 from public.qa_branches b where b.id=branch_id and b.owner_id=(select auth.uid()))
) with check (
  exists (select 1 from public.qa_branches b where b.id=branch_id and b.owner_id=(select auth.uid()))
);

create function qa_branch_private.section_for_kind(p_kind text) returns text
language sql immutable set search_path='' as $$
  select case p_kind when 'sale' then 'pos' when 'return' then 'returns' when 'purchase' then 'purchases'
  when 'inventory' then 'inventory' when 'deposit' then 'cashbox' when 'withdrawal' then 'cashbox' when 'expense' then 'cashbox' end
$$;
create function qa_branch_private.can_section(p_branch uuid,p_section text) returns boolean
language sql stable security definer set search_path='' as $$
  select qa_branch_private.can_operate(p_branch) and exists (
    select 1 from public.qa_branches b left join public.qa_branch_permissions p on p.branch_id=b.id where b.id=p_branch
    and (b.owner_id=auth.uid() or p_section=any(coalesce(p.sections,array['dashboard','pos','returns','purchases','inventory','suppliers','cashbox','settings'])))
  )
$$;
revoke all on function qa_branch_private.can_section(uuid,text),qa_branch_private.section_for_kind(text) from public,anon;
grant execute on function qa_branch_private.can_section(uuid,text),qa_branch_private.section_for_kind(text) to authenticated;

drop policy qa_branch_events_append on public.qa_branch_events;
create policy qa_branch_events_append on public.qa_branch_events for insert to authenticated with check (
  actor_id=(select auth.uid()) and qa_branch_private.can_section(branch_id,qa_branch_private.section_for_kind(kind))
);
drop policy qa_branch_suppliers_read on public.qa_branch_suppliers;
create policy qa_branch_suppliers_read on public.qa_branch_suppliers for select to authenticated using (
  qa_branch_private.can_section(branch_id,'suppliers')
);
drop policy qa_branch_suppliers_create on public.qa_branch_suppliers;
create policy qa_branch_suppliers_create on public.qa_branch_suppliers for insert to authenticated with check (
  created_by=(select auth.uid()) and qa_branch_private.can_section(branch_id,'suppliers')
);

-- The original private function must also enforce permissions for authenticated SQL callers.
alter function qa_branch_private.operator_day(uuid,date,text[]) rename to operator_day_data;
revoke all on function qa_branch_private.operator_day_data(uuid,date,text[]) from public,anon,authenticated;
create function qa_branch_private.operator_day(p_branch uuid,p_day date,p_kinds text[]) returns jsonb
language sql stable security definer set search_path='' as $$
  select qa_branch_private.operator_day_data(p_branch,p_day,array(
    select k from unnest(p_kinds) k where qa_branch_private.can_section(p_branch,qa_branch_private.section_for_kind(k))
  ))
$$;
revoke all on function qa_branch_private.operator_day(uuid,date,text[]) from public,anon;
grant execute on function qa_branch_private.operator_day(uuid,date,text[]) to authenticated;
create or replace function public.qa_branch_operator_day(p_branch uuid,p_day date,p_kinds text[]) returns jsonb
language sql security invoker stable set search_path='' as $$
  select qa_branch_private.operator_day(p_branch,p_day,p_kinds)
$$;

create table public.qa_branch_invoice_requests (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.qa_branches(id),
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
create unique index qa_branch_invoice_pending on public.qa_branch_invoice_requests(event_id) where status='pending';
create index qa_branch_invoice_requests_branch on public.qa_branch_invoice_requests(branch_id,requested_at desc);
alter table public.qa_branch_invoice_requests enable row level security;
revoke all on public.qa_branch_invoice_requests from public,anon,authenticated;
grant select(id,branch_id,event_id,action,reason,new_reference,new_amount,new_cash,status,requested_by,requested_at,decided_by,decided_at,invoice_reference,invoice_amount,invoice_cash)
  on public.qa_branch_invoice_requests to authenticated;
create policy qa_branch_invoice_requests_read on public.qa_branch_invoice_requests for select to authenticated using (
  exists (select 1 from public.qa_branches b where b.id=branch_id and (b.owner_id=(select auth.uid()) or requested_by=(select auth.uid())))
);

create function qa_branch_private.request_invoice(p_branch uuid,p_event uuid,p_action text,p_reason text,p_reference text,p_amount bigint,p_cash bigint) returns uuid
language plpgsql security definer set search_path='' as $$
declare invoice public.qa_branch_events%rowtype; request_id uuid;
begin
  select * into invoice from public.qa_branch_events
  where id=p_event and branch_id=p_branch and kind in ('sale','purchase','return');
  if not found or not qa_branch_private.can_section(p_branch,qa_branch_private.section_for_kind(invoice.kind)) then
    raise exception 'invoice unavailable' using errcode='42501';
  end if;
  insert into public.qa_branch_invoice_requests(branch_id,event_id,action,reason,new_reference,new_amount,new_cash,before_data)
  values(p_branch,p_event,p_action,btrim(p_reason),btrim(p_reference),p_amount,p_cash,to_jsonb(invoice))
  returning id into request_id;
  return request_id;
end
$$;

create function qa_branch_private.decide_invoice(p_request uuid,p_approve boolean) returns text
language plpgsql security definer set search_path='' as $$
declare req public.qa_branch_invoice_requests%rowtype; current_invoice jsonb; decision text;
begin
  if p_approve is null then raise exception 'missing decision'; end if;
  select r.* into req from public.qa_branch_invoice_requests r join public.qa_branches b on b.id=r.branch_id
  where r.id=p_request and b.owner_id=auth.uid() and public.qa_current_system_role() in ('system_owner','system_admin') for update of r;
  if not found then raise exception 'request unavailable' using errcode='42501'; end if;
  if req.status<>'pending' then return req.status; end if;
  decision := case when p_approve then 'approved' else 'rejected' end;
  if p_approve then
    select to_jsonb(e) into current_invoice from public.qa_branch_events e where e.id=req.event_id and e.branch_id=req.branch_id for update;
    if current_invoice is distinct from req.before_data then raise exception 'invoice changed'; end if;
    if req.action='edit' then
      update public.qa_branch_events set reference=req.new_reference,amount=req.new_amount,cash=req.new_cash where id=req.event_id;
    else
      delete from public.qa_branch_events where id=req.event_id;
    end if;
  end if;
  update public.qa_branch_invoice_requests set status=decision,decided_by=auth.uid(),decided_at=now() where id=req.id;
  return decision;
end
$$;
revoke all on function qa_branch_private.request_invoice(uuid,uuid,text,text,text,bigint,bigint),qa_branch_private.decide_invoice(uuid,boolean) from public,anon;
grant execute on function qa_branch_private.request_invoice(uuid,uuid,text,text,text,bigint,bigint),qa_branch_private.decide_invoice(uuid,boolean) to authenticated;

create function public.qa_branch_request_invoice(p_branch uuid,p_event uuid,p_action text,p_reason text,p_reference text,p_amount bigint,p_cash bigint) returns uuid
language sql security invoker set search_path='' as $$
  select qa_branch_private.request_invoice(p_branch,p_event,p_action,p_reason,p_reference,p_amount,p_cash)
$$;
create function public.qa_branch_decide_invoice(p_request uuid,p_approve boolean) returns text
language sql security invoker set search_path='' as $$
  select qa_branch_private.decide_invoice(p_request,p_approve)
$$;
revoke all on function public.qa_branch_request_invoice(uuid,uuid,text,text,text,bigint,bigint),public.qa_branch_decide_invoice(uuid,boolean) from public,anon;
grant execute on function public.qa_branch_request_invoice(uuid,uuid,text,text,text,bigint,bigint),public.qa_branch_decide_invoice(uuid,boolean) to authenticated;
commit;
