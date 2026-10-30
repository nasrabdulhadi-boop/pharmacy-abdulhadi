-- All fixtures, settings changes, payments, sales and returns are rolled back.
BEGIN;
SELECT set_config('request.jwt.claims','{"sub":"15cdd7b6-cbfa-4607-9364-2787447f7680","role":"authenticated"}',true);
SELECT set_config('pharmacy_supplier_stage.verified_actor','15cdd7b6-cbfa-4607-9364-2787447f7680',true);
DO $$
DECLARE
 v_supplier uuid:=gen_random_uuid();v_other uuid:=gen_random_uuid();v_product uuid:=gen_random_uuid();
 v_product2 uuid:=gen_random_uuid();v_product3 uuid:=gen_random_uuid();v_invoice uuid;v_invoice2 uuid;v_syp_invoice uuid;
 v_req uuid:=gen_random_uuid();v_cash_id uuid;v_batch uuid;v_sale uuid;v_sale_item uuid;v_data jsonb;v_data2 jsonb;
 v_base_cash numeric;v_base_payments numeric;v_base_profit numeric;v_failed boolean;v_n integer;v_cash_count bigint;v_sale_count bigint;
 v_start timestamptz:=date_trunc('day',now());v_end timestamptz:=date_trunc('day',now())+interval '1 day';
 v_bad jsonb;v_check text;v_name text;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Acceptance principal is not admin'; END IF;
 SELECT coalesce(sum(coalesce(amount_syp,amount)),0) INTO v_base_cash FROM public.cashbox_entries;
 v_data:=public.admin_dashboard_financial_summary(v_start,v_end);v_base_payments:=(v_data->>'supplier_payments')::numeric;v_base_profit:=(v_data->>'profit')::numeric;
 INSERT INTO public.suppliers(id,name) VALUES(v_supplier,'QA ROLLBACK supplier'),(v_other,'QA ROLLBACK unrelated supplier');
 INSERT INTO public.products(id,name,barcode,sale_currency,sale_price) VALUES
  (v_product,'QA ROLLBACK product',gen_random_uuid()::text,'USD',1.5),
  (v_product2,'QA ROLLBACK product2',gen_random_uuid()::text,'USD',1.5),
  (v_product3,'QA ROLLBACK product3',gen_random_uuid()::text,'SYP',210);
 v_data:=public.admin_create_purchase_usd_v1(v_supplier,null,'QA-RB-USD-1',current_date-2,'ROLLBACK ONLY',jsonb_build_array(jsonb_build_object('product_id',v_product,'quantity',100,'purchase_price',1,'sale_price',1.5,'sale_currency','USD','expiry_date',current_date+730)),0,'cash',null,'none',0);
 SELECT id INTO STRICT v_invoice FROM public.purchases WHERE supplier_id=v_supplier AND invoice_number='QA-RB-USD-1';
 v_data:=public.admin_create_purchase_usd_v1(v_supplier,null,'QA-RB-USD-2',current_date-1,'ROLLBACK ONLY',jsonb_build_array(jsonb_build_object('product_id',v_product2,'quantity',50,'purchase_price',1,'sale_price',1.5,'sale_currency','USD','expiry_date',current_date+730)),0,'cash',null,'none',0);
 SELECT id INTO STRICT v_invoice2 FROM public.purchases WHERE supplier_id=v_supplier AND invoice_number='QA-RB-USD-2';
 v_data:=public.admin_create_purchase_syp_v1(v_supplier,null,'QA-RB-SYP',current_date,'ROLLBACK ONLY',jsonb_build_array(jsonb_build_object('product_id',v_product3,'quantity',100,'purchase_price',140,'sale_price',210,'sale_currency','SYP','expiry_date',current_date+730)),0,'cash',null,'none',0);
 SELECT id INTO STRICT v_syp_invoice FROM public.purchases WHERE supplier_id=v_supplier AND currency='SYP';
 v_data:=public.admin_record_supplier_payment_currency_v2(v_supplier,10,'USD','USD',142,v_req,v_invoice,'cash','رقم وصل الاستلام: RB-1');
 v_cash_id:=(v_data->>'cashbox_entry_id')::uuid;
 v_data2:=public.admin_record_supplier_payment_currency_v2(v_supplier,10,'USD','USD',142,v_req,v_invoice,'cash','رقم وصل الاستلام: RB-1');
 IF v_data2->>'duplicate'<>'true' OR v_data2->>'payment_id'<>v_data->>'payment_id' THEN RAISE EXCEPTION 'Duplicate prevention failed'; END IF;
 PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,1420,'USD','SYP',142,gen_random_uuid(),null,'cash','رقم وصل الاستلام: RB-2');
 PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,10,'SYP','USD',142,gen_random_uuid(),null,'cash','رقم وصل الاستلام: RB-3');
 PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,140,'SYP','SYP',142,gen_random_uuid(),null,'cash','رقم وصل الاستلام: RB-4');
 IF (SELECT sum(due_amount) FROM public.purchases WHERE supplier_id=v_supplier AND currency='USD')<>130 OR
    (SELECT sum(due_amount) FROM public.purchases WHERE supplier_id=v_supplier AND currency='SYP')<>12440 THEN RAISE EXCEPTION 'Currency debt isolation failed'; END IF;
 v_data:=public.admin_cashbox_summary_v2(null,null);
 IF (v_data->>'balance')::numeric<>v_base_cash-4400 THEN RAISE EXCEPTION 'Cashbox balance mismatch'; END IF;
 v_data:=public.admin_accounting_report(v_start,v_end,null,null);
 IF (v_data->'summary'->>'cash_balance')::numeric<>v_base_cash-4400 THEN RAISE EXCEPTION 'Accounting balance uses wrong currency'; END IF;
 SELECT value INTO v_data2 FROM jsonb_array_elements(v_data->'cash_rows') WHERE value->>'id'=v_cash_id::text;
 IF (v_data2->>'amount')::numeric<>-1420 OR (v_data2->>'original_amount')::numeric<>-10 OR v_data2->>'currency'<>'USD' THEN RAISE EXCEPTION 'Report currency detail failed'; END IF;
 v_data:=public.admin_dashboard_financial_summary(v_start,v_end);
 IF (v_data->>'profit')::numeric<>v_base_profit THEN RAISE EXCEPTION 'Supplier debt payment changed operating profit'; END IF;
 IF (v_data->>'supplier_payments')::numeric<>v_base_payments+4400 THEN RAISE EXCEPTION 'Supplier payment report mismatch'; END IF;
 v_data:=public.admin_currency_purchase_detail_v1(v_invoice);
 IF jsonb_array_length(v_data->'payments')<>2 OR NOT(v_data->'payments'->0 ? 'tender_currency') THEN RAISE EXCEPTION 'Purchase payment metadata missing'; END IF;
 v_data:=public.admin_currency_supplier_ledger_v1(v_supplier,'USD');
 IF jsonb_array_length(v_data->'payments')<>2 OR (v_data->'summary'->>'balance')::numeric<>130 THEN RAISE EXCEPTION 'Supplier ledger mismatch'; END IF;
 UPDATE public.pharmacy_currency_settings SET usd_to_syp=150 WHERE id=1;
 v_data:=public.admin_cashbox_summary_v2(null,null);
 IF (v_data->>'balance')::numeric<>v_base_cash-4400 THEN RAISE EXCEPTION 'Old payment revalued after rate change'; END IF;
 SELECT count(*) INTO v_cash_count FROM public.cashbox_entries;
 PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,5,'USD','USD',200,gen_random_uuid(),null,'other','رقم وصل الاستلام: RB-NONCASH');
 IF (SELECT count(*) FROM public.cashbox_entries)<>v_cash_count THEN RAISE EXCEPTION 'Noncash affected drawer'; END IF;
 PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,14200,'USD','SYP',142,gen_random_uuid(),null,'cash','رقم وصل الاستلام: RB-SPLIT');
 IF (SELECT count(*) FROM public.supplier_payment_allocations a JOIN public.supplier_payments p ON p.id=a.payment_id WHERE p.supplier_id=v_supplier AND p.notes='رقم وصل الاستلام: RB-SPLIT')<>2 THEN RAISE EXCEPTION 'Oldest-invoice split failed'; END IF;
 v_data:=public.admin_currency_purchase_detail_v1(v_invoice2);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_data->'payments') p WHERE (p->>'amount')::numeric=25 AND (p->>'tender_amount')::numeric=14200 AND p->>'tender_currency'='SYP') THEN RAISE EXCEPTION 'Split payment shown as wrong tender'; END IF;
 PERFORM public.admin_record_supplier_payment_usd_v1(v_supplier,1,v_invoice2,'cash','Legacy rollback test');
 IF (SELECT sum(due_amount) FROM public.purchases WHERE supplier_id=v_supplier AND currency='USD')<>24 THEN RAISE EXCEPTION 'Legacy payment compatibility failed'; END IF;
 PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,1,'USD','SYP',142,gen_random_uuid(),null,'cash','رقم وصل الاستلام: RB-FRACTION');
 IF (SELECT sum(due_amount) FROM public.purchases WHERE supplier_id=v_supplier AND currency='USD')<>23.992958 THEN RAISE EXCEPTION 'Fractional settlement mismatch'; END IF;
 FOR v_n IN 1..9 LOOP
  v_failed:=false;
  BEGIN
   CASE v_n
    WHEN 1 THEN PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,999999,'USD','USD',142,gen_random_uuid(),null,'cash','رقم وصل الاستلام: BAD');
    WHEN 2 THEN PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,1,'USD','USD',142,gen_random_uuid(),null,'cash','');
    WHEN 3 THEN PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,1,'USD','USD',0,gen_random_uuid(),null,'cash','رقم وصل الاستلام: BAD');
    WHEN 4 THEN PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,'NaN','USD','USD',142,gen_random_uuid(),null,'cash','رقم وصل الاستلام: BAD');
    WHEN 5 THEN PERFORM public.admin_record_supplier_payment_currency_v2(v_other,1,'USD','USD',142,gen_random_uuid(),v_invoice,'cash','رقم وصل الاستلام: BAD');
    WHEN 6 THEN PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,11,'USD','USD',142,v_req,v_invoice,'cash','رقم وصل الاستلام: RB-1');
    WHEN 7 THEN PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,1,'SYP','SYP',142,gen_random_uuid(),v_invoice2,'cash','رقم وصل الاستلام: BAD');
    WHEN 8 THEN PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,0.001,'USD','USD',142,gen_random_uuid(),null,'cash','رقم وصل الاستلام: BAD');
    WHEN 9 THEN PERFORM public.admin_delete_purchase(v_invoice);
   END CASE;
  EXCEPTION WHEN OTHERS THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Invalid/unsafe operation accepted: %',v_n; END IF;
 END LOOP;
 SELECT count(*) INTO v_sale_count FROM public.sales;
 v_failed:=false;
 BEGIN PERFORM public.complete_sale_accounting_currency('SYP',null,0,null,jsonb_build_array(jsonb_build_object('product_id',v_product,'quantity',10000,'unit_price',213)),null,'cash'); EXCEPTION WHEN OTHERS THEN v_failed:=true; END;
 IF NOT v_failed OR (SELECT count(*) FROM public.sales)<>v_sale_count THEN RAISE EXCEPTION 'Insufficient stock sale failed atomically'; END IF;
 v_data:=public.complete_sale_accounting_currency('SYP',null,0,null,jsonb_build_array(jsonb_build_object('product_id',v_product,'quantity',1,'unit_price',213)),null,'cash');v_sale:=(v_data->>'sale_id')::uuid;
 SELECT id INTO STRICT v_sale_item FROM public.sale_items WHERE sale_id=v_sale;
 PERFORM public.admin_customer_return(v_sale_item,1,'Rollback customer return');
 SELECT id INTO STRICT v_batch FROM public.batches WHERE purchase_id=v_invoice;
 PERFORM public.admin_currency_supplier_return_v2(v_invoice,'selected',jsonb_build_array(jsonb_build_object('batch_id',v_batch,'quantity',1)),'Rollback supplier return');
 v_data:=public.admin_currency_purchase_detail_v1(v_invoice);
 IF (v_data->>'refund_due')::numeric<>1 THEN RAISE EXCEPTION 'Supplier return/refund balance mismatch'; END IF;
 PERFORM public.admin_currency_supplier_refund_receipt_v1(v_invoice,1,'cash','Rollback supplier refund');
 v_data:=public.admin_financial_integrity_check();
 FOREACH v_check IN ARRAY ARRAY['missing_cash_supplier_payments','supplier_payment_cash_mismatches','supplier_payment_allocation_mismatches','purchase_balance_mismatches','missing_cash_sales','missing_customer_refunds','returns_without_stock_movement'] LOOP
  IF (v_data->>v_check)::numeric<>0 THEN RAISE EXCEPTION 'Integrity failure: % = %',v_check,v_data->>v_check; END IF;
 END LOOP;
 FOREACH v_name IN ARRAY ARRAY['admin_get_products','admin_get_inventory','admin_products_count','admin_smart_summary','admin_list_sales','admin_list_suppliers','admin_currency_supplier_debt_list_v1','admin_list_purchases_currency_v1','admin_customer_profiles','get_admin_orders','admin_list_debtors','admin_return_list','admin_reorder_recommendations','admin_latest_inventory_count_result','admin_system_healthcheck'] LOOP
  -- Only existing read endpoints; dynamic dispatch cannot select other schemas.
  EXECUTE format('SELECT to_jsonb(x) FROM public.%I() x LIMIT 1',v_name) INTO v_data;
 END LOOP;
 v_data:=public.admin_accounting_report(v_start,v_end,null,null);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
 v_failed:=false;
 BEGIN PERFORM public.admin_record_supplier_payment_currency_v2(v_supplier,1,'USD','USD',142,gen_random_uuid(),null,'cash','رقم وصل الاستلام: DENIED'); EXCEPTION WHEN OTHERS THEN v_failed:=true; END;
 IF NOT v_failed THEN RAISE EXCEPTION 'Nonadmin payment accepted'; END IF;
 IF has_function_privilege('anon','public.admin_record_supplier_payment_currency_v2(uuid,numeric,text,text,numeric,uuid,uuid,text,text)','execute') THEN RAISE EXCEPTION 'Anonymous payment execution exposed'; END IF;
END $$;
SELECT 'PASS: original reads, POS, purchase/supplier/cashbox/report/return/refund integration; all currency combinations; fractional math; retries; rate freeze; noncash; security; every fixture rolled back' test_result;
ROLLBACK;
