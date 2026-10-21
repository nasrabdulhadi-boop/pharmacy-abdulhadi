-- Staging only, run after 01/02/13 migration. All statements are read-only.
SELECT 'SYP payments to USD invoices' AS check_name, COUNT(*) AS bad_rows
FROM public.supplier_payment_allocations spa
JOIN public.supplier_payments sp ON sp.id=spa.payment_id
JOIN public.purchases p ON p.id=spa.purchase_id
WHERE sp.currency='SYP' AND p.currency='USD'
UNION ALL
SELECT 'USD payments to SYP invoices', COUNT(*)
FROM public.supplier_payment_allocations spa
JOIN public.supplier_payments sp ON sp.id=spa.payment_id
JOIN public.purchases p ON p.id=spa.purchase_id
WHERE sp.currency='USD' AND p.currency='SYP'
UNION ALL
SELECT 'allocations exceeding payment',COUNT(*) FROM (
  SELECT sp.id FROM public.supplier_payments sp
  LEFT JOIN public.supplier_payment_allocations spa ON spa.payment_id=sp.id
  GROUP BY sp.id,sp.amount HAVING COALESCE(SUM(spa.amount),0)>sp.amount+0.0000001
) x
UNION ALL
SELECT 'allocations exceeding invoice',COUNT(*) FROM (
  SELECT p.id FROM public.purchases p
  LEFT JOIN public.supplier_payment_allocations spa ON spa.purchase_id=p.id
  GROUP BY p.id,p.total HAVING COALESCE(SUM(spa.amount),0)>p.total+0.0000001
) x
UNION ALL
SELECT 'SYP payment amount_syp mismatch',COUNT(*)
FROM public.supplier_payments
WHERE currency='SYP' AND amount_syp IS NOT NULL AND amount_syp IS DISTINCT FROM amount
UNION ALL
SELECT 'SYP cashbox amount_syp mismatch',COUNT(*)
FROM public.cashbox_entries
WHERE currency='SYP' AND amount_syp IS DISTINCT FROM amount
UNION ALL
SELECT 'USD invoice missing frozen FX',COUNT(*)
FROM public.purchases WHERE currency='USD' AND (fx_rate<=1 OR total_syp IS NULL)
UNION ALL
SELECT 'USD payment missing frozen FX',COUNT(*)
FROM public.supplier_payments WHERE currency='USD' AND (fx_rate<=1 OR amount_syp IS NULL);
