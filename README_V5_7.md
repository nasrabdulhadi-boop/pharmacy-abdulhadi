# Pharmacy Abdelhadi v5.7

## New in v5.7
- Smart inventory single-product count is aggregated across all batches into one row.
- The selected product shows total current stock, total received, and total sold.
- Single-product count asks only for the total physical quantity on the shelf.
- Supplier debt ledger: supplier totals, invoices, paid amounts, remaining balances, payment history.
- Supplier payments can be linked to a specific invoice or automatically allocated to the oldest open invoices.
- Cash supplier payments create a negative cashbox movement and are linked to the supplier payment.
- Full supplier invoice details remain linked to purchase items, batches, inventory, and payment allocations.

## Database order
Run after the existing v5.6 SQL/credit-sale patch:
1. V5_6_ACCOUNTING.sql
2. V5_6_1_CREDIT_SALE_FIX.sql
3. V5_7_SUPPLIER_DEBTS_AND_SMART_COUNT.sql

For an already-working v5.6.1 database, only step 3 is required now.
