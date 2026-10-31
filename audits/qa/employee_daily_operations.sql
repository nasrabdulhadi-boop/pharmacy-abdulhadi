-- QA ONLY. Adds function boundaries; no table, column, policy or stored-row rewrite.
begin;
-- Preserve the manager reviewer. Private clone is reachable only through the narrow daily-operation RPC.
do $do$ declare definition text; begin
 select pg_get_functiondef('public.qa_review_employee_operation(uuid,boolean)'::regprocedure) into definition;
 definition:=replace(definition,'public.qa_review_employee_operation','pharmacy_qa_private.apply_employee_daily_operation');
 definition:=replace(definition,$old$in ('system_owner','system_admin')$old$,$new$in ('employee','system_owner','system_admin')$new$);
 definition:=replace(definition,$old$if not found or r.status<>'pending' then return false; end if;$old$,$guard$if not found or r.status<>'pending' then return false; end if;
 if public.qa_current_system_role()='employee' and (r.employee_id<>auth.uid() or r.operation not in ('sale','purchase_draft')) then raise exception 'not_authorized' using errcode='42501'; end if;$guard$);
 execute definition;
end $do$;
revoke all on function pharmacy_qa_private.apply_employee_daily_operation(uuid,boolean) from public,anon,authenticated;
create or replace function public.qa_employee_execute_workspace(p_operation text,p_payloads jsonb,p_currency text default null,p_request_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare request uuid; previous public.qa_employee_operations;
begin
 if auth.uid() is null or public.qa_current_system_role() is distinct from 'employee' then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_operation is null or p_operation not in ('sale','purchase_draft') or p_request_id is null then raise exception 'daily_operation_not_allowed' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_request_id::text,731));
 select * into previous from public.qa_employee_operations where employee_id=auth.uid() and payload->>'daily_request_id'=p_request_id::text;
 if found then
  if previous.operation is distinct from p_operation or previous.payload->'daily_lines' is distinct from p_payloads or (previous.payload->>'daily_currency') is distinct from p_currency then raise exception 'idempotency_conflict' using errcode='22023'; end if;
  return previous.id;
 end if;
 if p_operation='sale' and exists(select 1 from jsonb_array_elements(p_payloads) i join pharmacy_qa_private.catalog c on c.id=(i->>'product_id')::uuid where c.price<=0) then raise exception 'sale_price_not_approved' using errcode='22023'; end if;
 request:=pharmacy_qa_private.submit_workspace_bundle(p_operation,p_payloads,p_currency);
 if not pharmacy_qa_private.apply_employee_daily_operation(request,true) then raise exception 'daily_execution_failed'; end if;
 update public.qa_employee_operations set payload=payload||jsonb_build_object('execution_mode','employee_direct','daily_request_id',p_request_id,'daily_lines',p_payloads,'daily_currency',p_currency) where id=request;
 return request;
end $$;
revoke all on function public.qa_employee_execute_workspace(text,jsonb,text,uuid) from public,anon;
grant execute on function public.qa_employee_execute_workspace(text,jsonb,text,uuid) to authenticated;
create or replace function public.qa_employee_create_purchase(p_payloads jsonb,p_currency text,p_request_id uuid,p_header jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare request uuid; old_header jsonb;
begin
 if auth.uid() is null or public.qa_current_system_role() is distinct from 'employee' then raise exception 'not_authorized' using errcode='42501'; end if;
 if jsonb_typeof(p_header) is distinct from 'object' or octet_length(p_header::text)>4096 or exists(select 1 from jsonb_object_keys(p_header) k where k not in ('supplier_id','invoice_number','invoice_date','notes','paid_amount')) or p_header->>'supplier_id' is distinct from '00000000-0000-4000-8000-000000009001' or coalesce((p_header->>'paid_amount')::numeric,0)<>0 then raise exception 'unsupported_purchase_header_or_payment' using errcode='22023'; end if;
 if (p_header->>'invoice_date')::date is distinct from (now() at time zone 'Asia/Damascus')::date then raise exception 'backdated_purchase_requires_manager' using errcode='42501'; end if;
 if nullif(btrim(p_header->>'invoice_number'),'') is not null then
  perform pg_advisory_xact_lock(hashtextextended((p_header->>'supplier_id')||(p_header->>'invoice_number'),735));
  if exists(select 1 from public.qa_employee_operations o where o.payload->'purchase_header'->>'supplier_id'=p_header->>'supplier_id' and o.payload->'purchase_header'->>'invoice_number'=p_header->>'invoice_number' and o.payload->>'daily_request_id' is distinct from p_request_id::text) then raise exception 'duplicate_purchase_invoice' using errcode='23505'; end if;
 end if;
 request:=public.qa_employee_execute_workspace('purchase_draft',p_payloads,p_currency,p_request_id);
 select payload->'purchase_header' into old_header from public.qa_employee_operations where id=request for update;
 if old_header is not null and old_header is distinct from p_header then raise exception 'idempotency_conflict' using errcode='22023'; end if;
 update public.qa_employee_operations set payload=payload||jsonb_build_object('purchase_header',p_header) where id=request;
 return request;
end $$;
revoke all on function public.qa_employee_create_purchase(jsonb,text,uuid,jsonb) from public,anon;
grant execute on function public.qa_employee_create_purchase(jsonb,text,uuid,jsonb) to authenticated;
-- New cards can be created without an approved selling price. Only a manager may activate/set prices.
create or replace function public.qa_save_workspace_product(p_product_id uuid,p_payload jsonb,p_barcodes jsonb default '[]',p_request_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
<<product_op>>
declare r text:=public.qa_current_system_role(); id uuid:=coalesce(p_product_id,p_request_id); code text; title text; sale numeric; purchase numeric; parts numeric; currency text; existing pharmacy_qa_private.catalog;
begin
 if auth.uid() is null or r is null or r not in ('employee','system_admin','system_owner') then raise exception 'not_authorized' using errcode='42501'; end if;
 if r='employee' and p_product_id is not null then raise exception 'price_or_product_edit_requires_manager' using errcode='42501'; end if;
 if id is null or jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>8192 or jsonb_typeof(p_barcodes) is distinct from 'array' then raise exception 'invalid_product' using errcode='22023'; end if;
 if jsonb_array_length(p_barcodes)>0 then raise exception 'additional_barcodes_not_supported_in_qa' using errcode='22023'; end if;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k not in ('name','barcode','active_ingredient','strength','dosage_form','manufacturer','unit','reorder_level','purchase_price','sale_price','parts_per_unit','customer_visible','sale_currency','category','active')) then raise exception 'unexpected_field' using errcode='22023'; end if;
 title:=btrim(p_payload->>'name');code:=coalesce(nullif(btrim(p_payload->>'barcode'),''),'QA-'||id::text);sale:=(p_payload->>'sale_price')::numeric;purchase:=(p_payload->>'purchase_price')::numeric;parts:=(p_payload->>'parts_per_unit')::numeric;currency:=p_payload->>'sale_currency';
 if title is null or length(title) not between 1 and 250 or length(code)>128 or sale is null or sale not between 0 and 1000000 or purchase is null or purchase not between 0 and 1000000 or parts is null or parts not between 1 and 1000 or parts<>trunc(parts) or currency is null or currency not in ('USD','SYP') or (p_payload->>'reorder_level')::numeric is null or (p_payload->>'reorder_level')::numeric not between 0 and 1000000 then raise exception 'invalid_product' using errcode='22023'; end if;
 if coalesce((p_payload->>'active')::boolean,true) is false or coalesce((p_payload->>'customer_visible')::boolean,false) or (r='employee' and sale<>0) then raise exception 'new_product_price_requires_manager' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(id::text,617));
 perform pg_advisory_xact_lock(hashtextextended(code,733));
 select * into existing from pharmacy_qa_private.catalog where catalog.id=product_op.id;
 if p_product_id is null and found then
  if existing.code=code and existing.title=title and existing.currency=currency and existing.price=sale and existing.parts=parts and exists(select 1 from public.products m where m.id=product_op.id and to_jsonb(m) @> (p_payload||jsonb_build_object('barcode',code,'customer_visible',false))) then return id; end if;
  raise exception 'idempotency_conflict' using errcode='22023';
 end if;
 if p_product_id is not null and not found then raise exception 'invalid_product' using errcode='22023'; end if;
 if p_product_id is not null and (existing.code<>code or existing.currency<>currency or existing.parts<>parts) then raise exception 'structural_product_edit_not_supported' using errcode='22023'; end if;
 if exists(select 1 from pharmacy_qa_private.catalog c where c.code=product_op.code and c.id<>product_op.id) or exists(select 1 from public.products m where m.barcode=product_op.code and m.id<>product_op.id) then raise exception 'duplicate_barcode' using errcode='23505'; end if;
 if p_product_id is null then insert into pharmacy_qa_private.catalog(id,code,title,price,currency,parts) values(id,code,title,sale,currency,parts::integer);
 else update pharmacy_qa_private.catalog c set code=product_op.code,title=product_op.title,price=sale,currency=product_op.currency,parts=product_op.parts::integer where c.id=product_op.id; end if;
 insert into public.products(id,name,barcode,active_ingredient,strength,dosage_form,manufacturer,category,unit,reorder_level,purchase_price,sale_price,parts_per_unit,customer_visible,sale_currency,active)
 values(id,title,code,p_payload->>'active_ingredient',p_payload->>'strength',p_payload->>'dosage_form',p_payload->>'manufacturer',p_payload->>'category',coalesce(p_payload->>'unit','piece'),(p_payload->>'reorder_level')::numeric,purchase,sale,parts,false,currency,true)
 on conflict on constraint products_pkey do update set name=excluded.name,barcode=excluded.barcode,active_ingredient=excluded.active_ingredient,strength=excluded.strength,dosage_form=excluded.dosage_form,manufacturer=excluded.manufacturer,category=excluded.category,unit=excluded.unit,reorder_level=excluded.reorder_level,purchase_price=excluded.purchase_price,sale_price=excluded.sale_price,parts_per_unit=excluded.parts_per_unit,sale_currency=excluded.sale_currency;
 return id;
end $$;
revoke all on function public.qa_save_workspace_product(uuid,jsonb,jsonb,uuid) from public,anon;
grant execute on function public.qa_save_workspace_product(uuid,jsonb,jsonb,uuid) to authenticated;
do $do$ declare definition text; begin
 select pg_get_functiondef('public.qa_workspace_snapshot()'::regprocedure) into definition;
 definition:=replace(definition,$old$'unit','box','reorder_level',1$old$,$new$'unit',coalesce((select m.unit from public.products m where m.id=p.id),'box'),'reorder_level',coalesce((select m.reorder_level from public.products m where m.id=p.id),1),'active_ingredient',(select m.active_ingredient from public.products m where m.id=p.id),'strength',(select m.strength from public.products m where m.id=p.id),'dosage_form',(select m.dosage_form from public.products m where m.id=p.id),'manufacturer',(select m.manufacturer from public.products m where m.id=p.id)$new$);
 definition:=replace(definition,$old$coalesce(sum(b.quantity*b.cost)/nullif(sum(b.quantity),0),0)$old$,$new$coalesce(sum(b.quantity*b.cost)/nullif(sum(b.quantity),0),(select m.purchase_price from public.products m where m.id=p.id),0)$new$);
 if position($field$'category',(select m.category from public.products m where m.id=p.id)$field$ in definition)=0 then
 definition:=replace(definition,$old$'manufacturer',(select m.manufacturer from public.products m where m.id=p.id)$old$,$new$'manufacturer',(select m.manufacturer from public.products m where m.id=p.id),'category',(select m.category from public.products m where m.id=p.id)$new$);
 end if;
 execute definition;
end $do$;
notify pgrst,'reload schema';
commit;
