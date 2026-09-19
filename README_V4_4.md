# Pharmacy Abdelhadi v4.4.0

## POS upgrade
- POS starts empty; no products are loaded automatically.
- Search by medicine name, barcode, or active ingredient.
- Exact single-result Enter adds the product.
- Search results show barcode, medicine name, stock, earliest expiry, and sale price.
- Invoice table columns: barcode, medicine name, stock, part, quantity, net, expiry, actions.
- `الكمية` is whole boxes/stock units.
- `جزء` is the number of blisters/strips/parts sold from one box.
- Products now have `parts_per_unit`: number of parts contained in one box. Example: 10 strips per box -> set `عدد الأجزاء في العلبة = 10`. Selling one strip is stored as 0.1 box.
- Existing FEFO sale engine remains the source of truth for stock deduction.

## Supabase
Run `POS_V4_4_UPGRADE.sql` once before using the partial-unit feature.
