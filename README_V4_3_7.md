# Pharmacy Abdelhadi v4.3.7

## Fixes
- POS: fixed `column reference "sale_id" is ambiguous` by renaming the PL/pgSQL sale variable to `v_sale_id` and qualifying all references.
- Inventory: fixed `missing FROM-clause entry for table "v_batch"` in `admin_delete_batch`; the locked row is now selected with `b.id = p_batch_id`.
- Security: added a dedicated, always-visible **التفاصيل** button/document icon column that opens a modal with operation details.
- Security audit details continue to record new batches and sale product/batch information.

## Supabase
Run `V4_3_7_FINAL_FIX.sql` once in Supabase SQL Editor as the admin/project owner.

## Frontend
Upload the project files to GitHub and deploy through Vercel.
