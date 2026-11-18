create function public.manager_catalog_apply(p_request_id uuid,p_rows jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); row_data jsonb; saved jsonb; code text; title text; currency_code text; price numeric; existing public.products; previous numeric;
begin
 if not exists (select 1 from auth.users u where u.id=actor and coalesce(u.raw_app_meta_data->>'system_role',u.raw_app_meta_data->>'role') in ('system_admin','system_owner','admin') and (u.banned_until is null or u.banned_until<=now())) then raise exception 'manager_required' using errcode='42501'; end if;
 if p_request_id is null or jsonb_typeof(p_rows) is distinct from 'array' or octet_length(p_rows::text)>100000 then raise exception 'invalid_request'; end if;
 if jsonb_array_length(p_rows) not between 1 and 200 or (select count(distinct r->>'barcode') from jsonb_array_elements(p_rows) r)<>jsonb_array_length(p_rows) then raise exception 'invalid_rows'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,17931));
 select a.details->'request' into saved from public.audit_logs a where a.id=p_request_id and a.user_id=actor and a.action='manager_catalog_import';
 if found then
   if saved is distinct from p_rows then raise exception 'request_conflict'; end if;
   return jsonb_array_length(p_rows);
 end if;
 for row_data in select r from jsonb_array_elements(p_rows) r order by r->>'barcode' loop
   code:=row_data->>'barcode'; title:=btrim(row_data->>'name');currency_code:=row_data->>'currency';
   if code !~ '^[A-Za-z0-9_-]{1,80}$' or currency_code is null or currency_code not in ('SYP','USD') or coalesce(row_data->>'price','') !~ '^[0-9]{1,9}([.][0-9]{1,4})?$' then raise exception 'invalid_row';end if;
   price:=(row_data->>'price')::numeric;
   if exists(select 1 from public.product_barcodes b where b.barcode=code) then raise exception 'alias_barcode' using errcode='40001'; end if;
   select * into existing from public.products where barcode=code for update;
   if row_data->>'mode'='create' then
     if found or title is null or length(title) not between 1 and 250 then raise exception 'catalog_changed' using errcode='40001';end if;
     insert into public.products(id,name,barcode,sale_currency,sale_price,active,unit,parts_per_unit,customer_visible,purchase_price,reorder_level) values(gen_random_uuid(),title,code,currency_code,price,true,'piece',1,false,0,0);
   elsif row_data->>'mode'='update' then
     if not found or not existing.active or existing.id::text is distinct from row_data->>'id' or existing.sale_currency is distinct from currency_code or coalesce(row_data->>'previousPrice','') !~ '^[0-9]+([.][0-9]+)?$' then raise exception 'catalog_changed' using errcode='40001';end if;
     previous:=(row_data->>'previousPrice')::numeric;
     if existing.sale_price is distinct from previous then raise exception 'catalog_changed' using errcode='40001';end if;
     update public.products set sale_price=price where id=existing.id;
   else raise exception 'unknown_mode';end if;
 end loop;
 insert into public.audit_logs(id,user_id,action,entity_type,entity_id,details) values(p_request_id,actor,'manager_catalog_import','products',p_request_id,jsonb_build_object('request',p_rows,'count',jsonb_array_length(p_rows)));
 return jsonb_array_length(p_rows);
end $$;
revoke all on function public.manager_catalog_apply(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.manager_catalog_apply(uuid,jsonb) to authenticated;
