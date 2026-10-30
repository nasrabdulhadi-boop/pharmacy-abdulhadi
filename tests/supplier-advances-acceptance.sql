-- All business fixtures and test operations roll back. No sequences are used.
BEGIN;
SELECT set_config('request.jwt.claims','{"sub":"15cdd7b6-cbfa-4607-9364-2787447f7680","role":"authenticated"}',true);
SELECT set_config('pharmacy_supplier_stage.verified_actor','15cdd7b6-cbfa-4607-9364-2787447f7680',true);
DO $$
DECLARE s uuid:=gen_random_uuid();s2 uuid:=gen_random_uuid();s3 uuid:=gen_random_uuid();p uuid:=gen_random_uuid();
 i uuid;i2 uuid;i3 uuid;v_req uuid:=gen_random_uuid();v_req2 uuid:=gen_random_uuid();v_result jsonb;v_again jsonb;v_payload jsonb;
 v_cash numeric;v_current numeric;v_profit numeric;v_fx numeric;v_qty numeric;v_payment_count bigint;v_invoice_count bigint;
 v_count bigint;v_used numeric;v_failed boolean;v_case integer;v_item uuid;v_batch uuid;v_sale uuid;
 v_start timestamptz:=date_trunc('day',now());v_end timestamptz:=date_trunc('day',now())+interval '1 day';
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Test principal is not admin'; END IF;
 SELECT usd_to_syp INTO v_fx FROM public.pharmacy_currency_settings WHERE id=1;
 SELECT coalesce(sum(coalesce(amount_syp,amount)),0) INTO v_cash FROM public.cashbox_entries;
 v_result:=public.admin_dashboard_financial_summary(v_start,v_end);v_profit:=(v_result->>'profit')::numeric;
 INSERT INTO public.suppliers(id,name) VALUES(s,'QA ADV supplier'),(s2,'QA ADV discount supplier'),(s3,'QA ADV deposit only');
 INSERT INTO public.products(id,name,barcode,sale_currency,sale_price) VALUES(p,'QA ADV product',gen_random_uuid()::text,'USD',2);
 v_payload:=jsonb_build_array(jsonb_build_object('product_id',p,'quantity',100,'purchase_price',1,'sale_price',2,'sale_currency','USD','expiry_date',current_date+730));
 v_result:=public.admin_create_purchase_with_advance_v3('USD',s,null,'QA-ADV-1',current_date,null,v_payload,120,'cash','رقم وصل الاستلام: ADV-120','none',0,v_req,0);
 i:=(v_result->>'id')::uuid;
 IF (v_result->>'paid_amount')::numeric<>100 OR (v_result->>'due_amount')::numeric<>0 OR (v_result->>'advance_created')::numeric<>20 THEN RAISE EXCEPTION '100 paid 120 failed: %',v_result; END IF;
 v_again:=public.admin_create_purchase_with_advance_v3('USD',s,null,'QA-ADV-1',current_date,null,v_payload,120,'cash','رقم وصل الاستلام: ADV-120','none',0,v_req,0);
 IF v_again->>'duplicate'<>'true' OR v_again->>'id'<>i::text THEN RAISE EXCEPTION 'Purchase retry duplicated money/inventory'; END IF;
 IF (SELECT count(*) FROM public.purchases WHERE supplier_id=s)<>1 THEN RAISE EXCEPTION 'Duplicate invoice inserted'; END IF;
 v_result:=public.admin_currency_supplier_ledger_v1(s,'USD');
 IF (v_result->'summary'->>'advance_credit')::numeric<>20 OR (v_result->'summary'->>'balance')::numeric<>0 THEN RAISE EXCEPTION 'Ledger sign/credit failed'; END IF;
 IF (v_result->'payments'->0->>'settled_amount')::numeric<>100 OR (v_result->'payments'->0->>'tender_amount')::numeric<>120 THEN RAISE EXCEPTION 'Tender vs settlement display failed'; END IF;
 SELECT coalesce(sum(coalesce(amount_syp,amount)),0) INTO v_current FROM public.cashbox_entries;
 IF v_current<>v_cash-120*v_fx THEN RAISE EXCEPTION 'Entire actual overpayment was not recorded once'; END IF;
 -- Legacy purchase endpoints must also automatically consume credit.
 v_result:=public.admin_create_purchase_usd_v1(s,null,'QA-ADV-2',current_date,null,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',50,'purchase_price',1,'sale_price',2,'sale_currency','USD','expiry_date',current_date+730)),0,'cash',null,'none',0);
 i2:=(v_result->>'id')::uuid;
 IF (v_result->>'applied_advance')::numeric<>20 OR (v_result->>'due_amount')::numeric<>30 THEN RAISE EXCEPTION 'Auto credit consumption failed'; END IF;
 IF (SELECT coalesce(sum(coalesce(amount_syp,amount)),0) FROM public.cashbox_entries)<>v_current THEN RAISE EXCEPTION 'Credit consumption duplicated cash movement'; END IF;
 v_result:=public.admin_record_supplier_payment_advance_v3(s,70,'USD','USD',v_fx,v_req2,null,'cash','رقم وصل الاستلام: ADV-70');
 IF (v_result->>'settled_amount')::numeric<>30 OR (v_result->>'advance_amount')::numeric<>40 THEN RAISE EXCEPTION 'Debt payment surplus failed'; END IF;
 v_again:=public.admin_record_supplier_payment_advance_v3(s,70,'USD','USD',v_fx,v_req2,null,'cash','رقم وصل الاستلام: ADV-70');
 IF v_again->>'duplicate'<>'true' THEN RAISE EXCEPTION 'Payment retry failed'; END IF;
 -- A different-currency invoice must not use USD credit.
 v_result:=public.admin_create_purchase_syp_v1(s,null,'QA-ADV-SYP',current_date,null,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1,'purchase_price',140,'sale_price',210,'sale_currency','SYP','expiry_date',current_date+730)),0,'cash',null,'none',0);
 IF (v_result->>'applied_advance')::numeric<>0 OR (v_result->>'due_amount')::numeric<>140 THEN RAISE EXCEPTION 'Currency isolation failed'; END IF;
 PERFORM public.admin_record_supplier_payment_advance_v3(s,200,'SYP','SYP',1,gen_random_uuid(),null,'cash','رقم وصل الاستلام: ADV-SYP');
 IF (public.admin_supplier_advance_summary_v1(s,'USD')->>'advance_credit')::numeric<>40 OR (public.admin_supplier_advance_summary_v1(s,'SYP')->>'advance_credit')::numeric<>60 THEN RAISE EXCEPTION 'Currency balances mixed'; END IF;
 -- Existing credit covers the entire invoice; a new cash payment is entirely a new advance.
 v_result:=public.admin_create_purchase_usd_v1(s,null,'QA-ADV-COVERED',current_date,null,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',5,'purchase_price',1,'sale_price',2,'sale_currency','USD','expiry_date',current_date+730)),10,'cash','رقم وصل الاستلام: ADV-COVERED','none',0);
 i3:=(v_result->>'id')::uuid;
 IF (v_result->>'applied_advance')::numeric<>5 OR (v_result->>'advance_created')::numeric<>10 OR (v_result->>'paid_amount')::numeric<>5 THEN RAISE EXCEPTION 'Covered invoice plus new advance failed'; END IF;
 v_result:=public.admin_currency_purchase_detail_v1(i3);
 IF (v_result->>'advance_created')::numeric<>10 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result->'payments') x WHERE (x->>'amount')::numeric=0 AND (x->>'advance_created')::numeric=10) THEN RAISE EXCEPTION 'Unallocated invoice payment disappeared from details'; END IF;
 -- Pure advance without invoices must appear in the main supplier account list.
 SELECT count(*) INTO v_payment_count FROM public.cashbox_entries;
 PERFORM public.admin_record_supplier_payment_advance_v3(s3,15,'USD','USD',v_fx,gen_random_uuid(),null,'other','رقم وصل الاستلام: ADV-NONCASH');
 IF (SELECT count(*) FROM public.cashbox_entries)<>v_payment_count THEN RAISE EXCEPTION 'Noncash advance touched drawer'; END IF;
 v_result:=public.admin_currency_supplier_debt_list_v1();
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_result) x WHERE x->>'id'=s3::text AND (x->>'invoice_count')::numeric=0 AND (x->>'advance_credit')::numeric=15 AND (x->>'balance')::numeric=0) THEN RAISE EXCEPTION 'No-invoice credit account missing'; END IF;
 -- Discount affects the invoice only, never the actual tender or bonus stock.
 v_result:=public.admin_create_purchase_usd_v1(s2,null,'QA-ADV-DISCOUNT',current_date,null,v_payload,110,'cash','رقم وصل الاستلام: ADV-DISCOUNT','percent',10);
 IF (v_result->>'total')::numeric<>90 OR (v_result->>'advance_created')::numeric<>20 OR (v_result->>'paid_amount')::numeric<>90 THEN RAISE EXCEPTION 'Discount/overpayment mismatch'; END IF;
 -- Stale UI credit quote must reject before creating inventory/invoice.
 SELECT count(*) INTO v_invoice_count FROM public.purchases;
 v_failed:=false;BEGIN PERFORM public.admin_create_purchase_with_advance_v3('USD',s,null,'QA-STALE',current_date,null,v_payload,0,'cash',null,'none',0,gen_random_uuid(),999);EXCEPTION WHEN OTHERS THEN v_failed:=true;END;
 IF NOT v_failed OR (SELECT count(*) FROM public.purchases)<>v_invoice_count THEN RAISE EXCEPTION 'Stale credit quote changed invoice/inventory'; END IF;
 -- Changed retry payload, invalid money, missing receipt and invoice owner/currency errors.
 FOR v_case IN 1..6 LOOP
  v_failed:=false;BEGIN
   CASE v_case
    WHEN 1 THEN PERFORM public.admin_record_supplier_payment_advance_v3(s,71,'USD','USD',v_fx,v_req2,null,'cash','رقم وصل الاستلام: ADV-70');
    WHEN 2 THEN PERFORM public.admin_record_supplier_payment_advance_v3(s,-1,'USD','USD',v_fx,gen_random_uuid(),null,'cash','رقم وصل الاستلام: BAD');
    WHEN 3 THEN PERFORM public.admin_record_supplier_payment_advance_v3(s,1,'USD','USD',v_fx,gen_random_uuid(),null,'cash','');
    WHEN 4 THEN PERFORM public.admin_record_supplier_payment_advance_v3(s,1,'SYP','SYP',1,gen_random_uuid(),i,'cash','رقم وصل الاستلام: BAD');
    WHEN 5 THEN PERFORM public.admin_record_supplier_payment_advance_v3(s2,1,'USD','USD',v_fx,gen_random_uuid(),i,'cash','رقم وصل الاستلام: BAD');
    WHEN 6 THEN PERFORM public.admin_create_purchase_with_advance_v3('USD',s,null,'CHANGED',current_date,null,v_payload,120,'cash','رقم وصل الاستلام: ADV-120','none',0,v_req,0);
   END CASE;
  EXCEPTION WHEN OTHERS THEN v_failed:=true;END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Unsafe operation accepted %',v_case;END IF;
 END LOOP;
 -- Cross-currency surplus remains in the supplier account currency at the frozen rate.
 DECLARE sx uuid:=gen_random_uuid();sy uuid:=gen_random_uuid();x jsonb;cb numeric; BEGIN
 INSERT INTO public.suppliers(id,name) VALUES(sx,'QA FX USD advance'),(sy,'QA FX SYP advance');
 PERFORM public.admin_create_purchase_usd_v1(sx,null,'QA-FX-USD',current_date,null,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',10,'purchase_price',1,'sale_price',2,'sale_currency','USD','expiry_date',current_date+730)),0,'cash',null,'none',0);
 x:=public.admin_record_supplier_payment_advance_v3(sx,2100,'USD','SYP',140,gen_random_uuid(),null,'cash','رقم وصل الاستلام: FX-USD');
 IF (x->>'settled_amount')::numeric<>10 OR (x->>'advance_amount')::numeric<>5 THEN RAISE EXCEPTION 'SYP paid on USD account surplus failed'; END IF;
 SELECT sum(coalesce(amount_syp,amount)) INTO cb FROM public.cashbox_entries;
 UPDATE public.pharmacy_currency_settings SET usd_to_syp=150 WHERE id=1;
 x:=public.admin_create_purchase_usd_v1(sx,null,'QA-FX-USD-USE',current_date,null,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',10,'purchase_price',1,'sale_price',2,'sale_currency','USD','expiry_date',current_date+730)),0,'cash',null,'none',0);
 IF (x->>'applied_advance')::numeric<>5 OR (x->>'due_amount')::numeric<>5 OR (SELECT sum(coalesce(amount_syp,amount)) FROM public.cashbox_entries)<>cb THEN RAISE EXCEPTION 'Rate change revalued advance/cash'; END IF;
 UPDATE public.pharmacy_currency_settings SET usd_to_syp=v_fx WHERE id=1;
 PERFORM public.admin_create_purchase_syp_v1(sy,null,'QA-FX-SYP',current_date,null,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1,'purchase_price',1000,'sale_price',2000,'sale_currency','SYP','expiry_date',current_date+730)),0,'cash',null,'none',0);
 x:=public.admin_record_supplier_payment_advance_v3(sy,10,'SYP','USD',140,gen_random_uuid(),null,'cash','رقم وصل الاستلام: FX-SYP');
 IF (x->>'settled_amount')::numeric<>1000 OR (x->>'advance_amount')::numeric<>400 THEN RAISE EXCEPTION 'USD paid on SYP account surplus failed'; END IF;
 x:=public.admin_create_purchase_syp_v1(sy,null,'QA-FX-SYP-USE',current_date,null,jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1,'purchase_price',600,'sale_price',1200,'sale_currency','SYP','expiry_date',current_date+730)),0,'cash',null,'none',0);
 IF (x->>'applied_advance')::numeric<>400 OR (x->>'due_amount')::numeric<>200 THEN RAISE EXCEPTION 'Converted SYP advance reuse failed'; END IF;
 END;
 IF has_function_privilege('anon','public.admin_record_supplier_payment_advance_v3(uuid,numeric,text,text,numeric,uuid,uuid,text,text)','execute') OR has_function_privilege('anon','public.admin_create_purchase_with_advance_v3(text,uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric,uuid,numeric)','execute') OR has_function_privilege('authenticated','public.apply_supplier_advances_to_purchase_v1(uuid)','execute') OR has_function_privilege('authenticated','public._ab_create_purchase_usd_core_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric)','execute') THEN RAISE EXCEPTION 'Private/anonymous financial endpoint exposed'; END IF;
 -- Settlements/advances do not change gross profit or add extra stock.
 v_result:=public.admin_dashboard_financial_summary(v_start,v_end);
 IF (v_result->>'profit')::numeric<>v_profit THEN RAISE EXCEPTION 'Advance treated as operating expense'; END IF;
 IF NOT(v_result ? 'supplier_advances') THEN RAISE EXCEPTION 'Report credit section missing'; END IF;
 v_result:=public.admin_accounting_report(v_start,v_end,null,null);
 IF NOT(v_result ? 'supplier_advances') THEN RAISE EXCEPTION 'Accounting credit section missing'; END IF;
 -- A supplier return/refund remains an invoice credit/refund; it cannot duplicate advance credit.
 v_current:=(public.admin_supplier_advance_summary_v1(s,'USD')->>'advance_credit')::numeric;
 SELECT id INTO v_batch FROM public.batches WHERE purchase_id=i LIMIT 1;
 PERFORM public.admin_currency_supplier_return_v2(i,'selected',jsonb_build_array(jsonb_build_object('batch_id',v_batch,'quantity',1)),'QA supplier return');
 PERFORM public.admin_currency_supplier_refund_receipt_v1(i,1,'cash','QA refund');
 IF (public.admin_supplier_advance_summary_v1(s,'USD')->>'advance_credit')::numeric<>v_current THEN RAISE EXCEPTION 'Supplier return duplicated advance balance'; END IF;
 v_result:=public.admin_financial_integrity_check();
 IF (v_result->>'supplier_advance_invalid_balances')::numeric<>0 OR (v_result->>'supplier_payment_allocation_mismatches')::numeric<>0 OR (v_result->>'supplier_payments_without_allocations')::numeric<>0 OR (v_result->>'supplier_payment_cash_mismatches')::numeric<>0 OR (v_result->>'purchase_balance_mismatches')::numeric<>0 THEN RAISE EXCEPTION 'Financial integrity failed: %',v_result; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
 v_failed:=false;BEGIN PERFORM public.admin_supplier_advance_summary_v1(s,'USD');EXCEPTION WHEN OTHERS THEN v_failed:=true;END;
 IF NOT v_failed THEN RAISE EXCEPTION 'Nonadmin read advance balance';END IF;
END $$;
SELECT 'PASS: surplus purchases/payments, automatic reuse, no double cash, no-invoice accounts, currency isolation, discounts, retries, stale quotes, reports, return/refund, security; all test rows rolled back' result;
ROLLBACK;
