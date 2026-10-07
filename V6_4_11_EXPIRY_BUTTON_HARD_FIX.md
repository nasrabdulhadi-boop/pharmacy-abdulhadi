# Pharmacy Abdelhadi V6.4.11 — Expiry Button Hard Fix

## Fix
- Replaced the purchase expiry inline popover with a body-level native `<dialog>` rendered through `createPortal`.
- This prevents the picker from being clipped by the purchase table's overflow/stacking context.
- The expiry button explicitly prevents default/propagation and opens the picker.
- Picker provides a year selector and 12 Arabic month buttons.
- Selecting a month writes the existing `expiry_date` field as the last day of the selected month.
- Closing the picker returns directly to the purchase invoice.

## Preservation
- No database tables, products, suppliers, batches, purchases, or accounting records are deleted or changed by this UI patch.
- Existing supplier/product save and purchase-save RPCs remain untouched.

## Verification
- JSX/TS transpile: passed.
- Delimiter balance: passed for (), {}, [].
- ZIP integrity checked after packaging.
- Production browser/E2E build was not available in this environment; no claim of live Vercel/Supabase E2E testing.
