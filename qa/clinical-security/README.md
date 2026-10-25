# Isolated clinical access-control model

This suite creates a fresh **in-memory PGlite PostgreSQL database** with synthetic products and synthetic accounts. It never connects to Supabase and contains no pharmacy project URL, credentials, records or migrations. All grants, roles and policies exist only inside that temporary database.

Run from the repository root:

```sh
npm --prefix qa/clinical-security ci --ignore-scripts
npm run test:clinical:security
```

Nine checks cover narrow public fields, anonymous/non-admin cost denial, anonymous RPC execution denial, non-admin actor denial, retained admin access through the modeled RPC, forged client metadata, denied writes and the public-view boundary.

The example uses column grants plus a `security_invoker` view and a guarded admin function. **It is not a production migration or a drop-in fix.** Existing admin direct-table queries and public catalog calls must be reviewed before proposing any real access changes. The suite does not exercise PostgREST, Supabase JWT signature verification, existing auth users, live policies or mobile browsers. A passing result cannot close a production exposure finding.

Dependency: `@electric-sql/pglite` pinned at `0.5.11`, with a separate lockfile. No root application dependency was added.

The suite also runs 14 tests for the opt-in `catalog-hardening.proposal.sql` candidate, for **23 SQL tests total**. These reproduce the broad-read exposure with synthetic costs, apply the exact proposal as a non-superuser owner, verify public/admin boundaries and exercise the frontend loader against actual in-process SQL. This proposal is outside automatic migrations and must not be applied to the live pharmacy. See [the staging report](../../docs/PUBLIC_CATALOG_HARDENING_STAGING_2026-10-26.md) for evidence and remaining API/browser checks.

References:
- https://pglite.dev/docs/
- https://supabase.com/docs/guides/database/postgres/column-level-security
- https://supabase.com/docs/guides/database/postgres/row-level-security
