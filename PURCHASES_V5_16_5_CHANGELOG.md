# Pharmacy Abdelhadi — Purchases targeted patch

Reference: V5.16.4
Working patch: V5.16.5 targeted purchases/payment changes

## Implemented
- New atomic RPC: `admin_create_purchase_with_payment`.
- Optional new supplier creation inside the same purchase transaction.
- Duplicate supplier-name guard (case-insensitive) for the inline-new-supplier path.
- Payment amount at purchase invoice time.
- Automatic remaining balance calculation.
- Full/partial/unpaid purchase state through existing supplier payment/allocation architecture.
- Cash payments create the existing `purchase_payment` cashbox OUT movement.
- Non-cash payments are recorded without a cashbox OUT movement.
- Zero-payment invoices explicitly refresh purchase balance so due amount is correct.
- Purchase list/detail expose paid/due/payment status.
- Purchase detail exposes active ingredient and payment records.
- Separate camera scan for supplier invoice barcode vs medicine barcode.
- Medicine barcode input is autofocus-friendly for USB scanners; repeated scans increase quantity.
- New-product-from-purchase uses existing `admin_save_pharmacy_product` RPC instead of direct table insert.
- Purchase item entry changed to a structured table with barcode, medicine, active ingredient, quantity, net cost, sale price, expiry, and line total.

## Validation performed
- JSX syntax transpilation with TypeScript: PASS.
- SQL patch structural pair check: PASS.
- No historical SQL files were executed.
- No live Supabase mutation was executed from this environment.

## Still pending before production
- Apply SQL patch in Supabase and run live read-only checks.
- Test full/partial/unpaid purchase scenarios against live DB.
- Test cashbox and audit rows live.
- Add/verify supplier-debt manual opening debt flow.
- Finish supplier-return settlement model.
- Full E2E/browser testing and production build.


### V5.16.5 SQL FIX
The first SQL run exposed PostgreSQL error 42P13 because `admin_list_purchases()` changes its RETURNS TABLE row type. The SQL was corrected to drop only the existing function definitions `admin_list_purchases()` and `admin_get_purchase_detail(uuid)` before recreating them. No data tables are dropped.
