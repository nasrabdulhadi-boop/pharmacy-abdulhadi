# Pharmacy Abdelhadi V6.3.6 — Dashboard Financial Fix

## What was fixed
- Dashboard today's profit now comes from one authoritative backend calculation.
- Profit uses actual `sale_items.unit_cost`, actual sale totals after invoice discount, and customer-return cost reversal.
- Dashboard day details and Reports use the same financial summary source.
- Added net sales, customer returns, cost of goods, margin, cash in/out and related counts to the day summary.
- The 7-day sales chart continues to use exact day windows and opens the selected day directly.
- Day details are now a right-side half-screen panel instead of a centered modal.
- No dashboard/page scrolling is required to open the day details; sections are switched with tabs inside the panel.
- The panel contains sales, purchases, cashbox, returns, debtor collections, supplier payments, orders and prescriptions.
- Report response compatibility was preserved: `return_rows`, `items`, `checks`, `net_sales`, `net_purchases`, `net_profit`, etc. remain available.
- No existing functions are dropped.

## Backend patch
Run once in Supabase SQL Editor:
`V6_3_6_DASHBOARD_FINANCIAL_FIX.sql`

This file creates one new helper function and replaces the existing dashboard/report JSON implementations with `CREATE OR REPLACE` only.

## Verification performed here
- JSX syntax parsed successfully with TypeScript 5.8.3 using JSX parsing/noResolve.
- Package version is 6.3.6.
- No `node_modules` or `dist` were added.
- Production `vite build` was not run because dependencies are not installed in this environment.
- Live Supabase/E2E testing was not available from this environment; the SQL patch must be executed in the connected project before UI behavior can be considered live-verified.
