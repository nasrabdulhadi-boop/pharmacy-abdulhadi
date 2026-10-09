# V6.4.17 — POS layout refresh

## Scope
- Keeps the existing POS search, barcode scanning, invoice state/draft, stock validation, debtor flow, cash/credit sale RPC and currency conversion logic.
- Moves quick-sale favorites into a separate vertical side panel beside the invoice on desktop; on narrow screens it stacks above the invoice.
- Tightens invoice table spacing while preserving all existing columns and actions.
- Adds `سعر النت` immediately before `الصافي / قطعة`, populated from the existing product search RPC's `purchase_price` field. This is display-only and does not change the sale calculation.
- Does not require a database migration or change Supabase functions/schema.

## Verification
- TypeScript JSX transpilation diagnostics: 0.
- Reviewed that `complete_sale_accounting_currency`, `admin_search_pos_products_currency`, stock checks, and cash/credit paths remain unchanged.
- Full Vite build and live browser/Supabase test were not performed in this environment. Test on a preview deployment before production.
