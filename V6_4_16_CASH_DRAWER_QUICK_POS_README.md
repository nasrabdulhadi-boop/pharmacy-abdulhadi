# Pharmacy Abdelhadi V6.4.16 — Cash Drawer + Quick POS

## Changes
- POS quick-sale favorites panel with configurable items, remove/reorder, and one-click add to the current invoice.
- Favorites are restricted to existing products returned by the pharmacy POS search. Every click re-fetches the current product row, so current stock and price are checked before adding. Items with insufficient/zero stock are still blocked by the existing POS logic.
- Cashbox physical-count workflow records expected ledger balance, actual counted cash, difference, time, user, and audit log in a new additive table. Saving a count does NOT post an adjustment or change cashbox balance.
- Adds audit action label for cashbox counts.

## Required deployment order
1. Make a backup of the current repository/deployment and Supabase project before deployment.
2. In Supabase SQL Editor, run `CASHBOX_DRAWER_COUNTS_V6_4_16.sql` once. It is additive and does not update or delete existing accounting rows. If it returns any error, stop and send the exact error; do not continue.
3. Confirm the SQL succeeds, then deploy the source files from this archive to the existing GitHub/Vercel project (do not create a new project).
4. Test in the live system: cash sale, credit sale, supplier payment, expense, quick-list add/remove/reorder, quick-item click, stock limit, physical count save, and audit history.

## Important limitations / validation status
- JSX was transpiled with the installed TypeScript JSX parser with zero diagnostics. A full Vite production build and live Supabase end-to-end test could not be run in this environment because project dependencies/live credentials are not available here. Therefore this is not a claim of production verification.
- Quick-sale favorites are stored in this browser's local storage, so they do not automatically sync to other devices/browsers. They only reference existing catalog products; this patch does not create non-stock products.
- Cashbox page retains the existing `admin_cashbox_reconcile` behavior on load. Review that existing function separately if you want to remove all automatic reconciliation side effects.
