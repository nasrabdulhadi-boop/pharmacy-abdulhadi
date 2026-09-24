# Pharmacy Abdelhadi — POS v5.8

## POS changes
- Fast popup search starts from the first typed character.
- Search by barcode, product name, or active ingredient; Arabic/English text is supported through PostgreSQL `ILIKE`.
- Active-ingredient matches use contains search and are ordered by nearest valid expiry first.
- Search results show barcode, scientific/active ingredient, strength/form, available stock, expiry, sale price, and material card access.
- Enter on the POS search adds the first result.
- USB barcode scanners that type the barcode and send Enter add the first exact barcode result.
- Camera barcode scanning adds the exact barcode result directly to the invoice.
- POS expiry display is fixed to use `expiry_date`.
- POS draft invoices persist in browser local storage while navigating between admin pages.
- Payment method and selected debtor are retained with the draft.
- An explicit **إلغاء الفاتورة** action clears the saved draft.
- Successful sale clears the saved draft.

## Supabase step
Run `POS_V5_8_FIX.sql` once in Supabase SQL Editor while logged in as an admin-capable database session.

## Important
The search function now reports **saleable stock** (positive quantity with no expiry or expiry on/after today), matching the sales backend's non-expired stock rule.
