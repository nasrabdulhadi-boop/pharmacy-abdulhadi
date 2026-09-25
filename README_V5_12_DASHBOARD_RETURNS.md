# Pharmacy Abdelhadi v5.12.1 — Dashboard & Returns

## SQL
Run `DASHBOARD_RETURNS_V5_12_FIX.sql` once in Supabase SQL Editor.

### Dashboard
- Dashboard daily sales KPIs use the browser/device-local day window (00:00–00:00), so the next day starts cleanly without deleting history.
- Clicking a day in the 7-day sales chart opens invoice-level details with time, payment method, debtor/customer, discount, paid/due amounts, and sold items.

### Returns
- Adds `customer_return` and `supplier_return` to the stock movement constraint while preserving existing movement types.
- Customer returns and supplier returns can therefore be recorded without the movement_type check error.
- Supplier returns support full remaining invoice stock, exactly 1, 2, or 3 products, or an arbitrary selected set.
- Supplier return selection is atomic: all selected products are validated and updated in one database transaction.
- Historical purchase invoices remain intact.


## V5.12.1 hotfix
Fixed PostgreSQL syntax in supplier return mode validation; no new SQL prerequisites beyond running the corrected migration once.
