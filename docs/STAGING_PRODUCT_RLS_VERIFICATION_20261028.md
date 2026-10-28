# QA product access audit (read-only)

Project: isolated QA Supabase project `vpjxdsprfcpqclnhbeoh`. No production database queries or modifications.

## Verified catalog controls
- The only public table in this QA database is `products`, and RLS is enabled.
- INSERT, UPDATE, DELETE policies are scoped to `authenticated` and require the server-issued JWT `app_metadata.role = admin`; UPDATE has both USING and WITH CHECK.
- The `catalog_admin_read` SELECT policy calls `public.is_admin()`.
- A separate `pharmacy_catalog_reader` role can SELECT only active, customer-visible catalog rows. This is **not** a technical-support role and must never be assigned to support without a separate design review.
- `is_admin()` is a SECURITY DEFINER function and accepts legacy admin role OR a hardcoded email exception. This email exception is a blocker for strict role-only authorization until carefully migrated.
- `admin_get_products_page` is SECURITY DEFINER with EXECUTE granted to anon and authenticated; its SQL does check `is_admin()`. The broad EXECUTE grant is an attack-surface concern, not by itself evidence of data leakage.

## Required before enabling support
1. Create isolated, non-production support identity with `app_metadata.system_role = technical_support`, and explicitly non-admin legacy role.
2. Test direct REST SELECT/INSERT/UPDATE/DELETE, and `admin_get_products_page` RPC with the support JWT; assert no sensitive rows and no mutations.
3. Test the same calls with unauthenticated and ordinary user tokens; verify authorized admin remains functional.
4. Audit all production RPCs, policies, views and storage separately before production rollout: this QA schema is not a production clone.
5. Remove legacy email-based privilege only after confirming the owner retains access through verified role claims and a rollback exists.

This audit is static inspection, **not** a completed real-user permission test. No schema changes were applied.
