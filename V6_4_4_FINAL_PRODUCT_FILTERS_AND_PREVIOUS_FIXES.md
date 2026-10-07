# Pharmacy Abdelhadi V6.4.4 — Final Product Filters + V6.4.3 Fixes

## Included
- Product Manager now supports **filtering** by:
  - company/manufacturer (الشركة)
  - pharmaceutical dosage form (الشكل الصيدلاني)
  - category/classification (التصنيف)
- Product Manager now supports **sorting** by:
  - name
  - company/manufacturer
  - dosage form
  - active ingredient
  - category
  - sale price
  - purchase/net price
- Sort direction toggle: ascending / descending.
- Search now also matches company, dosage form, category and strength, using contains matching.
- Result counter shows filtered results vs total active products.
- One-click reset clears search, filters and restores name ascending order.
- Existing V6.4.3 purchase-invoice new-product overlay behavior preserved.
- Existing V6.4.3 POS repeated barcode scan behavior preserved.
- Existing V6.4.3 dashboard exact active-product count RPC behavior preserved.

## Validation performed
- Source brace/parenthesis/bracket balance: PASS (0/0/0).
- ZIP integrity (`unzip -t`): PASS.
- Package version: 6.4.4.
- No SQL migration is required for the new Product Manager filters/sorting; they operate on the existing `admin_get_products` result.

## Important limitation
A full Vite production build was **not completed in this environment** because dependency installation timed out and `node_modules/.bin/vite` was unavailable. Therefore this package is not represented as production-build-verified.

## Existing SQL
The dashboard exact-count SQL from V6.4.3 remains included as:
`DASHBOARD_PRODUCTS_COUNT_FIX_V6_4_3.sql`
It still must be executed in Supabase if it has not already been executed.
