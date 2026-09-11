-- Pharmacy Abdelhadi — FINAL FIX
-- Run once in Supabase SQL Editor after the application is deployed.
-- Safe to run repeatedly. Does NOT expose the prescriptions bucket publicly.

create or replace function public.is_admin()
returns boolean
language sql
stable
as $$ select coalesce(auth.jwt()->'app_metadata'->>'role','') = 'admin'; $$;

-- Admin read/write policies for all application tables used by the dashboard.
do $$
declare t text;
begin
  foreach t in array array['products','batches','customers','orders','order_items','suppliers','purchases','purchase_items','sales','sale_items','prescriptions'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Products: keep public customer catalogue read-only and admin CRUD.
drop policy if exists "admin products" on public.products;
create policy "admin products" on public.products
for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "public products read" on public.products;
create policy "public products read" on public.products
for select to anon, authenticated using (customer_visible = true);

-- Batches / inventory.
drop policy if exists "admin batches" on public.batches;
create policy "admin batches" on public.batches
for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Orders, customers, suppliers and related records.
drop policy if exists "admin customers" on public.customers;
create policy "admin customers" on public.customers
for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin orders" on public.orders;
create policy "admin orders" on public.orders
for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin order items" on public.order_items;
create policy "admin order items" on public.order_items
for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin suppliers" on public.suppliers;
create policy "admin suppliers" on public.suppliers
for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin purchases" on public.purchases;
create policy "admin purchases" on public.purchases
for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin purchase items" on public.purchase_items;
create policy "admin purchase items" on public.purchase_items
for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin sales" on public.sales;
create policy "admin sales" on public.sales
for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin sale items" on public.sale_items;
create policy "admin sale items" on public.sale_items
for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin prescriptions" on public.prescriptions;
create policy "admin prescriptions" on public.prescriptions
for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Keep customer order submission possible without giving anon read access.
drop policy if exists "public create customers" on public.customers;
create policy "public create customers" on public.customers
for insert to anon, authenticated with check (true);
drop policy if exists "public create orders" on public.orders;
create policy "public create orders" on public.orders
for insert to anon, authenticated with check (status = 'new');
drop policy if exists "public create order items" on public.order_items;
create policy "public create order items" on public.order_items
for insert to anon, authenticated with check (quantity > 0 and unit_price >= 0);

-- Ensure the private prescription bucket exists and remains private.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'prescriptions', 'prescriptions', false, 10485760,
  array['image/jpeg','image/png','image/webp','application/pdf']::text[]
)
on conflict (id) do update set
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = excluded.allowed_mime_types;

-- Storage policies: admin only for prescription files.
drop policy if exists "Admins can read prescription files" on storage.objects;
create policy "Admins can read prescription files"
on storage.objects for select to authenticated
using (bucket_id = 'prescriptions' and public.is_admin());

drop policy if exists "Admins can upload prescription files" on storage.objects;
create policy "Admins can upload prescription files"
on storage.objects for insert to authenticated
with check (bucket_id = 'prescriptions' and public.is_admin());

drop policy if exists "Admins can update prescription files" on storage.objects;
create policy "Admins can update prescription files"
on storage.objects for update to authenticated
using (bucket_id = 'prescriptions' and public.is_admin())
with check (bucket_id = 'prescriptions' and public.is_admin());

drop policy if exists "Admins can delete prescription files" on storage.objects;
create policy "Admins can delete prescription files"
on storage.objects for delete to authenticated
using (bucket_id = 'prescriptions' and public.is_admin());

-- Audit log read for admins.
create table if not exists public.audit_logs(
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  action text not null,
  entity_type text,
  entity_id uuid,
  details jsonb,
  created_at timestamptz not null default now()
);
alter table public.audit_logs enable row level security;
drop policy if exists "admin audit read" on public.audit_logs;
create policy "admin audit read" on public.audit_logs
for select to authenticated using (public.is_admin());
