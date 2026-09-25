# V5.16 — Smart Inventory Hardening

## What changed
- Actual shelf quantity is editable as a text/decimal input; typing is not interrupted by a database request on every keystroke.
- `0` is accepted as a valid physical quantity.
- Quantity is saved on blur/Enter and is also flushed before approval.
- Specific-product search supports medicine name, active ingredient, and barcode.
- Exact barcode results are selected automatically.
- USB barcode scanners work through the normal search input because they emulate keyboard input; no camera button is required.
- Enter selects the first search result.
- Smart inventory approval now explicitly allows the `inventory_count` stock movement type.
- Aggregate product reconciliation handles multiple batches safely and never makes a batch negative.
- Audit records remain enabled for inventory approval and every affected batch movement.

## Supabase
Run `SMART_INVENTORY_V5_16_FIX.sql` once in the Supabase SQL Editor after the existing V5.15 database setup.

## Important
The UI changes are in `src/main.jsx`. The SQL patch is additive/idempotent and does not use `CASCADE`.

# V5.16.1 — نتيجة الجرد الفورية
- أضيفت نتيجة جرد محفوظة وقابلة للاسترجاع للجرد الشامل وجرد المنتج المحدد.
- بعد اعتماد الجرد يظهر جدول فوري: الدواء، العدد قبل الجرد، العدد بعد الجرد، الفرق، النتيجة.
- الجرد الشامل يدمج الدفعات المتعددة لنفس المنتج في صف واحد.
- يتم جلب آخر جرد مكتمل عند فتح/تحديث المخزون الذكي.
- SQL: SMART_INVENTORY_V5_16_1_RESULT.sql، ويُشغّل بعد SMART_INVENTORY_V5_16_FIX.sql.
