# Pharmacy Abdelhadi V6.4.5 — Purchase/POS Final Audit

## Targeted fixes
1. Purchase invoice: the New Product dialog is now rendered through a React portal directly under `document.body`, outside the purchase invoice modal DOM. This removes the parent stacking/overflow clipping that caused the dialog to appear underneath the invoice or only become visible after closing it.
2. The purchase invoice remains open while the New Product dialog is open. Saving the new product links it to the exact invoice line that opened the dialog (or the first blank line when opened from barcode intake).
3. POS barcode search: stale asynchronous search responses are ignored using a request sequence guard. Clearing the POS barcode/search input invalidates previous requests.
4. POS barcode scan: the search text and result list are cleared immediately when a barcode scan is accepted, before the Supabase lookup completes. This prevents the previous medicine/search result from remaining visible while the next barcode is scanned.
5. Repeated barcode scans continue to use exact barcode matching and focus the input again after each scan.
6. Existing V6.4.4 product filters/sorting are preserved: search, manufacturer/company, dosage form, category, sorting by name/company/dosage form/active ingredient/category/purchase price/sale price, direction toggle, and reset.
7. Existing V6.4.3 purchase invoice, dashboard product count, and other fixes are preserved.

## Static checks
- `src/main.jsx` brace count: balanced.
- `src/main.jsx` parenthesis count: balanced.
- `src/main.jsx` bracket count: balanced.
- Exactly one New Product dialog render remains, using `PortalModal`.
- No nested `newProductOpen && <Modal ...>` remains in the purchase invoice.
- ZIP integrity checked with `unzip -t`.

## Important verification boundary
A full Vite production build was not claimed because dependency installation is not available/does not complete within the environment timeout. No live Supabase mutation or browser E2E test was performed. The code was statically inspected and the archive integrity was checked.
