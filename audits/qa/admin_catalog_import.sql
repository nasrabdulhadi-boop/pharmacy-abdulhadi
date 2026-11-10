-- Deploy only to isolated QA. New and edited rows must belong to the synthetic import namespace.
create or replace function public.qa_apply_catalog_import(p_request_id uuid, p_rows jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare
 actor uuid := auth.uid();
 actor_role text := public.qa_current_system_role();
 item jsonb;
 import_code text;
 title text;
 import_currency text;
 new_price numeric;
 catalog_row pharmacy_qa_private.catalog;
 saved jsonb;
 changes jsonb := '[]'::jsonb;
begin
 if actor is null or actor_role is null or actor_role not in ('system_owner','system_admin') then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 if p_request_id is null or jsonb_typeof(p_rows) is distinct from 'array' or octet_length(p_rows::text)>80000 then
  raise exception 'invalid_import' using errcode='22023';
 end if;
 if jsonb_array_length(p_rows) not between 1 and 200 or
    (select count(distinct x->>'barcode') from jsonb_array_elements(p_rows) x) <> jsonb_array_length(p_rows) then
  raise exception 'invalid_import' using errcode='22023';
 end if;

 perform pg_advisory_xact_lock(hashtextextended(p_request_id::text,17931));
 select details into saved from pharmacy_qa_private.audit_events
 where id=p_request_id and actor_id=actor and action='qa_catalog_import';
 if found then
  if saved->'request' is distinct from p_rows then raise exception 'import_conflict' using errcode='22023'; end if;
  return jsonb_array_length(p_rows);
 end if;

 for item in select x from jsonb_array_elements(p_rows) x order by x->>'barcode' loop
  import_code:=item->>'barcode'; title:=btrim(item->>'name'); import_currency:=item->>'currency';
  if import_code is null or import_code !~ '^QA-IMPORT-[A-Z0-9_-]{1,60}$' or
     import_currency is null or import_currency not in ('USD','SYP') or
     coalesce(item->>'price','') !~ '^[0-9]{1,7}(\.[0-9]{1,4})?$' then
   raise exception 'invalid_import_row' using errcode='22023';
  end if;
  new_price:=(item->>'price')::numeric;
  if new_price>1000000 then raise exception 'invalid_import_price' using errcode='22023'; end if;
  select * into catalog_row from pharmacy_qa_private.catalog c where c.code=import_code;
  if item->>'mode'='create' then
   if found or title is null or char_length(title) not between 1 and 250 then
    raise exception 'import_catalog_changed' using errcode='40001';
   end if;
   perform public.qa_save_workspace_product(null,jsonb_build_object(
    'name',title,'barcode',import_code,'sale_price',new_price,'purchase_price',0,'sale_currency',import_currency,
    'parts_per_unit',1,'reorder_level',1,'customer_visible',false,'unit','piece'), '[]'::jsonb,gen_random_uuid());
  elsif item->>'mode'='update' then
   if not found or (item->>'id') is distinct from catalog_row.id::text then
    raise exception 'import_catalog_changed' using errcode='40001';
   end if;
   -- Use the same lock order as the existing product editor.
   perform pg_advisory_xact_lock(hashtextextended(catalog_row.id::text,617));
   perform pg_advisory_xact_lock(hashtextextended(import_code,733));
   select * into catalog_row from pharmacy_qa_private.catalog c where c.id=(item->>'id')::uuid for update;
   if not found or catalog_row.code is distinct from import_code or catalog_row.currency is distinct from import_currency or
      coalesce(item->>'previousPrice','') !~ '^[0-9]{1,7}(\.[0-9]{1,4})?$' or
      catalog_row.price is distinct from (item->>'previousPrice')::numeric then
    raise exception 'import_catalog_changed' using errcode='40001';
   end if;
   update public.products p set sale_price=new_price where p.id=catalog_row.id and p.barcode=import_code
    and p.active and not p.customer_visible and p.sale_currency=import_currency and p.sale_price=catalog_row.price;
   if not found then raise exception 'import_catalog_changed' using errcode='40001'; end if;
   update pharmacy_qa_private.catalog c set price=new_price where c.id=catalog_row.id;
  else
   raise exception 'invalid_import_mode' using errcode='22023';
  end if;
  changes:=changes||jsonb_build_array(jsonb_build_object('barcode',import_code,'currency',import_currency,'before',item->>'previousPrice','after',new_price));
 end loop;

 insert into pharmacy_qa_private.audit_events(id,actor_id,actor_email,actor_role,action,entity_type,entity_id,details)
 select p_request_id,actor,u.email,actor_role,'qa_catalog_import','product',p_request_id::text,
   jsonb_build_object('request',p_rows,'changes',changes)
 from auth.users u where u.id=actor;
 if not found then raise exception 'not_authorized' using errcode='42501'; end if;
 return jsonb_array_length(p_rows);
end $$;
revoke all on function public.qa_apply_catalog_import(uuid,jsonb) from public,anon;
grant execute on function public.qa_apply_catalog_import(uuid,jsonb) to authenticated;
