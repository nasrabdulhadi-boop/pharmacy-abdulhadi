# Supplier payment currency production release

2026-10-30. Base production source: `901e0081e78396c7f4df62740d5b3074a1473f41`.

## Behavior

Supplier debt remains in invoice currency. A payment can use USD or SYP and stores its actual tender amount, tender currency and fixed SYP-per-USD exchange rate. The server allocates the converted settlement to an explicit invoice or oldest invoices in that currency, updates balances, writes the actual cash movement, and records the receipt/audit atomically. Noncash payments do not change the drawer. Request UUIDs prevent duplicate payment after retries.

## Integration

- Supplier debts: currency selector, rate, converted settlement and remaining debt; visible six-decimal settlement precision.
- Supplier ledger and supplier-page invoice history: settlement and actual tender shown separately.
- Purchase invoice detail: allocated settlement distinguished from the entire original payment when split across invoices.
- Cashbox: original currency, amount and rate remain visible beside SYP equivalent.
- Dashboard day details and reports: currency-correct amounts; report cash balance now uses the same frozen SYP equivalents as the cashbox page.
- Financial integrity: extra checks for actual tender/cash links and complete/correct allocations; credit notes included in balance checks.
- Product prices, inventory costs, existing invoices, login, accounts, roles, POS shortcuts and authentication are not rewritten.

## Data preservation

The migration adds four nullable payment metadata columns, one partial unique index, one metadata constraint and guarded functions/read projections. Existing payment amounts/currencies/allocations keep their meanings. Legacy functions still work with null tender metadata.

The migration fingerprints every public business table before and after its own changes, excluding only the new nullable metadata keys from historical-row comparisons. Any content/count difference aborts the entire migration. No backfill, currency recategorization, batch-price rewrite or automatic reconciliation is performed.

## Validation before production

- Five Node tests passed: exact decimal conversion/rounding, invalid/unsafe inputs, fractional visibility, unchanged production auth/product/inventory sections, original navigation/rendering and UI integration.
- Release Vite build passed with the production entry point; no QA gateway or preview authentication code is included.
- Exact migration passed on isolated full-system staging.
- SQL acceptance passed payment combinations, split allocations, explicit invoices, reports, purchase/supplier details, legacy compatibility, fractional settlement, rate freeze, noncash, invalid inputs, POS, customer return, supplier return/refund and authorization. All acceptance fixtures/settings changes roll back.
- Actual concurrent staging transactions proved that two payments cannot overpay the same debt, and identical retried requests commit one payment. Only the newly generated concurrency fixture was cleaned up; the owner's separate preview payment was retained.

## Deployment and recovery

Apply `supplier-payment-currency-production.sql`, execute the rollback-only acceptance script on production, compare business fingerprints, then merge/deploy this release commit. Keep preview-only code out of main. The additive database change remains compatible with the previous application if deployment fails.

`supplier-payment-currency-rollback.sql` restores former read projections and disables the new payment endpoint after reverting the application. It deliberately preserves added metadata and all new payments; never remove financial rows to roll back code.

Browser sign-in and visual tests are not represented as completed by these automated checks. Existing unrelated production security advisories were recorded before the release; no broad permission/account changes are included.
