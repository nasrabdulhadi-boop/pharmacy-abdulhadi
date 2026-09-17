-- Pharmacy Abdelhadi v2.1 — BASE SCHEMA
-- Run this FIRST on a fresh Supabase project.
-- Then run the versioned migrations in numerical order.

create extension if not exists pgcrypto;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  barcode text unique,
  name text not null,
  active_ingredient text,
  dosage_form text,
  strength text,
  manufacturer text,
  category text,
  unit text not null default 'piece',
  reorder_level numeric(12,2) not null default 0 check (reorder_level >= 0),
  customer_visible boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.batches (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  batch_number text,
  expiry_date date,
  quantity numeric(12,2) not null default 0 check (quantity >= 0),
  purchase_price numeric(12,2) not null default 0 check (purchase_price >= 0),
  received_date date not null default current_date,
  created_at timestamptz not null default now()
);
create index if not exists idx_batches_product_expiry on public.batches(product_id, expiry_date, id);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  address text,
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers(id) on delete set null,
  status text not null default 'new' check (status in ('new','confirmed','preparing','ready','completed','cancelled')),
  notes text,
  total numeric(12,2) not null default 0 check (total >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(12,2) not null check (quantity > 0),
  unit_price numeric(12,2) not null default 0 check (unit_price >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  address text,
  created_at timestamptz not null default now()
);

create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid references public.suppliers(id) on delete set null,
  invoice_number text,
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  total numeric(12,2) not null default 0 check (total >= 0),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create table if not exists public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  batch_id uuid references public.batches(id) on delete restrict,
  quantity numeric(12,2) not null check (quantity > 0),
  purchase_price numeric(12,2) not null check (purchase_price >= 0),
  expiry_date date,
  created_at timestamptz not null default now()
);

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers(id) on delete set null,
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  discount numeric(12,2) not null default 0 check (discount >= 0),
  total numeric(12,2) not null default 0 check (total >= 0),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  batch_id uuid not null references public.batches(id) on delete restrict,
  quantity numeric(12,2) not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  unit_cost numeric(12,2) not null default 0 check (unit_cost >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.prescriptions (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers(id) on delete set null,
  order_id uuid references public.orders(id) on delete set null,
  file_path text not null,
  file_name text,
  mime_type text,
  file_size bigint,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

-- Required compatibility aliases for the earlier application code.
-- inventory_batches was used by an early migration; v2.1 standardizes on batches.

create index if not exists idx_products_name on public.products(name);
create index if not exists idx_products_barcode on public.products(barcode);
create index if not exists idx_orders_status on public.orders(status, created_at desc);
create index if not exists idx_sale_items_sale on public.sale_items(sale_id);
create index if not exists idx_purchase_items_purchase on public.purchase_items(purchase_id);
create index if not exists idx_prescriptions_order on public.prescriptions(order_id);

-- Basic updated_at helper.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at before update on public.products
for each row execute function public.set_updated_at();

drop trigger if exists orders_set_updated_at on public.orders;
create trigger orders_set_updated_at before update on public.orders
for each row execute function public.set_updated_at();

-- Enable RLS on application tables. Policies are added by later migrations.
alter table public.products enable row level security;
alter table public.batches enable row level security;
alter table public.customers enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.prescriptions enable row level security;
