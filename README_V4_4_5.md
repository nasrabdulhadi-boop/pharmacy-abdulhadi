# Pharmacy Abdelhadi v4.4.5

## Fixes
- Hidden pharmacy products remain available in the **Add Batch** product selector.
- POS search uses a SECURITY DEFINER admin RPC with prefix search and indexed fields, so results start appearing from the first character/characters.
- POS search debounce reduced to 70ms.
- Pharmacy Products and Inventory search now filter an already-loaded dataset locally instead of making a network request on every keystroke.
- Inventory product selector uses `admin_get_products()` so products hidden from the external website remain available internally.

## Supabase
Run `V4_4_5_SEARCH_SPEED_FIX.sql` once in Supabase SQL Editor before deploying the frontend.
