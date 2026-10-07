# Pharmacy Abdelhadi V6.4.13 — Purchase Invoice Discount

## Scope
Targeted purchase-invoice enhancement only. Built on V6.4.12; existing purchase, stock, supplier, payment and product flows are preserved.

## New feature
Invoice-level discount with two modes:
- Percentage (%): calculated from the invoice subtotal.
- Syrian pounds (ل.س): fixed amount deducted from the invoice subtotal.

The invoice now shows:
- Total before discount.
- Discount value.
- Total after discount.
- Paid amount.
- Remaining supplier balance.

The discount card updates all amounts live before saving.

## Persistence / accounting linkage
A new RPC `admin_create_purchase_with_payment_discount` is used only by the new purchase-invoice UI. The existing `admin_create_purchase` and `admin_create_purchase_with_payment` functions are not replaced.

New purchase metadata columns:
- `purchases.subtotal`
- `purchases.discount_type`
- `purchases.discount_value`
- `purchases.discount_amount`

`purchases.total` is the final amount after discount, so supplier debt and payment allocation are based on the discounted total.

Existing purchase rows are preserved and backfilled as `discount_type='none'`, `discount_amount=0`, `subtotal=total`.

## Inventory safety
The invoice-level discount does NOT rewrite individual `purchase_items.purchase_price` or batch cost. This avoids changing stock-cost history or inventory valuation unexpectedly. The discount is applied to the invoice payable total, supplier balance, payment and purchase total reporting.

## Validation
- Percentage must be 0–100.
- Fixed discount cannot exceed subtotal.
- Payment cannot exceed the post-discount total.
- Negative discount values are rejected.
- No data deletion is performed.
- No product/supplier/batch deletion is performed.

## Verification performed
- JSX/TS transpile diagnostics: 0.
- Delimiter balance: `{}` / `()` / `[]` all balanced.
- Existing V6.4.12 ZIP source used as the base.
- Full source package re-zipped and ZIP integrity tested.
- Production/Vercel E2E was not claimed because this environment does not run the user's live deployment.

## Required Supabase step
Run `PURCHASE_DISCOUNT_V6_4_13.sql` once in Supabase SQL Editor before using the new discount fields.
