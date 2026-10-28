# System Administration — isolated QA RLS audit

Date: 2026-10-29. Read-only queries against **isolated QA** project `vpjxdsprfcpqclnhbeoh` only. No production database access or mutation.

## Observed

- One public table: `products`; RLS enabled. Four sample product rows. This is not a full production schema and cannot establish production authorization safety.
- Three public functions: `is_admin` and `admin_get_products_page` are SECURITY DEFINER; `get_public_catalog_v1` is SECURITY INVOKER.
- `is_admin()` checks `auth.users.raw_app_meta_data.role='admin'` **or a fixed email address**. The email bypass is unsuitable for a strict role model and must be reviewed and removed in QA with compatible test accounts before relying on it.
- `is_admin()` has EXECUTE permission for PUBLIC/anon/authenticated. `admin_get_products_page()` also grants EXECUTE to anon and authenticated. Internal function authorization is not a substitute for revoking unnecessary grants.
- Current QA schema lacks finance, customer, prescriptions, inventory, backup and account-management tables. Therefore real support isolation across all sensitive data **cannot yet be verified**.

## Next required tests (QA only)

1. Inventory the intended QA schema, table grants, RLS policies and all RPC functions against the intended production shape **without importing patient or financial records**.
2. Establish isolated test accounts for owner, admin, support and unprivileged users; roles must be server-issued in `app_metadata`.
3. Remove fixed-email role bypass in QA after ensuring test owner access; audit SECURITY DEFINER function search paths and EXECUTE grants.
4. Use real authenticated tokens to test direct REST and RPC calls; support and anonymous accounts must be denied sensitive reads and writes.
5. Verify revocation behavior and token refresh. Document HTTP status and denial evidence, excluding secrets or record contents.

**Release gate: BLOCKED** until these tests pass. Never run these changes on production without separate approval and a reviewed migration.
