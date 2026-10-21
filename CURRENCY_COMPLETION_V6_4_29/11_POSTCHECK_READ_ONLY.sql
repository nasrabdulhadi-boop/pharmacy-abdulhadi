-- Read only. Run after staging migration, then separately after any production rollout.
-- Per-currency amounts are NEVER summed across USD and SYP.
SELECT currency,COUNT(*) invoice_count,SUM(total) native_total,SUM(paid_amount) native_paid,
 SUM(due_amount) native_due,SUM(CASE WHEN currency='USD' THEN total_syp ELSE total END) total_syp
 FROM public.purchases GROUP BY currency ORDER BY currency;
SELECT currency,COUNT(*) payment_count,SUM(amount) native_payments,SUM(COALESCE(amount_syp,amount)) payment_equiv_syp
 FROM public.supplier_payments GROUP BY currency;
SELECT 'bad_supplier_currency_links' check_name,COUNT(*) result
 FROM public.supplier_payment_allocations spa
 JOIN public.supplier_payments sp ON sp.id=spa.payment_id
 JOIN public.purchases p ON p.id=spa.purchase_id
 WHERE spa.currency<>sp.currency OR spa.currency<>p.currency OR sp.supplier_id<>p.supplier_id
UNION ALL
SELECT 'usd_purchase_fx_invalid',COUNT(*) FROM public.purchases
 WHERE currency='USD' AND (fx_rate<=1 OR total_syp IS NULL)
UNION ALL
SELECT 'usd_batch_cost_missing',COUNT(*) FROM public.batches
 WHERE purchase_currency='USD' AND (purchase_fx_rate<=1 OR original_purchase_price IS NULL)
UNION ALL
SELECT 'usd_supplier_payment_syp_missing',COUNT(*) FROM public.supplier_payments
 WHERE currency='USD' AND (fx_rate<=1 OR amount_syp IS NULL)
UNION ALL
SELECT 'usd_payment_allocations_mismatch',COUNT(*) FROM public.supplier_payment_allocations spa
 JOIN public.supplier_payments sp ON sp.id=spa.payment_id
 WHERE sp.currency='USD' AND (spa.currency<>'USD' OR spa.amount_syp IS NULL)
UNION ALL
SELECT 'cashbox_syp_mismatch',COUNT(*) FROM public.cashbox_entries
 WHERE currency='SYP' AND amount_syp IS NOT NULL AND amount_syp<>amount
UNION ALL
SELECT 'cashbox_usd_missing_conversion',COUNT(*) FROM public.cashbox_entries
 WHERE currency='USD' AND amount_syp IS NULL;
-- Data count baselines before/after should match except explicitly staged test inserts.
SELECT 'products' source,COUNT(*) count_rows FROM public.products
UNION ALL SELECT 'batches',COUNT(*) FROM public.batches
UNION ALL SELECT 'purchases',COUNT(*) FROM public.purchases
UNION ALL SELECT 'supplier_payments',COUNT(*) FROM public.supplier_payments
UNION ALL SELECT 'supplier_payment_allocations',COUNT(*) FROM public.supplier_payment_allocations
UNION ALL SELECT 'sales',COUNT(*) FROM public.sales
UNION ALL SELECT 'cashbox_entries',COUNT(*) FROM public.cashbox_entries;
