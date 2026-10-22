# Pharmacy Abdulhadi — currency feature invariants (2026-10-22)

## Protected production behavior
- A product has one `sale_currency` field (`USD` or `SYP`). Both product master `purchase_price` (net) and `sale_price` use this currency.
- Product search/table/card/edit form must label **both** prices using the product's own currency, not a hard-coded SYP suffix.
- USD supplier purchase invoice UI must retain the **عملة فاتورة المورد** selector, the USD pathway, supplier invoice currency, sale currency per line, and expiration dates.
- When an existing SYP-priced product is added to a USD purchase invoice, never auto-fill its SYP purchase price as USD. Initialize purchase price to zero and show the existing cross-currency warning. User must explicitly enter the USD cost.
- Same-currency existing product cost may be auto-filled. Do not auto-convert stored product master prices when changing display currency.
- No change to stock, accounting transactions, supplier payments, purchase invoices, product records, RLS, or Supabase RPCs without separate audited migration and tests.

## Release gates
1. Start from latest **verified currency-capable** commit, not the older default main branch.
2. Run `npm install` and `npm run build`, and require exit code 0.
3. Confirm preview Vercel deployment is `READY`.
4. Verify USD purchase invoice selector and both product net/sale price labels with representative SYP/USD products before production promotion.
5. Keep the default production branch and production database unchanged until explicitly approved.

## Recovery
Verified historical USD-enabled base: `d11373b7edeed252aa8289f646314094875f9a37`.
Working preview branch: `fix/restore-usd-purchases-safe-20261022`.
Do **not** replace this branch with `fix/clean-build-currency-20261022`, which was created from the old main branch and omits USD purchase features.
