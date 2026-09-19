# Pharmacy Abdelhadi v4.4.3

- Fixed Products pharmacy -> Show on website using SECURITY DEFINER RPC to avoid products UPDATE RLS failures.
- Inventory batch form now has purchase/net price and sale/net price.
- Selecting a product automatically displays its barcode; barcode is read-only.
- Batch number is no longer requested or displayed in the Inventory UI. The existing database column is retained internally for historical compatibility.
- Inventory search is by barcode, product name, or active ingredient.
- Adding a batch updates the product-level purchase and sale prices through a controlled admin RPC.

Run `V4_4_3_PRODUCTS_INVENTORY_FIX.sql` in Supabase SQL Editor before deploying.
