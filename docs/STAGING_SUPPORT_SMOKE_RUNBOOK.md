# Running the isolated QA support RPC smoke test

The test `tests/stagingSupportRpcSmoke.test.mjs` is skipped by default in normal CI. A green CI result **does not** prove real support isolation.

## Preconditions
- Confirm Supabase project is the isolated QA project `vpjxdsprfcpqclnhbeoh`, never production.
- Provision a temporary QA-only user with server-issued `app_metadata.system_role=technical_support` and no legacy admin claim. Never paste passwords or JWTs into chat or commit them.
- Supply `STAGING_SUPABASE_PUBLISHABLE_KEY` and `STAGING_SUPPORT_ACCESS_TOKEN` through ephemeral environment secrets.
- Run `RUN_STAGING_SUPPORT_SMOKE=true node --test tests/stagingSupportRpcSmoke.test.mjs` in a trusted environment.
- The test checks token issuer, explicit support claim, absence of admin role, expiration, and a denied/empty result from `admin_get_products_page`.

## Interpretation
- A 401/403 or an empty successful RPC result is accepted as denial of product rows.
- A successful nonempty result is a security failure; do not enable support accounts.
- Passing this one test is **not** sufficient: test direct table access, other RPCs, views, storage, and write attempts, and verify owner access separately.
- Never run a destructive write test against production. Use disposable QA records and rollback in isolated staging only.
