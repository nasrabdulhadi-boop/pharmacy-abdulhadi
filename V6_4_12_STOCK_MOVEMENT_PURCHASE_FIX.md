# V6.4.12 — Purchase Save / stock movement constraint fix

## Root cause
The database constraint `stock_movements_movement_type_check` can become too restrictive after a reset or after an earlier constraint-rebuild script runs while `stock_movements` is empty. The purchase RPC correctly inserts `movement_type = 'purchase'`, but the constraint may no longer allow it.

## Fix
`STOCK_MOVEMENT_TYPES_PURCHASE_FIX_V6_4_12.sql` rebuilds only that CHECK constraint, preserving all existing movement types and explicitly allowing the movement types used by the current system: purchase, purchase_bonus, sale, customer_return, supplier_return, inventory_count, disposal, adjustment.

No data is deleted or rewritten.

## Important for the current invoice
The frontend save handler does not clear the invoice lines when the RPC fails. The screenshot shows the invoice is still open, so after running the SQL once, click **حفظ الفاتورة** again. You should not need to re-enter the invoice.

If the page is refreshed before retrying, the unsaved browser state may be lost; therefore run the SQL first and retry the currently open invoice before refreshing.

## Verification
Source delimiter checks and ZIP integrity are performed before delivery. Live Supabase execution is not performed from this environment.
