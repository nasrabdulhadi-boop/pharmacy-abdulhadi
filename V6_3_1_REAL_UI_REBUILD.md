# Pharmacy Abdelhadi V6.3.1 — Real UI Rebuild

This version rebuilds the admin shell and dashboard to follow `DESIGN_REFERENCE_V6_3_APPROVED.png` instead of relying only on CSS overrides.

## Preserved
- Supabase connection and existing database schema
- Existing RPC calls and business logic
- POS, purchases, inventory, supplier debts, cashbox, returns, reports, orders, prescriptions and customer site

## Changed
- New admin shell with pharmacy-green sidebar
- New sticky header and global search styling
- New dashboard hero/welcome area
- Four primary KPI cards
- Seven-day sales area/line chart with clickable days
- Quick actions panel
- Inventory health panel
- Action alerts panel
- Daily indicators panel
- Shared modern visual language for existing admin pages
- Responsive mobile sidebar behavior

## Deployment
1. Replace the project files in the GitHub Desktop clone with this folder contents.
2. Do not copy `node_modules`, `dist`, or `.vite` if they exist locally.
3. Commit as `V6.3.1 - Real UI rebuild`.
4. Push to `main`.
5. Let Vercel deploy normally.

No Supabase SQL migration is required for this UI-only release.
