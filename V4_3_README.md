# Pharmacy Abdelhadi v4.3

## What changed
- POS upgraded with quantity + / - controls and item removal.
- POS sale transaction uses a secure atomic function (run `V4_3_UPGRADE.sql`).
- Supplier page rebuilt: working Add Supplier modal, phone/address/notes, edit/delete, error feedback, and RPC-based writes.
- Customer "آخر طلب" now shows order number, customer details, address, status, total, date, and item quantities.
- Admin branding updated to v4.3.

## Deployment
1. Replace the GitHub project files with this package.
2. In Supabase SQL Editor run **V4_3_UPGRADE.sql once**.
3. Wait for Vercel Production to become Ready.
4. Hard refresh the Production site.

## Test order
- Admin > الموردون > إضافة مورد.
- Admin > نقطة البيع > search product > add > adjust quantity > complete sale.
- Customer > آخر طلب / تتبع الطلب.
