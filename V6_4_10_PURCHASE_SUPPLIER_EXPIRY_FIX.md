# Pharmacy Abdelhadi V6.4.10 — Purchase Supplier + Expiry Fix

## Changes
1. Purchase invoice "Add New Supplier" now uses the same native browser top-layer dialog mechanism as the purchase "Add New Product" dialog. It renders above the purchase invoice instead of behind it.
2. New supplier save validates the returned RPC object, immediately updates the purchase supplier selector, and keeps the new supplier linked to the current invoice form. The supplier is persisted through `admin_create_supplier`, so it is immediately available in the Suppliers section after refresh/navigation.
3. New product behavior from V6.4.9 is preserved. It persists through `admin_save_pharmacy_product`, updates the local purchase selector/cache immediately, and remains linked to the current invoice line.
4. Purchase expiry input was replaced with a larger custom picker button. Clicking it opens a clear year selector plus 12-month grid. Choosing a month stores the last calendar day of that month (for example 2027-03 -> 2027-03-31), preserving the existing database date field and purchase-save RPC contract.
5. No tables, existing purchase RPCs, inventory logic, supplier debt logic, or product schema were deleted or changed.

## Verification
- TypeScript/JSX parser diagnostics: 0
- TypeScript JSX transpile diagnostics: 0
- Brace balance: verified
- Parenthesis balance: verified
- Bracket balance: verified
- Supplier modal occurrence: PortalModal/top-layer
- Product modal occurrence: PortalModal/top-layer
- Expiry picker and save path reviewed
- ZIP integrity checked after packaging

## Runtime limitation
No live Vercel/Supabase browser E2E test was available in this environment. Production build was not claimed as verified because dependencies are not installed in the working environment.
