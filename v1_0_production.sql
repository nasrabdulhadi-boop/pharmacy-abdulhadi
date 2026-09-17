-- Pharmacy Abdelhadi — v1.0 production hardening
-- Run AFTER the previous migrations. Review object names against your live Supabase schema.

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id),
  batch_id uuid references public.batches(id),
  movement_type text not null check (
    movement_type in ('purchase','sale','sale_return','purchase_return','adjustment')
  ),
  quantity numeric(12,2) not null check (quantity <> 0),
  reference_id uuid,
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_stock_movements_product
  on public.stock_movements(product_id, created_at desc);

create index if not exists idx_stock_movements_batch
  on public.stock_movements(batch_id, created_at desc);

alter table public.stock_movements enable row level security;

drop policy if exists "admin read stock movements" on public.stock_movements;
create policy "admin read stock movements"
on public.stock_movements
for select
to authenticated
using (
  coalesce((auth.jwt()->'app_metadata'->>'role'), '') = 'admin'
);

-- Health check: returns TRUE only when basic integrity checks pass.
create or replace function public.production_healthcheck()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  negative_batches bigint;
  expired_with_stock bigint;
begin
  select count(*) into negative_batches
  from public.batches
  where remaining_quantity < 0;

  select count(*) into expired_with_stock
  from public.batches
  where expiry_date < current_date
    and remaining_quantity > 0;

  return jsonb_build_object(
    'ok', (negative_batches = 0 and expired_with_stock = 0),
    'negative_stock_batches', negative_batches,
    'expired_batches_with_stock', expired_with_stock,
    'checked_at', now()
  );
end;
$$;

revoke all on function public.production_healthcheck() from public;
grant execute on function public.production_healthcheck() to authenticated;

-- NOTE:
-- Prescription files must live in a PRIVATE Supabase Storage bucket.
-- Create the bucket in the dashboard as:
--   prescriptions
-- Public access must remain OFF.
