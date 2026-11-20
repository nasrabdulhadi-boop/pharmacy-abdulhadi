-- Preserve the restricted Auth role, including during initial account creation.
create or replace function pharmacy_branch_private.workspace_identity_guard() returns trigger language plpgsql set search_path='' as $$
begin new.role:='pharmacy_workspace_only'; return new; end $$;
create schema staff_scoped;
revoke all on schema staff_scoped from public, anon, authenticated;
create function staff_scoped.is_admin() returns boolean language sql stable set search_path='' as $$
select coalesce(current_setting('pharmacy.staff_scoped',true)='verified',false) $$;
create function staff_scoped.authorize(actor uuid, scopes text[], correction boolean) returns void language plpgsql set search_path='' as $$
begin
 if not exists(select from auth.users u where id=actor and role='pharmacy_workspace_only' and (banned_until is null or banned_until<=now())
 and raw_app_meta_data->>'workspace_issuer'='pharmacy_manager_v1' and raw_app_meta_data->>'staff_kind' in ('employee','support')
 and raw_app_meta_data->'sections' ?| scopes and (not correction or raw_app_meta_data->'sections' ? 'corrections')) then raise exception 'Section denied' using errcode='42501';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor)::text,true);
 perform set_config('pharmacy.staff_scoped','verified',true);
end $$;
set local check_function_bodies=off;
do $install$
declare rules jsonb:='{"admin_dashboard_day_details":["dashboard","dashboard"],"admin_products_count":["dashboard"],"admin_list_sales":["dashboard","daily"],"admin_dashboard_sales_day":["dashboard"],"admin_get_products":["dashboard"],"admin_get_inventory":["dashboard","inventory","smart"],"admin_smart_summary":["dashboard"],"admin_currency_purchase_detail_v1":["dashboard","purchases","products","purchases"],"complete_sale_accounting_currency":["pos"],"admin_product_catalog_currency":["pos","products","siteProducts","inventory"],"admin_get_currency_settings":["pos","inventory","supplierDebts"],"admin_product_batch_trace":["pos","products","siteProducts","inventory"],"admin_create_debtor":["pos","debtors"],"admin_search_pos_products_currency":["pos"],"admin_resolve_product_barcode":["pos","inventory","smart","purchases"],"admin_pos_stock_unavailable_reason":["pos"],"admin_save_product_with_barcodes":["products"],"admin_search_debtors":["pos","debtors"],"admin_get_sale_invoice_number_v1":["pos","daily","daily","pos"],"admin_restore_pharmacy_product":["products"],"admin_get_product_barcodes":["products","products","siteProducts","siteProducts","purchases"],"admin_delete_pharmacy_product":["products"],"admin_bulk_sale_price_change":["products"],"admin_set_product_visibility":["siteProducts"],"admin_product_search_key_for_barcode":["products","siteProducts"],"admin_update_product_prices":["inventory"],"admin_search_inventory_products":["inventory","smart"],"admin_delete_batch":["inventory","inventory"],"adjust_stock":["inventory"],"admin_search_purchase_products_currency":["inventory","purchases"],"admin_update_batch_details":["inventory"],"admin_reorder_recommendations":["smart"],"admin_complete_inventory_count":["smart"],"admin_set_inventory_count_actual":["smart"],"admin_dispose_stock":["smart"],"admin_inventory_count_items":["smart"],"admin_latest_inventory_count_result":["smart"],"admin_update_purchase_item_sale_currency_v1":["purchases"],"admin_create_supplier":["suppliers","purchases"],"admin_create_purchase_with_advance_v3":["purchases"],"admin_delete_purchase":["purchases"],"admin_supplier_advance_summary_v1":["purchases"],"admin_list_purchases_currency_v1":["purchases","suppliers"],"admin_list_suppliers":["purchases","suppliers","supplierDebts"],"admin_currency_supplier_ledger_v1":["suppliers","supplierDebts"],"admin_delete_supplier":["suppliers"],"admin_currency_supplier_purchase_history_v1":["suppliers"],"admin_record_supplier_payment_advance_v3":["supplierDebts"],"admin_currency_supplier_debt_list_v1":["supplierDebts"],"admin_record_debtor_payment":["debtors"],"admin_debtor_ledger":["debtors"],"admin_list_debtors":["debtors"],"admin_delete_order":["orders"],"admin_update_order_status":["orders"],"get_admin_orders":["orders"],"admin_customer_return":["returns"],"admin_return_list":["returns"],"admin_list_sale_items":["returns","daily"],"admin_supplier_return_bundle":["returns"],"admin_supplier_return_options":["returns"],"admin_customer_profiles":["customers"],"admin_customer_history":["customers"],"admin_record_cashbox_count":["cashbox"],"admin_cashbox_count_history":["cashbox"],"admin_cashbox_reconcile":["cashbox"],"admin_cashbox_manual_entry":["cashbox"],"admin_cashbox_summary_v2":["cashbox"],"admin_accounting_report":["financial","reports","daily"],"admin_get_purchase_detail_currency":["daily"],"admin_sale_detail_daily_v1":["daily"],"admin_sale_invoice_numbers_v1":["daily","daily","security"],"admin_daily_activity_v1":["daily","daily"],"admin_daily_financial_summary_v1":["daily"],"admin_get_products_page":["dashboard","products","siteProducts"],"admin_start_product_inventory_count":["smart"],"admin_start_inventory_count":["smart"],"admin_inventory_count_sales_summary":["smart"],"admin_inventory_count_result":["smart"],"admin_update_supplier":["suppliers"],"admin_system_healthcheck":["security"],"admin_financial_integrity_check":["security"]}'; selected oid[]; f record; n text; body text; args text; res text; expr text; scopes text[]; correction boolean; guard text;
begin
 with recursive defs as (select p.oid,p.proname,p.prosrc from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind='f'),
 reach as (select * from defs where rules ? proname union select d.* from reach r join defs d on r.prosrc ~ ('\m'||d.proname||'\s*\(') where d.proname not in ('is_admin','gen_random_uuid'))
 select array_agg(oid) into selected from reach;
 for f in select p.*,pg_get_function_arguments(p.oid) argdecl,pg_get_function_result(p.oid) result from pg_proc p where p.oid=any(selected) loop
  body:=pg_get_functiondef(f.oid);
  for n in select distinct proname from pg_proc where oid=any(selected) union select 'is_admin' loop
    body:=regexp_replace(body,'(\mpublic\.|\m)'||n||'\s*\(','staff_scoped.'||n||'(','gi');
  end loop;
  execute body;
  if rules ? f.proname then
   select array_agg(value) into scopes from jsonb_array_elements_text(rules->f.proname);
   correction:= f.proname ~ '(delete|adjust_stock|dispose_stock|bulk_sale_price_change|restore_pharmacy|update_product_prices|update_batch_details|complete_inventory_count|update_purchase_item_sale_currency)';
   select string_agg(format('$%s',i+1),',' order by i) into args from generate_series(1,f.pronargs) i;
   expr:=format('staff_scoped.%I(%s)',f.proname,coalesce(args,''));
   res:=case when f.proretset then 'return query select * from '||expr||';' when f.prorettype='void'::regtype then 'perform '||expr||';return;' else 'return '||expr||';' end;
   guard:='';
   if f.proname='admin_save_product_with_barcodes' then
    guard:='if p_product_id is not null then perform staff_scoped.authorize(ws_actor,array[''products''],true); end if;';
   elsif f.proname='complete_sale_accounting_currency' then
    guard:='if p_currency is distinct from ''SYP'' or p_fx_rate is not null then raise exception ''Unsupported sale currency'';end if;
    perform 1 from public.pharmacy_currency_settings where id=1 for share;
    perform 1 from public.products where id in(select (v->>''product_id'')::uuid from jsonb_array_elements(p_items) v) order by id for share;
    if exists(select from jsonb_array_elements(p_items) v left join public.products p on p.id=(v->>''product_id'')::uuid where p.id is null or (v->>''unit_price'')::numeric is distinct from p.sale_price*case when upper(p.sale_currency)=''USD'' then (select usd_to_syp from public.pharmacy_currency_settings where id=1) else 1 end) then raise exception ''Product price changed'';end if;';
   end if;
   if f.proname ~ '(^adjust_|^complete_sale|^admin_(bulk_|create_|complete_|set_|update_|record_|restore_|delete_|dispose_|customer_return$|supplier_return_bundle$|cashbox_manual_entry|save_|start_))' then
    guard:='if exists(select from auth.users where id=ws_actor and raw_app_meta_data->>''staff_kind''=''support'' and not (raw_app_meta_data->''sections'' ? ''operations'')) then raise exception ''Read only'' using errcode=''42501'';end if; '||guard;
   end if;
   execute format('create function public.%I(ws_actor uuid%s) returns %s language plpgsql security definer set search_path=public,pg_temp as %L',
   'ws_'||f.proname,case when f.argdecl='' then '' else ','||f.argdecl end,f.result,
   format('begin perform staff_scoped.authorize($1,%L::text[],%L); %s %s end',scopes,correction,guard,res));
   execute format('revoke all on function public.%I(uuid%s) from public, anon, authenticated','ws_'||f.proname,case when f.pronargs=0 then '' else ','||oidvectortypes(f.proargtypes) end);
   execute format('grant execute on function public.%I(uuid%s) to service_role','ws_'||f.proname,case when f.pronargs=0 then '' else ','||oidvectortypes(f.proargtypes) end);
  end if;
 end loop;
end $install$;
revoke all on all functions in schema staff_scoped from public,anon,authenticated;
create function public.manager_employee_activity(p_start date,p_end date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare lo timestamptz:=p_start::timestamp at time zone 'Asia/Damascus'; hi timestamptz:=(p_end+1)::timestamp at time zone 'Asia/Damascus'; result jsonb;
begin
 if coalesce(pharmacy_branch_private.manager_role(),'') not in ('system_admin','system_owner') then raise exception 'Manager required' using errcode='42501';end if;
 if p_start is null or p_end is null or p_end<p_start or p_end-p_start>366 then raise exception 'Invalid period';end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.name),'[]') into result from (
 select u.id,u.raw_app_meta_data->>'staff_name' name,u.email,
 s.invoices,s.sales,s.profit,s.credit,p.purchase_count,p.purchase_value,d.collections,rt.refunds,a.events
 from auth.users u
 cross join lateral (select count(*) invoices,coalesce(sum(coalesce(x.total_syp,x.total)),0) sales,
 case when count(*) filter(where c.incomplete)>0 then null else coalesce(sum(coalesce(x.total_syp,x.total)-c.cost),0) end profit,
 coalesce(sum(x.due_amount*case when x.currency='USD' then x.fx_rate else 1 end),0) credit from public.sales x
 cross join lateral(select sum(i.unit_cost*i.quantity) cost, count(*)=0 or count(*)<>count(i.unit_cost) incomplete from public.sale_items i where i.sale_id=x.id)c
 where x.created_by=u.id and x.created_at>=lo and x.created_at<hi)s
 cross join lateral(select count(*) purchase_count,coalesce(sum(coalesce(x.total_syp,x.total*case when x.currency='USD' then x.fx_rate else 1 end)),0) purchase_value from public.purchases x where x.created_by=u.id and x.created_at>=lo and x.created_at<hi)p
 cross join lateral(select coalesce(sum(coalesce(x.amount_syp,x.credit*case when x.currency='USD' then x.fx_rate else 1 end)),0) collections from public.debtor_transactions x where x.created_by=u.id and x.transaction_type='payment' and x.created_at>=lo and x.created_at<hi)d
 cross join lateral(select coalesce(sum(coalesce(x.amount_syp,x.amount)),0) refunds from public.returns x where x.created_by=u.id and x.return_type='customer' and x.created_at>=lo and x.created_at<hi)rt
 cross join lateral(select coalesce(jsonb_agg(to_jsonb(v) order by v.created_at desc),'[]') events from (select l.created_at,l.action,l.entity_type from public.audit_logs l where l.user_id=u.id and l.created_at>=lo and l.created_at<hi order by l.created_at desc limit 30)v)a
 where u.role='pharmacy_workspace_only' and u.raw_app_meta_data->>'manager_id'=auth.uid()::text and u.raw_app_meta_data->>'workspace_issuer'='pharmacy_manager_v1' and u.raw_app_meta_data->>'staff_kind'='employee')r;
 return result;
end $$;
revoke all on function public.manager_employee_activity(date,date) from public,anon;
grant execute on function public.manager_employee_activity(date,date) to authenticated;
create function public.manager_staff_change(ws_actor uuid, tab text, op text, target uuid, val jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare scope text; saved uuid; begin
 scope:=case tab when 'offers' then 'offers' when 'prescriptions' then 'prescriptions' when 'medicine_requests' then 'requests' when 'batches' then 'inventory' end;
 perform staff_scoped.authorize(ws_actor,array[scope],op='delete' or tab='batches');
 if exists(select from auth.users where id=ws_actor and raw_app_meta_data->>'staff_kind'='support' and not(raw_app_meta_data->'sections' ? 'operations')) then raise exception 'Read only' using errcode='42501';end if;
 if tab='offers' and op='insert' and length(trim(val->>'title')) between 1 and 500 then
 insert into public.offers(title,description,active) values(val->>'title',val->>'description',(val->>'active')::boolean) returning id into saved;
 elsif tab='offers' and op='update' then update public.offers set active=(val->>'active')::boolean where id=target returning id into saved;
 elsif tab='offers' and op='delete' then delete from public.offers where id=target returning id into saved;
 elsif tab='medicine_requests' and op='update' and val->>'status'='contacted' then update public.medicine_requests set status='contacted' where id=target returning id into saved;
 elsif tab='prescriptions' and op='update' and val->>'status' in ('new','reviewing','ready','completed','rejected') then update public.prescriptions set status=val->>'status' where id=target returning id into saved;
 elsif tab='prescriptions' and op='insert' and starts_with(val->>'file_path','staff/'||ws_actor::text||'/') and exists(select from storage.objects where bucket_id='prescriptions' and name=val->>'file_path') then
 insert into public.prescriptions(file_path,file_name,mime_type,file_size,created_by,status) values(val->>'file_path',val->>'file_name',val->>'mime_type',(val->>'file_size')::bigint,ws_actor,'new') returning id into saved;
 elsif tab='batches' and op='insert' and (val->>'quantity')::numeric>0 and (val->>'purchase_price')::numeric>=0 then
 insert into public.batches(product_id,expiry_date,quantity,purchase_price,purchase_currency,purchase_fx_rate,original_purchase_price,received_date) values((val->>'product_id')::uuid,(val->>'expiry_date')::date,(val->>'quantity')::numeric,(val->>'purchase_price')::numeric,val->>'purchase_currency',(val->>'purchase_fx_rate')::numeric,(val->>'original_purchase_price')::numeric,(val->>'received_date')::date) returning id into saved;
 elsif tab='batches' and op='update' and (val->>'purchase_price')::numeric>=0 then
 update public.batches set expiry_date=(val->>'expiry_date')::date,purchase_price=(val->>'purchase_price')::numeric,purchase_currency=val->>'purchase_currency',purchase_fx_rate=(val->>'purchase_fx_rate')::numeric,original_purchase_price=(val->>'original_purchase_price')::numeric where id=target returning id into saved;
 end if;
 if saved is null then raise exception 'Invalid operation';end if;
 insert into public.audit_logs(user_id,action,entity_type,entity_id) values(ws_actor,op,tab,saved);
end $$;
revoke all on function public.manager_staff_change(uuid,text,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.manager_staff_change(uuid,text,text,uuid,jsonb) to service_role;
