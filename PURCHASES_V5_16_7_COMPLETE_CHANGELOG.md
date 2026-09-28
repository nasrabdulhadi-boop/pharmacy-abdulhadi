# Pharmacy Abdelhadi V5.16.7 — Purchases Complete

## Base
- Built from the established V5.16.4 reference.
- Includes the V5.16.5 purchase/payment SQL patch already applied to Supabase.

## Frontend changes in this package
- Purchase invoice supplier chooser with search and inline new-supplier modal.
- Supplier-debt navigation from Purchases.
- New supplier fields: name, phone, address, notes.
- Supplier duplicate-name guard in the invoice flow.
- Separate invoice-number barcode camera.
- Medicine barcode camera.
- Direct USB barcode input with Enter; repeated scans increment the same medicine quantity.
- Unknown medicine barcode opens the new-medicine form with barcode prefilled.
- New medicine can also be opened directly from the invoice item table.
- New medicine form includes pharmacy-product fields plus active/customer-visible toggles.
- New medicine is saved through admin_save_pharmacy_product and attached to the invoice.
- Purchase item table: barcode, medicine, active ingredient, quantity, net purchase price, sale price, expiry, line total.
- Product search by name / active ingredient / barcode / strength in the invoice item picker.
- Paid amount, remaining amount, full-payment shortcut, credit shortcut, payment method and notes.
- Purchase list shows total, paid, due and payment status.
- Purchase detail shows supplier, items, active ingredient, payments and accounting note.
- Supplier Debts includes record-debt / deferred-invoice entry and supplier-specific deferred invoice shortcut.
- Purchase page has a direct Supplier Debts button.

## Database
- V5.16.5 SQL patch provides admin_create_purchase_with_payment.
- admin_list_purchases returns paid_amount, due_amount and payment_status.
- admin_get_purchase_detail returns payment data.
- Anonymous EXECUTE was revoked for the three new/changed purchase RPCs; authenticated EXECUTE retained.

## Validation
- JSX transpilation syntax check: PASS.
- No live purchase mutation performed by this build step.
- Browser/E2E and production build must be tested after deployment.

## Deployment
- Replace the project source with this complete package, commit/push to the same production branch, then verify the Vercel deployment URL.
- Do NOT rerun historical SQL files.
- The V5.16.5 SQL patch has already been applied in the user's Supabase database; do not rerun it unless specifically instructed.
