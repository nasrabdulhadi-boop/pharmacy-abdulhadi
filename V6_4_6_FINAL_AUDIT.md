# Pharmacy Abdelhadi V6.4.6 — Final targeted audit

## Fixed
1. **New medicine modal crash**
   - Root cause: `createPortal` was imported from `react-dom/client`.
   - Corrected to import `createPortal` from `react-dom` and `createRoot` from `react-dom/client`.
   - The new-medicine modal remains a real portal above the purchase invoice.

2. **Pharmacy Products stopping at 1000 / Failed to fetch**
   - Root cause: the previous `admin_get_products()` RPC returned a large SETOF response and the Supabase/PostgREST response path can be capped at 1000 rows.
   - Added `admin_get_products_page(p_limit,p_offset,p_customer_visible)`.
   - Frontend loads products in sequential pages of 500 rows until the final short page.
   - Pharmacy Products therefore can load all active products, not just the first 1000.
   - Purchase product selector and Inventory product loading use the same paginated source.

3. **Existing features preserved**
   - Product sorting/filtering remains in place.
   - Dashboard exact active product count RPC remains in place.
   - POS barcode stale-search protection remains in place.
   - Purchase new-product-to-invoice-line behavior remains in place.

## Required database step
Run `PRODUCTS_PAGINATION_AND_PORTAL_FIX_V6_4_6.sql` once in Supabase SQL Editor while logged in as an admin-capable project user.

The portal crash itself requires no SQL; it is fixed in the frontend import.

## Validation included
- ZIP integrity test performed after packaging.
- Source delimiter balance checks performed.
- Static checks confirm:
  - `createPortal` comes from `react-dom`.
  - `createRoot` comes from `react-dom/client`.
  - ProductManager no longer calls `admin_get_products()` directly.
  - Purchase and Inventory product loading use the paginated RPC helper.
  - New paginated RPC is included in the SQL patch.

## Important honesty note
A complete Vite production build was not claimed because dependency installation in this environment previously timed out. No live Supabase mutation was performed automatically. The SQL patch is included and must be executed in the user's Supabase project.
