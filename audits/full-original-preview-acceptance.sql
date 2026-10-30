BEGIN;
SELECT set_config('request.jwt.claims','{"role":"service_role"}',true);
DO $$
DECLARE v_admin uuid:='15cdd7b6-cbfa-4607-9364-2787447f7680';v_supplier uuid:='11111111-1111-4111-8111-111111111111';v_name text;v_data jsonb;v_req uuid:=gen_random_uuid();v_payment jsonb;v_n integer;v_failed boolean;
BEGIN
 FOREACH v_name IN ARRAY ARRAY['admin_get_products','admin_get_inventory','admin_products_count','admin_smart_summary','admin_list_sales','admin_list_suppliers','admin_currency_supplier_debt_list_v1','admin_list_purchases_currency_v1','admin_customer_profiles','get_admin_orders','admin_list_debtors','admin_return_list','admin_reorder_recommendations','admin_latest_inventory_count_result','admin_system_healthcheck','admin_cashbox_summary_v2','admin_financial_integrity_check'] LOOP
  v_data:=public.supplier_preview_original_admin_bridge(v_admin,'rpc',v_name,'{}');
 END LOOP;
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'rpc','admin_dashboard_day_details',jsonb_build_object('args',jsonb_build_object('p_start',current_date,'p_end',current_date+1)));
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'rpc','admin_accounting_report',jsonb_build_object('args',jsonb_build_object('p_start',current_date,'p_end',current_date+1)));
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'table','batches','{"action":"select","filters":[{"column":"product_id","op":"eq","value":"22222222-2222-4222-8222-222222222221"}],"orders":[{"column":"expiry_date","ascending":true}]}');
 IF jsonb_array_length(v_data)<>1 OR v_data->0->'products'->>'name' IS NULL THEN RAISE EXCEPTION 'Joined inventory query failed'; END IF;
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'table','offers','{"action":"insert","data":{"title":"اختبار مؤقت","active":true}}');
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'table','offers','{"action":"select","filters":[{"column":"active","op":"eq","value":true}]}');
 IF jsonb_array_length(v_data)<>1 THEN RAISE EXCEPTION 'Table insert/select failed'; END IF;
 v_payment:=public.supplier_preview_original_admin_bridge(v_admin,'rpc','admin_record_supplier_payment_currency_v2',jsonb_build_object('args',jsonb_build_object('p_supplier_id',v_supplier,'p_amount',10,'p_debt_currency','USD','p_tender_currency','USD','p_fx_rate',140,'p_request_id',v_req,'p_notes','رقم وصل الاستلام: FULL-1')));
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'rpc','admin_record_supplier_payment_currency_v2',jsonb_build_object('args',jsonb_build_object('p_supplier_id',v_supplier,'p_amount',10,'p_debt_currency','USD','p_tender_currency','USD','p_fx_rate',140,'p_request_id',v_req,'p_notes','رقم وصل الاستلام: FULL-1')));
 IF v_data->>'duplicate'<>'true' THEN RAISE EXCEPTION 'Retry protection failed'; END IF;
 FOR v_n IN 1..3 LOOP
  v_data:=public.supplier_preview_original_admin_bridge(v_admin,'rpc','admin_record_supplier_payment_currency_v2',jsonb_build_object('args',jsonb_build_object('p_supplier_id',v_supplier,'p_amount',CASE WHEN v_n=1 THEN 1400 WHEN v_n=2 THEN 10 ELSE 140 END,'p_debt_currency',CASE WHEN v_n=1 THEN 'USD' ELSE 'SYP' END,'p_tender_currency',CASE WHEN v_n=2 THEN 'USD' ELSE 'SYP' END,'p_fx_rate',140,'p_request_id',gen_random_uuid(),'p_notes','رقم وصل الاستلام: FULL-'||(v_n+1))));
 END LOOP;
 IF (SELECT sum(due_amount) FROM pharmacy_supplier_stage.purchases WHERE currency='USD')<>130 OR (SELECT sum(due_amount) FROM pharmacy_supplier_stage.purchases WHERE currency='SYP')<>12460 THEN RAISE EXCEPTION 'Debt mismatch'; END IF;
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'rpc','admin_cashbox_summary_v2','{}');
 IF (v_data->>'balance')::numeric<>-4340 OR jsonb_array_length(v_data->'entries')<>4 THEN RAISE EXCEPTION 'Original cashbox integration mismatch'; END IF;
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'rpc','admin_currency_supplier_ledger_v1',jsonb_build_object('args',jsonb_build_object('p_supplier_id',v_supplier,'p_currency','USD')));
 IF jsonb_array_length(v_data->'payments')<>2 OR NOT(v_data->'payments'->0 ? 'tender_currency') THEN RAISE EXCEPTION 'Original ledger integration mismatch'; END IF;
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'rpc','admin_financial_integrity_check','{}');
 IF (v_data->>'purchase_balance_mismatches')::integer<>0 OR (v_data->>'missing_cash_supplier_payments')::integer<>0 THEN RAISE EXCEPTION 'Financial integrity failed'; END IF;
 FOR v_n IN 1..3 LOOP
  v_failed:=false;
  BEGIN
   IF v_n=1 THEN PERFORM public.supplier_preview_original_admin_bridge(gen_random_uuid(),'rpc','admin_products_count','{}');
   ELSIF v_n=2 THEN PERFORM public.supplier_preview_original_admin_bridge(v_admin,'rpc','is_admin','{}');
   ELSE PERFORM public.supplier_preview_original_admin_bridge(v_admin,'table','auth.users','{}'); END IF;
  EXCEPTION WHEN OTHERS THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Unauthorized bridge call accepted'; END IF;
 END LOOP;
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'rpc','complete_sale_accounting_currency','{"args":{"p_currency":"SYP","p_items":[{"product_id":"22222222-2222-4222-8222-222222222221","quantity":1,"unit_price":210}],"p_payment_method":"cash"}}');
 IF (v_data->>'total')::numeric<>210 THEN RAISE EXCEPTION 'Original POS sale failed'; END IF;
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'rpc','admin_cashbox_summary_v2','{}');
 IF (v_data->>'balance')::numeric<>-4130 THEN RAISE EXCEPTION 'POS/cashbox integration failed'; END IF;
 v_data:=public.supplier_preview_original_admin_bridge(v_admin,'rpc','admin_accounting_report',jsonb_build_object('args',jsonb_build_object('p_start',current_date,'p_end',current_date+1)));
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_admin,'role','authenticated')::text,true);
 v_failed:=false;
 BEGIN PERFORM public.supplier_preview_original_admin_bridge(v_admin,'rpc','admin_products_count','{}'); EXCEPTION WHEN OTHERS THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'Client bypassed service gateway'; END IF;
 IF has_function_privilege('authenticated','public.supplier_preview_original_admin_bridge(uuid,text,text,jsonb)','execute') OR has_schema_privilege('authenticated','pharmacy_supplier_stage','usage') THEN RAISE EXCEPTION 'Direct staging access exposed'; END IF;
END $$;
SELECT 'PASS: full dashboard/read APIs, original supplier ledger/cashbox/reports, 4 currency combinations, retries, table queries and access isolation' test_result;
ROLLBACK;
