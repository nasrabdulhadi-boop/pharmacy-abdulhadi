# Pharmacy Abdelhadi V6.3.9 — Final Integrity Check

## Fixed root cause
`admin_dashboard_day_details` previously referenced `o.customer_name` and `o.customer_phone`. The `orders` table uses `customer_id`; customer name/phone are read from `customers`. The function now uses `LEFT JOIN public.customers c ON c.id=o.customer_id` and returns `c.name` / `c.phone`.

## Integration guarantees
- Dashboard financial summary is the single source for sales, net sales, returns, COGS and profit.
- 7-day dashboard sales trend uses `summary.net_sales`, so customer returns are reflected.
- Day details use the same financial summary and correct customer join.
- Accounting reports use the same financial summary and therefore match dashboard totals.
- Report trend subtracts customer-return amounts per day, keeping the visual trend aligned with net sales.
- Return selector remains based on remaining returnable quantity.
- No application tables are dropped.
- No existing function is dropped; functions are replaced by signature.
- Permissions are limited to `authenticated` for the patched admin RPCs.

## Local checks
- JSX/source edits are syntactically balanced.
- SQL function signatures match existing RPC signatures.
- ZIP integrity checked after packaging.

## Important
Run this SQL patch only after the V6.3.8/V6.3.7 stack is present. Do not run all historical SQL files.
