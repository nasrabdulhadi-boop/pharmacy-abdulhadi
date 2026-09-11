# Pharmacy Abdelhadi v3.2
Adds a real admin inventory workflow: Add Batch modal, product selection, expiry date, quantity, purchase price, and batch listing.

## Supabase
Run `BATCH_RLS_FIX.sql` once in SQL Editor after deploying this version. The policies allow only authenticated users whose app_metadata role is `admin` to manage/read batches.
