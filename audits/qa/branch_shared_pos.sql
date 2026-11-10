begin;
alter table public.qa_branch_permissions drop constraint qa_branch_permissions_sections_check;
alter table public.qa_branch_permissions add check (
  sections <@ array['dashboard','dashboardProfit','pos','returns','purchases','inventory','suppliers','cashbox','settings']::text[]
);

create table public.qa_branch_catalog (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.qa_branches(id),
  barcode text not null check (length(btrim(barcode)) between 1 and 60),
  name text not null check (length(btrim(name)) between 2 and 160),
  stock integer not null check (stock between 0 and 100000000),
  sale_price bigint not null check (sale_price between 1 and 1000000000000),
  unit_cost bigint not null check (unit_cost between 0 and 1000000000000),
  unique(branch_id,barcode)
);
alter table public.qa_branch_catalog enable row level security;
revoke all on public.qa_branch_catalog from public,anon,authenticated;
grant select,insert,update on public.qa_branch_catalog to authenticated;
create policy qa_branch_catalog_owner on public.qa_branch_catalog for all to authenticated using (
  exists(select 1 from public.qa_branches b where b.id=branch_id and b.owner_id=(select auth.uid()))
) with check (
  exists(select 1 from public.qa_branches b where b.id=branch_id and b.owner_id=(select auth.uid()))
);

create table qa_branch_private.pos_sales (
  id uuid primary key,
  branch_id uuid not null references public.qa_branches(id),
  actor_id uuid not null,
  items jsonb not null,
  receipt jsonb not null,
  canceled boolean not null default false
);
alter table qa_branch_private.pos_sales enable row level security;
revoke all on qa_branch_private.pos_sales from public,anon,authenticated;

create function qa_branch_private.pos_search(p_branch uuid,p_query text,p_exact boolean) returns jsonb
language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(to_jsonb(p) order by p.name,p.barcode),'[]'::jsonb)
  from (select id,barcode,name,stock,sale_price,1 as parts_per_unit,'SYP'::text as sale_currency
    from public.qa_branch_catalog where branch_id=p_branch and qa_branch_private.can_section(p_branch,'pos')
      and case when p_exact then barcode=btrim(p_query)
        else strpos(lower(name),lower(btrim(p_query)))>0 or strpos(lower(barcode),lower(btrim(p_query)))>0 end
    order by name,barcode limit 30) p
$$;

create function qa_branch_private.pos_complete(p_branch uuid,p_id uuid,p_items jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare previous qa_branch_private.pos_sales%rowtype; product public.qa_branch_catalog%rowtype;
 item record; lines jsonb:='[]'; total numeric:=0; cost_total numeric:=0; qty integer; receipt jsonb;
begin
  if not qa_branch_private.can_section(p_branch,'pos') then raise exception 'صلاحية البيع غير متاحة' using errcode='42501'; end if;
  if p_id is null or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'الفاتورة فارغة أو تتجاوز الحد';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
  select * into previous from qa_branch_private.pos_sales where id=p_id;
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
    select * into product from public.qa_branch_catalog where id=item.product_id and branch_id=p_branch for update;
    if not found or product.stock<qty then raise exception 'الرصيد غير متاح في هذا الفرع'; end if;
    if product.sale_price is distinct from item.unit_price then raise exception 'تغير سعر الصنف. أعد إضافته إلى الفاتورة'; end if;
    total:=total+product.sale_price*qty::numeric;
    cost_total:=cost_total+product.unit_cost*qty::numeric;
    lines:=lines||jsonb_build_array(jsonb_build_object('product_id',product.id,'product_name',product.name,'barcode',product.barcode,
      'quantity',qty,'unit_price',product.sale_price,'line_total',product.sale_price*qty::numeric));
    update public.qa_branch_catalog set stock=stock-qty where id=product.id;
  end loop;
  insert into public.qa_branch_events(id,branch_id,kind,reference,amount,cash,cost)
    values(p_id,p_branch,'sale','POS-'||left(p_id::text,8),total,total,cost_total);
  receipt:=jsonb_build_object('id',p_id,'total',total,'items',lines);
  insert into qa_branch_private.pos_sales values(p_id,p_branch,auth.uid(),p_items,receipt,false);
  return receipt;
end
$$;

create function qa_branch_private.pos_invoice_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare sale qa_branch_private.pos_sales%rowtype; line record;
begin
  select * into sale from qa_branch_private.pos_sales where id=old.id and branch_id=old.branch_id;
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
    update public.qa_branch_catalog set stock=stock+line.quantity where branch_id=old.branch_id and id=line.product_id;
    if not found then raise exception 'تعذر عكس المخزون'; end if;
  end loop;
  update qa_branch_private.pos_sales set canceled=true where id=old.id;
  return old;
end
$$;
create trigger qa_branch_pos_invoice_change before update or delete on public.qa_branch_events
  for each row execute function qa_branch_private.pos_invoice_change();

drop policy qa_branch_events_append on public.qa_branch_events;
create policy qa_branch_events_append on public.qa_branch_events for insert to authenticated with check (
  kind<>'sale' and actor_id=(select auth.uid()) and qa_branch_private.can_section(branch_id,qa_branch_private.section_for_kind(kind))
);

create or replace function qa_branch_private.operator_day(p_branch uuid,p_day date,p_kinds text[]) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare payload jsonb; movements jsonb; inventory jsonb;
begin
  payload:=qa_branch_private.operator_day_data(p_branch,p_day,array(
    select k from unnest(p_kinds) k where qa_branch_private.can_section(p_branch,qa_branch_private.section_for_kind(k))
  ));
  select coalesce(jsonb_agg(case when s.id is null then m.value else m.value||jsonb_build_object('items',s.receipt->'items') end order by m.ordinality),'[]'::jsonb)
    into movements from jsonb_array_elements(payload->'movements') with ordinality m
    left join qa_branch_private.pos_sales s on s.branch_id=p_branch and s.id=(m.value->>'id')::uuid;
  payload:=jsonb_set(payload,'{movements}',movements);
  if p_day=(now() at time zone 'Asia/Damascus')::date and 'inventory'=any(p_kinds)
    and qa_branch_private.can_section(p_branch,'inventory') then
    select coalesce(jsonb_agg(jsonb_build_object('id',id,'reference',name||' · '||barcode,'quantity',stock,'reorder_level',1) order by name),'[]'::jsonb)
      into inventory from public.qa_branch_catalog where branch_id=p_branch;
    payload:=jsonb_set(payload,'{inventory}',payload->'inventory'||inventory);
  end if;
  return payload;
end
$$;

create function qa_branch_private.dashboard(p_branch uuid,p_day date) returns jsonb
language sql stable security definer set search_path='' as $$
  with rights as (
    select qa_branch_private.can_section(p_branch,'dashboard') as dashboard,
      qa_branch_private.can_section(p_branch,'dashboardProfit') as profit,
      qa_branch_private.can_section(p_branch,'pos') as sales,
      qa_branch_private.can_section(p_branch,'inventory') as stock,
      qa_branch_private.can_section(p_branch,'returns') as return_access,
      qa_branch_private.can_section(p_branch,'purchases') as purchase_access,
      qa_branch_private.can_section(p_branch,'cashbox') as cash_access
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
    from days d left join public.qa_branch_events e on e.branch_id=p_branch
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
    'products',case when r.stock then (select count(*) from public.qa_branch_catalog where branch_id=p_branch) end,
    'low',case when r.stock then (select count(*) from public.qa_branch_catalog where branch_id=p_branch and stock<=1) end,
    'chart',case when r.sales then (select jsonb_agg(jsonb_build_object('dateKey',day,'value',sales) order by day) from totals) else '[]'::jsonb end
  ) end from totals t cross join rights r where t.day=p_day
$$;

revoke all on function qa_branch_private.pos_invoice_change() from public,anon,authenticated;
revoke all on function qa_branch_private.pos_search(uuid,text,boolean),qa_branch_private.pos_complete(uuid,uuid,jsonb),qa_branch_private.dashboard(uuid,date) from public,anon;
grant execute on function qa_branch_private.pos_search(uuid,text,boolean),qa_branch_private.pos_complete(uuid,uuid,jsonb),qa_branch_private.dashboard(uuid,date) to authenticated;
create function public.qa_branch_pos_search(p_branch uuid,p_query text,p_exact boolean default false) returns jsonb
language sql stable security invoker set search_path='' as $$ select qa_branch_private.pos_search(p_branch,p_query,p_exact) $$;
create function public.qa_branch_pos_complete(p_branch uuid,p_id uuid,p_items jsonb) returns jsonb
language sql security invoker set search_path='' as $$ select qa_branch_private.pos_complete(p_branch,p_id,p_items) $$;
create function public.qa_branch_dashboard(p_branch uuid,p_day date) returns jsonb
language sql stable security invoker set search_path='' as $$ select qa_branch_private.dashboard(p_branch,p_day) $$;
revoke all on function public.qa_branch_pos_search(uuid,text,boolean),public.qa_branch_pos_complete(uuid,uuid,jsonb),public.qa_branch_dashboard(uuid,date) from public,anon;
grant execute on function public.qa_branch_pos_search(uuid,text,boolean),public.qa_branch_pos_complete(uuid,uuid,jsonb),public.qa_branch_dashboard(uuid,date) to authenticated;
commit;
