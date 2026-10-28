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

## Verified remediation — 2026-10-29

Applied migration `qa_restrict_anonymous_admin_rpc_execute` to isolated QA project **only**. Revoked `EXECUTE` on `public.is_admin()` and `public.admin_get_products_page(integer,integer,boolean)` from `PUBLIC` and `anon`; retained `authenticated` EXECUTE for compatibility pending further testing.

Verification query with `has_function_privilege`: `anon=false`, `authenticated=true` for both functions. Supabase security advisors no longer report `anon_security_definer_function_executable`. Remaining warnings: authenticated execution of the two SECURITY DEFINER functions, and leaked-password protection disabled.

This **does not** prove role isolation: the email admin bypass remains, authenticated RPC exposure remains, and direct token-based deny tests are pending. Production was not changed.

## SQL role-simulation checks — 2026-10-29

Read-only tests in a transaction with `SET LOCAL ROLE authenticated` and synthetic `request.jwt.claims`; each transaction ended with `ROLLBACK`:

| Simulated identity | `is_admin()` | Visible product count | Result |
| --- | --- | --- | --- |
| Nonexistent subject with `technical_support` metadata | false | 0 | Expected denial |
| Existing QA admin user, server-stored legacy `admin` metadata | true | 4 | Existing admin compatibility preserved |
| Nonexistent subject with claimed `admin` / `system_owner` metadata | false | RPC returned 0 | Claimed role alone insufficient |

These tests do **not** use a real signed JWT or prove HTTP REST/RPC authorization, token revocation, or all sensitive schema coverage. Do not mark the release gate complete.

## QA role precedence and RLS hardening — 2026-10-29

Applied isolated QA migration `qa_enforce_explicit_system_role_precedence`:
- `public.is_admin()` uses trusted server-stored `auth.users.raw_app_meta_data`; explicit `system_role` takes precedence over legacy `role=admin`. Technical support cannot inherit legacy admin access.
- `products` INSERT, UPDATE, DELETE RLS policies now all invoke `public.is_admin()` (UPDATE checks both old and new rows).
- SQL inspection confirmed all three policy expressions.
- A **transactional** QA test temporarily assigned `system_role=technical_support` to the existing QA admin **inside a rolled-back transaction**, then tested with the authenticated role: `is_admin()=false`, admin product RPC returned 0 rows. Post-rollback inspection confirmed both QA accounts have no persistent `system_role` changes.

Remaining release blockers: real signed-in technical-support account and HTTP REST/RPC tests; token refresh/revocation; 2 authenticated SECURITY DEFINER advisor warnings; leaked-password protection warning. SQL simulation is not end-to-end proof.

## Additional QA table-grant hardening — 2026-10-29

Audited effective table privileges on isolated QA `public.products`. Discovered `TRUNCATE`, `TRIGGER`, and `REFERENCES` privileges granted to API roles, plus anonymous DML privileges. These are not justified by the read-only public catalog; importantly `TRUNCATE` bypasses RLS. Revoked `TRUNCATE`, `TRIGGER`, `REFERENCES` from PUBLIC, anon and authenticated, and revoked anonymous INSERT/UPDATE/DELETE. Post-change `information_schema.role_table_grants` confirmed authenticated retains only SELECT/INSERT/UPDATE/DELETE; anon has no direct table privileges. RLS policies still restrict authenticated DML by server-verified admin role. No rows were modified. These are QA-only changes, not production migration. Release remains blocked until real user-session REST/RPC tests and coverage of sensitive schema.

## QA transactional regression tests — 2026-10-29

Rechecked isolated QA using SQL transactions with `SET LOCAL ROLE authenticated` and synthetic request JWT claims derived from the server-stored QA user. Each transaction ended in `ROLLBACK`.

| Scenario | `is_admin()` | Direct `products` SELECT | `admin_get_products_page(10,0,NULL)` |
|---|---:|---:|---:|
| Legacy admin account, unchanged app metadata | true | 4 rows | 3 active rows |
| Same QA admin temporarily assigned explicit `system_role=technical_support` | false | 0 rows | 0 rows |

Additional authenticated support privilege checks: `TRUNCATE=false`, `TRIGGER=false`, `REFERENCES=false`. QA products row count after tests: 4. These are transaction-scoped SQL authorization simulations, **not** real login or network-level REST/RPC tests. No production changes. Real signed-in role tests, role revocation/token freshness, and complete sensitive-schema coverage remain blockers.

## Fresh advisor and account inventory check — 2026-10-29

GitHub Actions run 40777267836 for commit `6d038d4` passed. Isolated QA Auth has 2 existing accounts, 1 legacy admin and **0 actual technical_support accounts**; therefore no authenticated network-level support test has been performed. Supabase security advisors still report two `authenticated_security_definer_function_executable` warnings (`public.is_admin`, `public.admin_get_products_page`) and one `auth_leaked_password_protection` warning. Both definer functions have explicit admin gates; the linter still correctly flags their authenticated execution surface. Review before changing because `is_admin()` is used by RLS policies. Guidance: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable and https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection . No production changes; release remains blocked.

## Transactional role promotion and revocation regression — 2026-10-29

On isolated QA, temporarily assigned the existing non-admin QA account `app_metadata.system_role=system_admin` inside a rolled-back transaction. With simulated authenticated SQL request context, `public.is_admin()` returned true and `public.admin_get_products_page(10,0,NULL)` returned 3 rows. A separate rolled-back transaction simulated changing the same account from `system_admin` to `technical_support` while retaining its request subject; after demotion, `is_admin()` returned false and the admin RPC returned 0 rows. All account changes were rolled back. **This verifies database authorization against current server-side app metadata, not actual JWT/session revocation, live REST requests, or real email/password login.** Those remain release blockers.
