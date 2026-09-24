# V5.10 — POS + Pharmacy Products fixes

## POS
- Material card modal is forced above the search popup.
- Sale quantity and parts are capped at available stock in the UI.
- Repeated additions/scans cannot increase a line beyond stock.
- Medicine name in the sales invoice is larger, with strength/form still beside it.

## Pharmacy Products
- Fixed `products.active` compatibility. If the database was created without that column, `V5_10_FIX.sql` adds it safely.
- Recreated the product delete/archive RPC after the column exists, fixing `column "active" of relation "products" does not exist`.

Run `V5_10_FIX.sql` once in Supabase SQL Editor before testing product deletion.
