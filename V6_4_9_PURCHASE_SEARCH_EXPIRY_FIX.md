# Pharmacy Abdelhadi V6.4.9 — Purchase UX Fix

## Changes
- Removed the per-row medicine search input from the purchase invoice.
- Product search/selection is now performed only from the main medicine search at the top of the purchase invoice.
- Main search supports medicine name, active ingredient, and barcode; Enter on a numeric barcode performs an exact barcode lookup.
- Search results appear under the main search and clicking a result adds it to the invoice; repeated selection increments the existing line quantity.
- Removed the per-row “+ دواء جديد” button.
- Added “إضافة دواء جديد” beside “إضافة صنف” in the invoice items header.
- The existing new-product workflow and line-linking behavior are preserved.
- Expiry input changed from day-level date picker to a fast month/year picker (`type=month`). The system stores the last day of the selected month, preserving the database date format while making entry faster.
- No data deletion or schema destructive changes are included.

## Verification
- JavaScript/JSX delimiter balance checked.
- Target purchase component inspected after edits.
- ZIP integrity checked with `unzip -t`.
- Production Vite build was not claimed because dependencies are not installed in this environment.
- No live Supabase/Vercel E2E test was available in this environment.
