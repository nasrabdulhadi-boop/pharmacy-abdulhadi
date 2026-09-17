-- Pharmacy Abdelhadi v1.4
-- Atomic POS + FEFO foundation.
-- IMPORTANT: review exact existing column names before applying to a live DB.

create or replace function public.is_admin()
returns boolean
language sql
stable
as $$
  select coalesce(auth.jwt()->'app_metadata'->>'role','') = 'admin';
$$;

-- Generic validation function used by integration tests.
create or replace function public.validate_sale_quantity(
  requested_qty integer,
  available_qty integer
)
returns boolean
language sql
immutable
as $$
  select requested_qty > 0 and available_qty >= requested_qty;
$$;

-- FEFO selection helper.
-- Returns batches with positive stock ordered by earliest expiry.
-- Adapt product_id / quantity / expiry_date names if your existing schema differs.
create or replace function public.fefo_batches(p_product_id uuid, p_required_qty numeric)
returns table(batch_id uuid, take_qty numeric, expiry_date date)
language plpgsql
security invoker
as $$
declare
  remaining numeric := p_required_qty;
  r record;
begin
  if p_required_qty <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;

  for r in
    select id, quantity, expiry_date
    from public.batches
    where product_id = p_product_id
      and quantity > 0
      and (expiry_date is null or expiry_date >= current_date)
    order by expiry_date nulls last, id
    for update
  loop
    exit when remaining <= 0;
    take_qty := least(remaining, r.quantity);
    batch_id := r.id;
    expiry_date := r.expiry_date;
    remaining := remaining - take_qty;
    return next;
  end loop;

  if remaining > 0 then
    raise exception 'Insufficient non-expired stock';
  end if;
end;
$$;

-- Stock ledger policy: browser users can read only if admin.
alter table if exists public.stock_movements enable row level security;
drop policy if exists "admin read stock movements" on public.stock_movements;
create policy "admin read stock movements"
on public.stock_movements for select to authenticated
using (public.is_admin());

-- Production note:
-- Complete sale creation should be a single database transaction:
-- lock FEFO batches -> validate quantity -> decrement batches ->
-- create sale/sale_items -> insert stock_movements -> commit.
-- Do not implement this as separate client-side requests.
