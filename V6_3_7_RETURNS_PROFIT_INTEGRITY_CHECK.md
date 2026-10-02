# Pharmacy Abdelhadi V6.3.7 — Returns & Profit Integrity

## Fixed
- Dashboard profit uses net sales minus net COGS after customer returns.
- Returned quantity is excluded from COGS exactly once.
- Customer return amount is discount-aware.
- Customer return writes `returns` + `stock_movements` + cashbox/debtor adjustment + audit in one transaction.
- Fully returned sale lines no longer appear as returnable items; the original `sale_items` row remains for accounting/FK/audit integrity.
- Historical missing return stock movements are reconciled without blindly duplicating existing quantities.
- Dashboard now exposes gross sales and net sales separately.

## Verification limitation
Production build/browser E2E and live Supabase execution are not claimed from this environment.
The SQL is designed as a targeted `CREATE OR REPLACE` patch and does not drop application functions.
