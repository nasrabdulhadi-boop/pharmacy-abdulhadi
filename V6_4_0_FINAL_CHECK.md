# Pharmacy Abdelhadi V6.4.0 — Final Pre-Delivery Check

## Scope checked
- V6.3.9 source used as the baseline; no restart from zero.
- Purchase bonus/free units are isolated from invoice financial value.
- POS line price override is isolated from product/batch/purchase prices.
- Dashboard financial source remains `admin_dashboard_financial_summary`.
- Dashboard day-details keeps the same sections and rendering; only its panel width is increased.
- Reports keep the same financial source and expose purchase bonus quantities without adding them to purchase totals.
- Supplier return logic recognizes bonus batches as zero-value stock.

## Purchase bonus integrity
Example: quantity 5, bonus 1, purchase price 10,000:
- Invoice total = 5 × 10,000 = 50,000.
- Supplier debt/payment = based on 50,000 only.
- Paid stock batch = 5 units at 10,000 cost.
- Bonus stock batch = 1 unit at zero cost.
- Product purchase/sale defaults are updated only from the paid invoice values.
- Total stock increase = 6 units.

## POS price override integrity
Example: product sale price 10,000, operator sells current line at 8,500:
- `products.sale_price` is not updated.
- Batch purchase price is not updated.
- Purchase records are not updated.
- Stock quantity changes only by the sold quantity.
- `sale_items.unit_price` stores 8,500 for this sale.
- `sale_items.base_unit_price` preserves the product price seen by the server at sale time.
- Cash/debtor total, returns, dashboard and reports use the actual sold price stored in `sale_items.unit_price`.
- Price overrides are recorded in the sale audit log.

## Dashboard day details
- Data sections and labels were not redesigned.
- Only `.dashboardDayPanel` width was changed from 58vw/900px to 68vw/1050px on desktop.
- Mobile width behavior remains 100vw.

## Static validation performed
- JSX transpilation with TypeScript: PASS.
- ZIP integrity: verified after packaging.
- Source diff reviewed: changes are limited to the requested purchase bonus, POS price override, purchase/report data exposure, supplier-return compatibility, and the requested dashboard panel width.

## Environment limitation
A live Supabase transaction test and browser/Vercel E2E test were not available in this environment. Therefore this package is **pre-delivery checked**, not claimed as live-production tested. Apply the SQL patch first, then verify the three smoke scenarios before production deployment.
