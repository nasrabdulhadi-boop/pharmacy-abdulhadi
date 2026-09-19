# Pharmacy Abdelhadi v4.4.4

## Fix
- Product visibility is now independent from the admin product list and inventory list.
- Hiding/showing a product on the customer website never removes it from Products or Inventory.
- Admin product and inventory reads use SECURITY DEFINER functions, so RLS on customer-visible products cannot hide pharmacy data.
- Existing customer_visible behavior on the public website is preserved.

## Supabase
Run `V4_4_4_VISIBILITY_INVENTORY_FIX.sql` once, then deploy the app.
