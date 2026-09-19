# Pharmacy Abdelhadi v4.4.2

## What changed
- Added separate admin pages: **منتجات الصيدلية** and **منتجات الموقع**.
- Pharmacy products now include **سعر النت (سعر الشراء)** and **سعر المبيع (الصافي)**.
- Added `products.purchase_price` migration.
- Inventory is linked to the pharmacy product master through `product_id`.
- Inventory table now shows barcode, drug name, active ingredient, expiry, quantity, batch net price, sale price, material card and delete.
- Inventory supports text search by barcode/name/active ingredient/batch number.
- Inventory supports camera barcode scanning when the browser exposes `BarcodeDetector` and camera permission is granted.
- Quantity can be edited inline; changes use `adjust_stock` so stock movements remain recorded.
- Material card shows product information and all batches, with quantity editing and batch deletion.
- External customer website continues to show only `customer_visible=true` products.

## Supabase
Run `V4_4_2_PRODUCTS_INVENTORY.sql` once in Supabase SQL Editor.
