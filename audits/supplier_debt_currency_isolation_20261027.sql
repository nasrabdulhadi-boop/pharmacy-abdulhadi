-- Read-only supplier currency isolation audit. Never updates production records.
-- Invoice totals, payments, and balances must be compared only within currency.
SELECT currency, COUNT(*) AS invoice_count,
       SUM(total) AS invoiced, SUM(paid_amount) AS paid,
       SUM(credit_amount) AS credited, SUM(due_amount) AS outstanding
FROM public.purchases GROUP BY currency ORDER BY currency;

-- Any nonzero result requires investigation before deploying debt changes.
SELECT COUNT(*) AS invoice_balance_mismatches
FROM public.purchases
WHERE ABS(COALESCE(total,0)-COALESCE(paid_amount,0)
          -COALESCE(credit_amount,0)-COALESCE(due_amount,0)) > 0.011;

SELECT COUNT(*) AS cross_currency_payment_allocations
FROM public.supplier_payment_allocations a
JOIN public.purchases p ON p.id=a.purchase_id
JOIN public.supplier_payments sp ON sp.id=a.payment_id
WHERE p.currency IS DISTINCT FROM sp.currency
   OR a.currency IS DISTINCT FROM p.currency;

-- Legacy admin_supplier_debt_list combines currencies; the UI must exclusively
-- use admin_currency_supplier_debt_list_v1 and currency-scoped ledger/payment RPCs.
