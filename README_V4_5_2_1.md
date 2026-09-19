# Pharmacy Abdelhadi v4.5.2.1

- Quantity editing is now intentionally available only in the Inventory table.
- Material Card displays batch quantity as read-only; use Inventory to change it.
- Added purchase invoice deletion from Purchases.
- Purchase deletion is blocked if any batch from that invoice has already been sold.
- Purchase creation and deletion are written to audit_logs and appear in Security with Arabic labels.

Run `V4_5_2_1_PURCHASE_AUDIT.sql` in Supabase SQL Editor before deploying the source.
