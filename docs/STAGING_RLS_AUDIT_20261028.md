# Isolated QA RLS audit — 2026-10-28

Scope: **read-only inspection** of Supabase project `vpjxdsprfcpqclnhbeoh`. No SQL mutations were performed.

## Findings

- `public.products` uses RLS. INSERT/UPDATE/DELETE policies require `auth.jwt()->'app_metadata'->>'role' = 'admin'`.
- Product SELECT policy `catalog_admin_read` calls `public.is_admin()`.
- `public.is_admin()` is a `SECURITY DEFINER` function reading `auth.users` and returns true when app metadata role is `admin` **or** a hard-coded legacy email matches. This email-based admin exception needs owner-reviewed removal before using the project for support-role security certification. The email address is intentionally omitted from this report.
- The isolated QA database is not a full clone of production; testing only `products` cannot certify finance, prescriptions, sales, or other sensitive tables.

## Required next steps

1. Identify every caller of `public.is_admin()` and verify the existing admin login does not depend on the email exception.
2. Prepare and review a migration to use an owner-controlled server-side role claim only; do not apply until compatibility is verified.
3. Test negative access with real support JWT against SELECT/INSERT/UPDATE/DELETE and RPC endpoints, not just client-side role checks.
4. Never copy production patient, prescription, or financial data into staging.

**Release gate: BLOCKED.** This audit is a finding, not a remediation or proof of server-side isolation.
