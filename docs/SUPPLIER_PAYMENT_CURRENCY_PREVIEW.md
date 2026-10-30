# Supplier payment currency preview — 2026-10-30

Branch: `feature/supplier-payment-currency-preview-20261030`, based on production source commit `901e0081e78396c7f4df62740d5b3074a1473f41`.

No production database migration, branch merge, production deployment, or historical data rewrite was performed.

## Behavior

- Select actual payment currency (USD/SYP), independently of invoice/debt currency.
- Exchange rate means SYP per USD and is saved per payment; no later repricing.
- Payment and allocations retain invoice currency; additive `tender_*` metadata records actual money paid.
- Cash movements use actual currency/amount and a frozen SYP equivalent.
- Invoice balances, supplier ledger, payment receipt and audit link to the same transaction.
- Explicit invoice or oldest-invoice allocation stays within the selected debt currency.
- Cash failure aborts the entire transaction. Noncash does not create a cash movement.
- Request UUID prevents double submission, including retry after a lost response.
- Amount supports 2 decimal places; cross-currency settlement rounds to 6 decimal places. Excess payments are rejected.

## Isolated preview

Uses existing QA project `vpjxdsprfcpqclnhbeoh`, private `supplier_currency_qa` schema and synthetic invoices (USD 150; SYP 14000). No pharmacy supplier records were copied. QA functions use the existing administrator/session check. Anonymous, staff and technical-support accounts cannot access this feature.

The preview intentionally exposes supplier debts and its own cash ledger only. It is independent of the administration-center preview. Sign in with an existing **QA administrator** account. Production credentials do not necessarily exist in QA.

Branch-scoped Vercel Preview variables select the QA database; a runtime guard rejects any other database URL when preview mode is enabled. Its RPC adapter permits only this feature's endpoints.

## Validation performed

- Standard and preview Vite production builds succeeded.
- Real QA SQL suite passed all four currency combinations, explicit/oldest invoice allocation, debt/cash reconciliation, noncash handling and idempotent retry.
- Eight invalid-input cases rejected without writes: overpayment, missing receipt, zero exchange rate, NaN, wrong invoice currency, changed duplicate request, sub-cent tender and unknown currency.
- Missing session, revoked/nonexistent session and employee with forged admin claim rejected for reads and writes.
- Injected cashbox INSERT error rolled back payment, allocations and invoice changes.
- Anonymous execute permission and authenticated direct private-schema access verified absent.
- Test writes rolled back; seed invoices remain unpaid for manual testing.
- Automated browser UI test could not run locally: browser binary unavailable and browser download returned truncated archives. No browser pass is claimed.

## Future integration review

`supplier-payment-currency-v2.sql` and `supplier-payment-ledger-v2.sql` are prepared, **unapplied** production migrations. QA core is generated from the former by mapping tables into its private schema. Production integration still needs regression review of all accounting reports/exports, financial-integrity checks, the purchase-invoice payment entry path and currency display, using a full production-shaped staging database. Existing records keep their meanings and read with legacy fallback.

The preview is ready for isolated manual testing; it is not a claim that every production accounting report was regression-tested.
