# صيدلية عبدالهادي — Final Web App v3.0

This is the deployable Vite + React application for the pharmacy.

## Local setup
1. Copy `.env.example` to `.env.local`.
2. Fill `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
3. `npm install`
4. `npm run dev`

## Supabase
The user's already-created database should have the base schema. Run `FINAL_SUPABASE_SETUP.sql` once to add final RLS policies, settings, audit log, and atomic sale RPC.

## Vercel
Import the GitHub repository. Framework preset: Vite. Build: `npm run build`. Output: `dist`. Add the two VITE_* environment variables to Production, Preview and Development, then deploy.

Never put a service-role key in the frontend.


## v3.1 fix
- Fixed customer product query to use `customer_visible` instead of the non-existent `active` column.
- Added `sale_price` to the admin product form and product table.
- Inventory remains batch-based; add stock through batches/purchases.
