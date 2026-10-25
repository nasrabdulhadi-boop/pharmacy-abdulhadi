# Public catalog hardening — isolated candidate, 2026-10-26

**Scope: preparation and isolated testing only. No live SQL, data updates, permission changes, Vercel environment changes, production merge, or POS/accounting changes. The live exposure is not closed by this delivery.**

## Candidate implementation

- `qa/clinical-security/catalog-hardening.proposal.sql` is an opt-in, transaction-wrapped **proposal**, outside automatic migration directories. It refuses ordinary execution, unexpected SELECT policies/predicate drift, existing reserved objects and residual anonymous cost privileges. It has only DDL/ACL operations; no product-row updates or deletion.
- It preserves `authenticated` administrator direct-table access through the existing `public.is_admin()` check and leaves the original INSERT/UPDATE/DELETE policies unchanged. Non-admin authenticated base-table reads receive no rows; anonymous direct-table SELECT is revoked, including explicit column grants.
- The public RPC returns exactly the same 11 display fields used by the customer page. Hidden or inactive products are excluded; sale prices and currencies are unchanged. Pages are bounded to 500 records and ordered by name and ID.
- The public wrapper is `SECURITY INVOKER`. Its private helper has a dedicated non-login, non-bypass-RLS owner with only public-column SELECT privileges; the helper's owner cannot select purchase cost and does not own the table. The trusted schema owner retains PostgreSQL's role-management authority but its temporary inherit/SET access is removed.
- `src/publicCatalogAccess.js` has a hardened paginated loader with a strict field allowlist, duplicate/malformed-page rejection and an exact-cap probe. RPC errors never fall back to the legacy table.
- The customer page uses the new loader behind **`VITE_PUBLIC_CATALOG_ACCESS_V2=true`**. This flag is **off unless explicitly enabled**. With the flag unset, the existing public query and field selection are preserved. No environment flag was changed in this task.
- In hardened mode only, loading errors are shown as a generic Arabic retry message instead of being presented as an empty search result. Internal database errors are not shown to customers.

## Evidence

Live metadata was inspected read-only to establish the 18 product columns, the existing visibility SELECT policy, the three admin write policies, table grants and administrator ownership/capabilities. No pharmacy records were copied into test fixtures. The test fixture uses the observed column types and policy shape with synthetic UUIDs, products, costs and accounts; JWT claims and auth users are simulated.

- **143 software tests passed**, including five new client loader tests; `npm run build` passed. The existing large-bundle warning remains.
- **23 isolated SQL tests passed**: 14 tests apply/exercise the exact candidate and 9 retain the earlier security model tests.
- The new fixture first reproduces the broad-read problem using synthetic costs, then applies the exact proposal as a **non-superuser** table/schema owner with `CREATEROLE`.
- Verified: no product-value changes from applying the proposal; anonymous cost SELECT/filter denied; ordinary authenticated cost rows hidden; public display/currency retained; hidden/archived products excluded; admin direct cost reads retained; original synthetic admin UPDATE policy works in a rolled-back transaction; restricted reader cannot read cost/create objects/update products; public return type has no cost column; bounded paging; guard/refusal behavior; and loader → actual SQL integration via an in-process adapter.
- The main JSX diff is confined to `Customer` and its loader import. The clinical assistant, POS, purchases, inventory and accounting implementation is unchanged by this delivery.

Reproduce locally, without pharmacy credentials:

```sh
npm run build
npm --prefix qa/clinical-security ci --ignore-scripts
npm run test:clinical:security
```

## Boundaries and next staging checks

The tests run in PGlite, not a connected Supabase staging project. They do not test PostgREST projection/error codes, JWT signature validation, managed-role restrictions, API schema exposure, browser/phone UI or all existing privileged RPCs/views. The fixture does not contain the complete pharmacy schema, triggers or transaction workflows. This is a tested candidate for a separate staging review, not a production-ready migration.

Before any later deployment:

1. Obtain explicit authorization for the target staging project and verify it is separate from the live pharmacy. Do not run this proposal against the current live project.
2. Compare all schema/policy/grant/function dependencies. Confirm the private schema is not exposed by the Data API; audit existing privileged RPCs/views for alternate paths to private fields. Preserve original definitions and ACLs for review.
3. Validate on the actual staging PostgreSQL/Supabase role model with synthetic data. A policy/ownership guard failure means stop and review; do not remove guards to force execution.
4. Deploy the candidate backend and opt in to the frontend flag **on staging only**, together. Confirm that the frontend reports a controlled error if the new RPC is unavailable. Do not enable the flag on the existing preview that shares the live database.
5. Test actual HTTP requests as anonymous, non-admin and admin; check cost projection/filter/order attempts, public catalog pagination and all admin product-management operations. Test the browser/phone and audit any affected Realtime/views as applicable.
6. Prepare a separately reviewed migration, compatibility/rollback plan and explicit approval before any production operation. Do not restore broad public SELECT as a convenience fallback.

## Primary references

- https://supabase.com/docs/guides/database/postgres/column-level-security
- https://supabase.com/docs/guides/database/functions
- https://www.postgresql.org/docs/17/role-attributes.html

No actual account role, pharmacy product, sale, purchase or database policy was changed in this task.
