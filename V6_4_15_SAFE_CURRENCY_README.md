# Pharmacy Abdelhadi V6.4.15 — Safe Currency/POS Repair

## What this patch fixes
- Adds `sale_currency` to products with **SYP as the default**.
- Existing product `sale_price` values are preserved exactly; no bulk conversion is performed.
- Adds central USD/SYP rate with history.
- Adds product editor currency selector (SYP/USD).
- USD product pricing is calculated dynamically: stored base remains USD; POS calculates current SYP using the central rate.
- SYP products remain fixed in SYP.
- Adds the missing `public.complete_sale_accounting_currency(...)` RPC with the exact parameter order/types expected by the patched POS.
- POS now calls the currency-aware RPC and preserves historical FX metadata on the sale/sale-item/cashbox/debtor records.
- The original `complete_sale_accounting(...)` RPC is not deleted.
- The original `admin_search_pos_products(...)` RPC is not replaced or dropped; a new additive `admin_search_pos_products_currency(...)` RPC is used by the patched POS.

## Safety
This migration intentionally contains no `DROP TABLE`, `TRUNCATE`, or bulk product-price conversion.
It only adds columns/tables/indexes and replaces the existing product-save RPC with the same signature so the existing UI contract remains intact.

Existing products are marked `SYP` only as a compatibility interpretation of their existing numeric prices. Their numeric `sale_price` values are not changed.

## Apply order
1. Keep the current production database untouched until you have a backup/snapshot.
2. Run `CURRENCY_V6_4_15_SAFE_MIGRATION.sql` once in Supabase SQL Editor.
3. Confirm the SQL finishes without an error before deploying the frontend.
4. Deploy this V6.4.15 source.
5. In POS settings, enter the current USD/SYP rate.
6. Edit an individual product and choose USD when you actually want that product linked to the exchange rate.

## Important examples
- Product stored at `2 USD`, rate `15,000` -> POS `30,000 SYP`.
- Same product at rate `16,000` -> POS `32,000 SYP`.
- Stored product at `30,000 SYP` remains `30,000 SYP` when the rate changes.

## Verification performed here
- Source was based on the supplied V6.4.14 archive.
- Static searches were performed against the existing POS/product RPCs before patching.
- The frontend dependency installation/build could not be completed in this environment because `npm install` timed out; therefore this package is **not claimed as a production-build-verified artifact**.
- Live Supabase execution and live POS E2E were not available here; the SQL must be run and checked in the user's Supabase project before production deployment.
