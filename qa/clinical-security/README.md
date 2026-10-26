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

## Actual Supabase integration — isolated project only

`isolated-supabase.fixture.sql` was applied only to the verified empty project `vpjxdsprfcpqclnhbeoh` (`pharmacy-clinical-qa-isolated`), after Supabase quoted $0/month for the new project. It creates four synthetic products and two confirmed synthetic Auth accounts. Passwords are generated privately outside git; the fixture requires explicit opt-in and private settings, and refuses any nonempty public schema or existing Auth users. It does not copy pharmacy records or run pharmacy migrations.

`run-isolated-supabase.mjs` uses the real Supabase SDK, Auth, signed JWTs and Data API. It refuses the live project, mismatched origins and secret-role keys before authenticating. Its only permitted target is the isolated project above. It checks the synthetic product IDs/names before testing writes. Administrator price updates are restored in `finally`; the final fixture snapshot must match. No sale or purchase endpoint is called.

```sh
# INPUT is a private absolute JSON path OUTSIDE this repository, mode 0600.
# Fields: project_ref, base_url, public_key, accounts.admin/user {id,email,password}.
# Use only the generated @example.invalid synthetic accounts; never production users.
node qa/clinical-security/run-isolated-supabase.mjs INPUT baseline OUTPUT.json
# After applying the EXACT opt-in proposal to the isolated project:
node qa/clinical-security/run-isolated-supabase.mjs INPUT hardened OUTPUT.json
```

Do not run the baseline phase after hardening or overwrite the fixture to rerun it. The guarded fixture is deliberately not an idempotent migration. Sanitized results in `results/` record four successful baseline checks (two genuine logins plus two expected exposure reproductions), then **28 successful real-API checks after hardening**. No passwords, keys, JWTs or pharmacy records are in these result files.

The project is a minimal fixture with the observed product columns/policy shape and the existing administrator-check/page-RPC logic. It is not a complete pharmacy clone: financial RPCs, triggers, constraints, Storage and Realtime are not reproduced. This result does not authorize or establish compatibility of a production migration. See [the actual Supabase report](../../docs/CLINICAL_ISOLATED_SUPABASE_AND_SOURCES_2026-10-26.md).

References:
- https://pglite.dev/docs/
- https://supabase.com/docs/guides/database/postgres/column-level-security
- https://supabase.com/docs/guides/database/postgres/row-level-security
