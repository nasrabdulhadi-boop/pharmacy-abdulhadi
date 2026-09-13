-- صيدلية عبدالهادي — V4.1 FULL UPGRADE
-- يشغّل مرة واحدة في Supabase SQL Editor بعد مخطط النسخ السابقة.
-- يعيد إنشاء سياسات/دوال بشكل آمن قدر الإمكان، ولا يجعل ملفات الوصفات عامة.

create extension if not exists pgcrypto;

-- 1) عروض الصيدلية
create table if not exists public.offers(
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.offers enable row level security;
drop policy if exists "public read active offers" on public.offers;
create policy "public read active offers" on public.offers for select to anon, authenticated using(active=true);
drop policy if exists "admin offers" on public.offers;
create policy "admin offers" on public.offers for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- 2) طلبات البحث عن دواء غير موجود
create table if not exists public.medicine_requests(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  strength text,
  phone text not null,
  status text not null default 'new',
  created_at timestamptz not null default now()
);
alter table public.medicine_requests enable row level security;
drop policy if exists "admin medicine requests" on public.medicine_requests;
create policy "admin medicine requests" on public.medicine_requests for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- 3) دورة حياة الوصفات + بيانات العميل
alter table public.prescriptions add column if not exists status text not null default 'new';
alter table public.prescriptions add column if not exists customer_name text;
alter table public.prescriptions add column if not exists customer_phone text;
alter table public.prescriptions add column if not exists notes text;

-- 4) أرقام طلبات حقيقية
create sequence if not exists public.order_public_seq start 1025;
alter table public.orders add column if not exists public_code text;
update public.orders set public_code='ORD-'||nextval('public.order_public_seq') where public_code is null;
create unique index if not exists orders_public_code_uidx on public.orders(public_code);
alter table public.orders alter column public_code set default ('ORD-'||nextval('public.order_public_seq'));

-- 5) منع إدخال طلبات عامة مباشرة، واستخدام RPC آمن بدلاً منه
drop policy if exists "public create customers" on public.customers;
drop policy if exists "public create orders" on public.orders;
drop policy if exists "public create order items" on public.order_items;

create or replace function public.create_public_order(
  p_name text,
  p_phone text,
  p_address text default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns table(order_id uuid, public_code text, total numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer uuid;
  v_order uuid;
  v_total numeric := 0;
  it jsonb;
  v_product uuid;
  v_qty numeric;
  v_price numeric;
  v_visible boolean;
begin
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_phone),'')='' then
    raise exception 'Name and phone are required';
  end if;
  if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then
    raise exception 'Order is empty';
  end if;

  insert into public.customers(name,phone,address)
  values(trim(p_name),trim(p_phone),nullif(trim(coalesce(p_address,'')),''))
  returning id into v_customer;

  insert into public.orders(customer_id,status,notes,total)
  values(v_customer,'new',nullif(trim(coalesce(p_notes,'')),''),0)
  returning id, public_code into v_order, public_code;

  for it in select * from jsonb_array_elements(p_items) loop
    v_product := (it->>'product_id')::uuid;
    v_qty := (it->>'quantity')::numeric;
    if v_qty <= 0 then raise exception 'Invalid quantity'; end if;
    select customer_visible, coalesce(sale_price,0) into v_visible, v_price
    from public.products where id=v_product;
    if not found or v_visible is not true then raise exception 'Product is unavailable'; end if;
    insert into public.order_items(order_id,product_id,quantity,unit_price)
    values(v_order,v_product,v_qty,v_price);
    v_total := v_total + v_qty*v_price;
  end loop;

  update public.orders set total=v_total, updated_at=now() where id=v_order;
  return query select v_order, public_code, v_total;
end;
$$;
revoke all on function public.create_public_order(text,text,text,text,jsonb) from public;
grant execute on function public.create_public_order(text,text,text,text,jsonb) to anon, authenticated;

create or replace function public.track_public_order(p_code text,p_phone text)
returns table(public_code text,status text,created_at timestamptz,total numeric)
language sql
security definer
set search_path = public
as $$
  select o.public_code,o.status,o.created_at,o.total
  from public.orders o
  join public.customers c on c.id=o.customer_id
  where upper(o.public_code)=upper(trim(p_code)) and c.phone=trim(p_phone)
  order by o.created_at desc limit 1;
$$;
revoke all on function public.track_public_order(text,text) from public;
grant execute on function public.track_public_order(text,text) to anon, authenticated;

-- 6) وصفات العملاء: رفع الملف مجهولاً إلى مسار intake فقط، ثم إنشاء السجل عبر RPC
create or replace function public.submit_public_prescription(
  p_name text,p_phone text,p_notes text,p_file_path text,p_file_name text,p_mime_type text,p_file_size bigint
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_phone),'')='' then raise exception 'Name and phone are required'; end if;
  if p_file_path not like 'intake/%' then raise exception 'Invalid prescription path'; end if;
  if p_file_size is null or p_file_size > 10485760 then raise exception 'File is too large'; end if;
  insert into public.prescriptions(customer_name,customer_phone,notes,file_path,file_name,mime_type,file_size,status)
  values(trim(p_name),trim(p_phone),nullif(trim(coalesce(p_notes,'')),''),p_file_path,p_file_name,p_mime_type,p_file_size,'new')
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.submit_public_prescription(text,text,text,text,text,text,bigint) from public;
grant execute on function public.submit_public_prescription(text,text,text,text,text,text,bigint) to anon, authenticated;

-- 7) طلب دواء غير موجود عبر RPC
create or replace function public.submit_medicine_request(p_name text,p_strength text,p_phone text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if coalesce(trim(p_name),'')='' or coalesce(trim(p_phone),'')='' then raise exception 'Name and phone are required'; end if;
  insert into public.medicine_requests(name,strength,phone,status)
  values(trim(p_name),nullif(trim(coalesce(p_strength,'')),''),trim(p_phone),'new')
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.submit_medicine_request(text,text,text) from public;
grant execute on function public.submit_medicine_request(text,text,text) to anon, authenticated;

-- 8) Storage: bucket خاص. الإدارة تقرأ/تعدل، الزبون يستطيع الرفع فقط داخل intake/.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('prescriptions','prescriptions',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf']::text[])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Public prescription intake upload" on storage.objects;
create policy "Public prescription intake upload" on storage.objects
for insert to anon, authenticated
with check(bucket_id='prescriptions' and name like 'intake/%');

drop policy if exists "Admins can read prescription files" on storage.objects;
create policy "Admins can read prescription files" on storage.objects
for select to authenticated using(bucket_id='prescriptions' and public.is_admin());

drop policy if exists "Admins can upload prescription files" on storage.objects;
create policy "Admins can upload prescription files" on storage.objects
for insert to authenticated with check(bucket_id='prescriptions' and public.is_admin());

drop policy if exists "Admins can update prescription files" on storage.objects;
create policy "Admins can update prescription files" on storage.objects
for update to authenticated using(bucket_id='prescriptions' and public.is_admin()) with check(bucket_id='prescriptions' and public.is_admin());

drop policy if exists "Admins can delete prescription files" on storage.objects;
create policy "Admins can delete prescription files" on storage.objects
for delete to authenticated using(bucket_id='prescriptions' and public.is_admin());

-- 9) تأكيد سياسات الجداول الجديدة
alter table public.offers enable row level security;
alter table public.medicine_requests enable row level security;

-- 10) نسخة آمنة من حالة الصحة
create or replace function public.production_healthcheck()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  neg integer;
  exp integer;
begin
  if not public.is_admin() then raise exception 'Admin authorization required'; end if;
  select count(*) into neg from public.batches where quantity < 0;
  select count(*) into exp from public.batches where quantity > 0 and expiry_date < current_date;
  return jsonb_build_object('ok',neg=0 and exp=0,'negative_stock_batches',neg,'expired_batches_with_stock',exp);
end;
$$;

-- 11) سجل تدقيق للقراءة فقط من الإدارة
create table if not exists public.audit_logs(
 id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id), action text not null,
 entity_type text, entity_id uuid, details jsonb, created_at timestamptz not null default now()
);
alter table public.audit_logs enable row level security;
drop policy if exists "admin audit read" on public.audit_logs;
create policy "admin audit read" on public.audit_logs for select to authenticated using(public.is_admin());
drop policy if exists "admin audit insert" on public.audit_logs;
create policy "admin audit insert" on public.audit_logs for insert to authenticated with check(public.is_admin());

-- 12) ملاحظة: لا يتم فتح قراءة orders/prescriptions للعملاء.
-- تتبع الطلب يتم فقط عبر RPC يطابق رقم الطلب + الهاتف.
