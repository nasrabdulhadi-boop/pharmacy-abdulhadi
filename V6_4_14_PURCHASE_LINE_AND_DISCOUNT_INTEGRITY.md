# Pharmacy Abdelhadi V6.4.14 — Purchase Line Stability + Discount Integrity

## Fixed
- Purchase invoice medicine names no longer depend on the current search-result list.
- Each invoice line keeps a stable `product_name` display value when the medicine is added.
- The per-line product dropdown was removed from the invoice table; the main medicine search remains the only selection/search path, as requested.
- Adding the 5th/6th medicine therefore cannot blank the name of an earlier line while leaving its quantity/price.
- Existing product_id, purchase_price, sale_price, quantity, bonus_quantity and expiry_date payloads are unchanged.

## Discount integrity
- Invoice-level discount remains separate from item sale prices.
- `purchase_items.sale_price` and the product sale price are not rewritten by the discount.
- Discount changes only invoice subtotal/discount metadata/total and the resulting supplier payable balance/payment.

## Verification
- Source delimiter counts checked.
- TypeScript/JSX transpile check performed with TypeScript compiler API.
- ZIP integrity checked.
- Static checks confirm purchase payload still sends each line's `sale_price` unchanged and the discount SQL updates only `purchases` discount/total fields after the item/batch creation.
- No data-deleting SQL added.
- No new SQL required for this UI fix.

## Runtime limitation
No live Vercel/Supabase E2E browser test was available in this environment.
