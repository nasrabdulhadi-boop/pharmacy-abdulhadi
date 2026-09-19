# Pharmacy Abdelhadi v4.4.1

## POS improvements
- Added POS settings button.
- Default quantity and default part are saved in browser localStorage.
- POS starts empty and only shows searched products.
- Clicking a product name opens its material card.
- Added a bottom "بطاقة المادة" action for the current invoice.
- Material card shows barcode, sale price, parts per unit, stock, manufacturer, category, and all batches with expiry/received dates.
- Invoice/search tables follow the requested pharmacy-style columns and numbered rows.

No database migration is required for v4.4.1; it uses the existing `parts_per_unit` field from v4.4.0.
