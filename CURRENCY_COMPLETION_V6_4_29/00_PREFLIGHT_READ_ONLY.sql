-- Read-only verification before any schema change. Run on a staging copy.
SELECT 'currency_rate' AS check_name, usd_to_syp::text AS result FROM public.pharmacy_currency_settings WHERE id=1;
SELECT 'purchases' AS check_name, COUNT(*)::text AS result FROM public.purchases
UNION ALL SELECT 'supplier_payments', COUNT(*)::text FROM public.supplier_payments
UNION ALL SELECT 'supplier_payment_allocations', COUNT(*)::text FROM public.supplier_payment_allocations
UNION ALL SELECT 'batches', COUNT(*)::text FROM public.batches
UNION ALL SELECT 'products', COUNT(*)::text FROM public.products;
-- Inspect any pre-existing currency columns; do not assume migration was never partially run.
SELECT table_name,column_name,data_type,column_default FROM information_schema.columns
WHERE table_schema='public' AND table_name IN
('purchases','purchase_items','batches','supplier_payments','supplier_payment_allocations','returns')
AND (column_name ILIKE '%currency%' OR column_name ILIKE '%fx%' OR column_name ILIKE '%syp%' OR column_name ILIKE '%original%')
ORDER BY table_name,column_name;
