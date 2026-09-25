# Pharmacy Abdelhadi v5.16.2

Smart Inventory result now shows sales made during the inventory-count period.

Columns: before count, sold during count, expected after sales, actual after count, difference, result.

Sales are calculated from `stock_movements` with `movement_type = sale` between `inventory_counts.started_at` and `completed_at`.

Run `SMART_INVENTORY_V5_16_2_SALES_RESULT.sql` after the v5.16 and v5.16.1 smart-inventory SQL files.
