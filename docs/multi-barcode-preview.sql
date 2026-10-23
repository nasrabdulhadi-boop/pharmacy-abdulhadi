-- Preview-only migration. DO NOT apply to production before approval.
create table if not exists public.product_barcodes (
 id bigint generated always as identity primary key,
 product_id uuid not null references public.products(id) on delete cascade,
 barcode text not null,
 created_at timestamptz not null default now(),
 constraint product_barcodes_nonempty check (length(btrim(barcode)) > 0),
 constraint product_barcodes_unique unique(barcode)
);
create index if not exists product_barcodes_product_id_idx on public.product_barcodes(product_id);
alter table public.product_barcodes enable row level security;
revoke all on public.product_barcodes from anon, authenticated;
create or replace function public.admin_get_product_barcodes(p_product_id uuid)
returns table(barcode text) language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','') <> 'admin' then raise exception 'Not authorized'; end if;
 return query select pb.barcode from public.product_barcodes pb where pb.product_id=p_product_id order by pb.id;
end; $$;
create or replace function public.admin_set_product_barcodes(p_product_id uuid,p_barcodes text[])
returns void language plpgsql security definer set search_path=public as $$
declare v_code text;
begin
 if auth.uid() is null or coalesce(auth.jwt()->'app_metadata'->>'role','') <> 'admin' then raise exception 'Not authorized'; end if;
 if not exists(select 1 from public.products where id=p_product_id) then raise exception 'Product not found'; end if;
 if coalesce(array_length(p_barcodes,1),0)>30 then raise exception 'Too many barcodes'; end if;
 if exists(select 1 from unnest(coalesce(p_barcodes,array[]::text[])) as c where length(btrim(c))=0) then raise exception 'Empty barcode'; end if;
 if exists(select 1 from (select btrim(c) from unnest(coalesce(p_barcodes,array[]::text[])) as c group by btrim(c) having count(*)>1) d) then raise exception 'Duplicate barcode'; end if;
 for v_code in select btrim(c) from unnest(coalesce(p_barcodes,array[]::text[])) as c loop
  if exists(select 1 from public.products p where btrim(p.barcode)=v_code) then raise exception 'Barcode already belongs to a primary product: %',v_code; end if;
  if exists(select 1 from public.product_barcodes pb where pb.barcode=v_code and pb.product_id<>p_product_id) then raise exception 'Barcode assigned to another product: %',v_code; end if;
 end loop;
 delete from public.product_barcodes where product_id=p_product_id;
 insert into public.product_barcodes(product_id,barcode) select p_product_id,btrim(c) from unnest(coalesce(p_barcodes,array[]::text[])) as c;
end; $$;
revoke all on function public.admin_get_product_barcodes(uuid) from public,anon;
revoke all on function public.admin_set_product_barcodes(uuid,text[]) from public,anon;
grant execute on function public.admin_get_product_barcodes(uuid) to authenticated;
grant execute on function public.admin_set_product_barcodes(uuid,text[]) to authenticated;
-- Integration requirement: extend ALL POS, purchase, inventory and product lookup RPCs
-- to resolve product_barcodes.barcode -> product_id, while keeping products.barcode.
-- Do not activate until these RPCs are audited and integrated.

-- Atomic creation/update of product and its alias barcodes in one transaction.
create or replace function public.admin_save_product_with_barcodes(
 p_product_id uuid, p_payload jsonb, p_barcodes text[]
) returns public.products language plpgsql security definer set search_path=public,auth as $$
declare v public.products; v_code text;
begin
 if not public.is_admin() then raise exception 'غير مصرح'; end if;
 if coalesce(array_length(p_barcodes,1),0)>30 then raise exception 'Too many barcodes'; end if;
 for v_code in select btrim(c) from unnest(coalesce(p_barcodes,array[]::text[])) as c loop
   if v_code='' then raise exception 'Empty barcode'; end if;
   if v_code=coalesce(btrim(p_payload->>'barcode'),'') then raise exception 'Additional barcode equals primary'; end if;
 end loop;
 -- Check that primary barcode is not an alias of a different product.
 if exists(select 1 from public.product_barcodes pb
    where pb.barcode=btrim(p_payload->>'barcode') and (p_product_id is null or pb.product_id<>p_product_id))
 then raise exception 'Primary barcode belongs to another product'; end if;
 v:=public.admin_save_pharmacy_product(p_product_id,p_payload);
 perform public.admin_set_product_barcodes(v.id,p_barcodes);
 return v;
end; $$;
revoke all on function public.admin_save_product_with_barcodes(uuid,jsonb,text[]) from public,anon;
grant execute on function public.admin_save_product_with_barcodes(uuid,jsonb,text[]) to authenticated;

-- Lookup returns the canonical product ID for primary OR alias barcode.
create or replace function public.admin_resolve_product_barcode(p_barcode text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_id uuid; v_code text:=btrim(coalesce(p_barcode,''));
begin
 if not public.is_admin() then raise exception 'غير مصرح'; end if;
 select p.id into v_id from public.products p where p.barcode=v_code limit 1;
 if v_id is not null then return v_id; end if;
 select pb.product_id into v_id from public.product_barcodes pb where pb.barcode=v_code limit 1;
 return v_id;
end; $$;
revoke all on function public.admin_resolve_product_barcode(text) from public,anon;
grant execute on function public.admin_resolve_product_barcode(text) to authenticated;
