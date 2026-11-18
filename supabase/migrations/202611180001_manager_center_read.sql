create function public.manager_center_members()
returns table(email text, role text, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select u.email::text, coalesce(u.raw_app_meta_data->>'system_role',u.raw_app_meta_data->>'role','unassigned'), u.created_at
  from auth.users u
  where exists (select 1 from auth.users actor where actor.id=auth.uid()
    and coalesce(actor.raw_app_meta_data->>'system_role',actor.raw_app_meta_data->>'role') in ('admin','system_owner','system_admin'))
  order by u.created_at;
$$;
revoke all on function public.manager_center_members() from public, anon, authenticated;
grant execute on function public.manager_center_members() to authenticated;

create function public.manager_center_data_archive()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  table_name text;
  numeric_fields text;
  data_rows jsonb;
  tables jsonb := '[]';
  allowed_tables constant text[] := array['audit_logs','batches','cashbox_counts','cashbox_entries','customers','debtor_transactions','debtors','inventory_count_items','inventory_counts','medicine_requests','offers','order_items','orders','pharmacy_currency_history','pharmacy_currency_settings','pharmacy_settings','pos_shortcut_preferences','prescriptions','product_barcodes','products','purchase_items','purchases','returns','sale_invoice_numbers','sale_items','sales','stock_movements','supplier_advance_applications','supplier_advance_lots','supplier_payment_allocations','supplier_payments','supplier_purchase_requests','supplier_refund_receipts','suppliers'];
begin
  if not exists (select 1 from auth.users actor where actor.id=auth.uid()
    and coalesce(actor.raw_app_meta_data->>'system_role',actor.raw_app_meta_data->>'role') in ('admin','system_owner','system_admin')) then
    raise exception 'manager_required' using errcode='42501';
  end if;
  foreach table_name in array allowed_tables loop
    select string_agg(format('%L, to_jsonb(r.%I::text)',a.attname,a.attname),',') into numeric_fields
    from pg_catalog.pg_attribute a where a.attrelid=format('public.%I',table_name)::regclass and a.attnum>0 and not a.attisdropped
    and a.atttypid in ('pg_catalog.int8'::regtype,'pg_catalog.numeric'::regtype);
    execute format('select coalesce(jsonb_agg(to_jsonb(r)%s),''[]''::jsonb) from public.%I r',
      case when numeric_fields is null then '' else ' || jsonb_build_object('||numeric_fields||')' end,table_name) into data_rows;
    tables := tables || jsonb_build_array(jsonb_build_object('name',table_name,'row_count',jsonb_array_length(data_rows),'rows',data_rows));
  end loop;
  return jsonb_build_object('format','pharmacy-manager-data-v1','created_at',statement_timestamp(),'tables',tables);
end;
$$;
revoke all on function public.manager_center_data_archive() from public,anon,authenticated;
grant execute on function public.manager_center_data_archive() to authenticated;
