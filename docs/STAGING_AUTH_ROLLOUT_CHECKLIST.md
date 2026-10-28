# Staging authentication rollout checklist

**Production changes: prohibited.** Target only `pharmacy-clinical-qa-isolated` (`vpjxdsprfcpqclnhbeoh`).

## Current implementation gap

`src/stagingAuthGuard.js` is a unit-tested helper but is **not yet imported by `src/main.jsx`**. The existing UI guard is separate. Do not mark the new guard as active until the main entry point is updated and reviewed.

## Safe activation prerequisites

- [ ] Confirm preview Vercel project uses the isolated Supabase URL and publishable key, never production secrets.
- [ ] Connect the strict staging guard in the UI. The default must remain disabled.
- [ ] Set Auth redirect URL allowlist to the exact staging domain; never use wildcards in production.
- [ ] Test password reset with a disposable staging-only account and confirm expired, reused, and malformed links fail.
- [ ] Test changing a password with a disposable staging-only account; verify new password works and old one fails.
- [ ] Create a technical-support account **only after** server-side role authorization is implemented; do not derive role from user_metadata.
- [ ] Test support account SELECT/INSERT/UPDATE/DELETE on products, sales, patients, prescriptions, cashbox, supplier balances, users, storage, and privileged RPCs. All sensitive access must fail.
- [ ] Verify diagnostic responses have an explicit server-side allowlist and no raw errors, IDs, logs, tokens, or finance data.
- [ ] Run `npm test` and `npm run build` in CI and record links.
- [ ] Keep merge to `main` blocked pending owner approval.

## Status

Not approved for enabling real support users or production deployment.
