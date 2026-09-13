-- Pharmacy Abdelhadi v3.4 — inventory/product management enhancements
-- Run once in Supabase SQL Editor after the existing FINAL_FIX.sql.

create or replace function public.adjust_stock(
  p_batch_id uuid,
  p_delta numeric,
  p_note text default null
)
returns numeric
language plpgsql
security invoker
set search_path = public
as $$
declare
  b public.batches%rowtype;
  new_qty numeric;
begin
  if not public.is_admin() then
    raise exception 'Admin authorization required';
  end if;
  if coalesce(p_delta,0) = 0 then
    raise exception 'Stock adjustment cannot be zero';
  end if;

  select * into b from public.batches where id = p_batch_id for update;
  if not found then raise exception 'Batch not found'; end if;

  new_qty := b.quantity + p_delta;
  if new_qty < 0 then
    raise exception 'Insufficient stock: adjustment would make quantity negative';
  end if;

  update public.batches set quantity = new_qty where id = p_batch_id;

  insert into public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
  values(b.product_id,b.id,'adjustment',p_delta,p_note,auth.uid());

  insert into public.audit_logs(user_id,action,entity_type,entity_id,details)
  values(auth.uid(),'adjust_stock','batch',b.id,jsonb_build_object('delta',p_delta,'new_quantity',new_qty,'note',p_note));

  return new_qty;
end;
$$;

grant execute on function public.adjust_stock(uuid,numeric,text) to authenticated;

-- Admins can read stock movement history.
alter table public.stock_movements enable row level security;
drop policy if exists "admin read stock movements" on public.stock_movements;
create policy "admin read stock movements"
on public.stock_movements for select to authenticated
using (public.is_admin());

-- Admins can insert movements only through controlled RPCs; direct client INSERT is not granted here.
