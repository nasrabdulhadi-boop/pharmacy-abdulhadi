# Pharmacy Abdelhadi v4.5.2

## Fixes
- Admin navigation/scroll: the admin main area is now an independent vertical scroll area on desktop and mobile, and the sidebar can scroll independently.
- Material card supplier/invoice: batch traceability is loaded through a secure `admin_product_batch_trace` RPC, so supplier name and purchase invoice number are displayed despite RLS.

## SQL
Run `V4_5_2_TRACE_AND_SCROLL_FIX.sql` once in Supabase SQL Editor, then deploy the source files.
