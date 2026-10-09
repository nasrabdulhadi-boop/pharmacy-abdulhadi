# Pharmacy Abdulhadi V6.4.18 — POS layout refresh

## Changes
- Uses the existing V6.4.16 project as its source baseline and preserves the existing project files, SQL migrations, settings, and deployment structure.
- Reorganizes the POS page into an invoice workspace and a separate vertical quick-sale sidebar positioned to the left on desktop; the quick panel moves above the invoice on narrow screens.
- Adds three quick-sale sections. Existing localStorage favorites are migrated in-memory to section 1 when no section is stored; assigning an item to a section is saved with the existing localStorage key.
- Adds a `سعر النت` invoice column based on `purchase_price` returned by the existing `admin_search_pos_products_currency` RPC. This is display-only; sale totals and RPC payloads are unchanged.
- Preserves all current invoice columns and the existing sale, stock, barcode, cash/credit, currency, and debtor RPC flows.

## Validation
- TypeScript JSX transpilation syntax check passed with zero diagnostics.
- The original project files are preserved; only `src/main.jsx`, `style.css`, `package.json`, `index.html`, and this README are changed/added in this refresh.
- Full Vite production build and live Supabase end-to-end tests were not possible in this environment because dependency installation did not complete. This package must be tested in a preview deployment before production.
- Quick-sale favorites are stored in the current browser's localStorage and do not sync across devices.
