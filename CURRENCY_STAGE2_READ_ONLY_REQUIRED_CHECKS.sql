-- صيدلية عبدالهادي — Currency Phase 2 / READ ONLY / SELECT only.
-- No data or schema is changed by these statements.
-- Run individually in Supabase SQL Editor, and export the results.

-- Q1) Actual columns needed before adding supplier USD ledger (no customer records)
SELECT table_name,column_name,data_type,is_nullable,column_default
FROM information_schema.columns
WHERE table_schema='public'
AND table_name IN (
  'supplier_payments','supplier_payment_allocations','purchases','purchase_items',
  'batches','returns','products','sales','sale_items',
  'pharmacy_currency_settings','pharmacy_currency_history')
AND (table_name IN ('supplier_payments','supplier_payment_allocations','pharmacy_currency_settings')
     OR column_name IN ('id','currency','sale_currency','purchase_price','sale_price',
      'subtotal','total','total_syp','amount','amount_syp','fx_rate','paid_amount',
      'due_amount','purchase_id','purchase_item_id','supplier_payment_id','sale_id',
      'unit_cost','unit_price','price_currency','price_fx_rate','base_unit_price'))
ORDER BY table_name,ordinal_position;

-- Q2) How many old invoices/payments and totals exist? Aggregated; no names/IDs.
SELECT 'purchases' record_type, COUNT(*) row_count, COALESCE(SUM(total),0) amount
FROM public.purchases
UNION ALL
SELECT 'supplier_payments', COUNT(*), COALESCE(SUM(amount),0) FROM public.supplier_payments
UNION ALL
SELECT 'supplier_payment_allocations', COUNT(*), COALESCE(SUM(amount),0) FROM public.supplier_payment_allocations;

-- Q3) Cashbox integrity: amounts that are not consistently recorded in SYP
SELECT currency,fx_rate,COUNT(*) AS entry_count,
 COUNT(*) FILTER (WHERE amount_syp IS NULL) AS missing_amount_syp,
 COUNT(*) FILTER (WHERE currency='SYP' AND amount_syp IS DISTINCT FROM amount) AS inconsistent_syp_amount,
 COALESCE(SUM(amount),0) AS native_amount_sum,
 COALESCE(SUM(amount_syp),0) AS amount_syp_sum
FROM public.cashbox_entries GROUP BY currency,fx_rate ORDER BY currency,fx_rate;

-- Q4) Customer debt: inspect aggregate currency safety
SELECT currency,fx_rate,COUNT(*) AS entry_count,
 COUNT(*) FILTER (WHERE amount_syp IS NULL) AS missing_amount_syp,
 COUNT(*) FILTER (WHERE currency='SYP' AND amount_syp IS DISTINCT FROM amount) AS inconsistent_syp_amount
FROM public.debtor_transactions GROUP BY currency,fx_rate ORDER BY currency,fx_rate;

-- Q5) Historical sale currency usage and whether SYP subtotal agrees with recorded total_syp
SELECT currency,fx_rate,COUNT(*) AS sales_count,
 COUNT(*) FILTER (WHERE total_syp IS NULL) AS missing_total_syp,
 COUNT(*) FILTER (WHERE currency='SYP' AND total_syp IS DISTINCT FROM total) AS syp_total_mismatch
FROM public.sales GROUP BY currency,fx_rate ORDER BY currency,fx_rate;

-- Q6) Product price currency distribution (aggregates only)
SELECT sale_currency,COUNT(*) AS products_count
FROM public.products GROUP BY sale_currency ORDER BY sale_currency;

-- Q7) Database triggers affecting money / stock / payment allocation
SELECT c.relname AS table_name, t.tgname AS trigger_name,
 pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND NOT t.tgisinternal
AND c.relname IN ('purchases','purchase_items','supplier_payments',
 'supplier_payment_allocations','batches','returns','cashbox_entries','sales','sale_items')
ORDER BY c.relname,t.tgname;

-- Q8) Definitions of functions that update purchase payment balances or customer debt
SELECT p.proname AS function_name,
 pg_get_function_identity_arguments(p.oid) AS arguments,
 pg_get_functiondef(p.oid) AS definition
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
 ('admin_refresh_purchase_balance','admin_record_debtor_payment',
  'admin_cashbox_reconcile','admin_cashbox_summary_v2',
  'admin_get_purchase_detail','admin_supplier_return_options',
  'admin_return_list','admin_search_pos_products_currency')
ORDER BY p.proname;
