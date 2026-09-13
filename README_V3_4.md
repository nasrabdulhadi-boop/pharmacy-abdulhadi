# Pharmacy Abdelhadi v3.4

Enhances product and inventory management.

## UI additions
- Product search by name, barcode, active ingredient.
- Add/edit products, sale price, visibility, reorder level.
- Delete products only when no batches exist; otherwise safely hide them.
- Add/edit inventory batches.
- Quantity adjustment with positive/negative delta.
- Delete empty batches only.
- Refresh remains available on lists.
- Quantity changes are recorded in stock_movements through `adjust_stock`.

## Supabase
After deploying the app, run `STOCK_PRODUCT_ENHANCEMENTS.sql` once.
Do not expose service-role keys.
