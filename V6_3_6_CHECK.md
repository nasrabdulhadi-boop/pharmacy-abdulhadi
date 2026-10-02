# Pharmacy Abdelhadi V6.3.6

## Focused fixes
- Dashboard today profit now follows the same accounting basis as Reports: gross sale-item profit minus customer-return profit.
- Dashboard day details now exposes gross profit, return profit, net sales and net profit.
- Daily dashboard data is tied to the sale header date while item profit is aggregated through sale_id, avoiding mismatched item timestamps.
- Seven-day sales chart uses the exact daily dashboard RPC values and each day is clickable.
- Clicking a day opens a fixed side panel occupying about half the screen; page scrolling is not used.
- The side panel contains sales, purchases, cashbox, returns, debtor payments, supplier payments, orders and prescriptions.

## Verification status
- Source edits inspected.
- SQL syntax structure inspected against the existing schema/function signatures.
- ZIP integrity and application build still require the local project environment with dependencies; no production build claim is made here.
- Live Supabase execution was not available from this environment.
