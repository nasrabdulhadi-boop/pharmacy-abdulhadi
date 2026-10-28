# System administration center — security release gate

Status: NOT APPROVED FOR PRODUCTION.

## Hard requirements

1. Work only on `feature/system-administration-center-preview-20261028` and an isolated Supabase staging project. Do not use production credentials or modify production data.
2. Client-side `systemAccessPolicy.js` is a display policy, not an authorization boundary. Never grant a technical-support user access based solely on its role checks.
3. Before enabling technical support, implement server-enforced deny-by-default RLS policies and audited RPC authorization for every exposed endpoint. Verify that authenticated technical-support users cannot select, insert, update, delete, or invoke sensitive pharmacy, patient, finance, user-management, or backup operations.
4. Diagnostics must be generated server-side using an explicit allowlist; never send raw SQL errors, identifiers, customer records, access tokens, environment variables, or logs to the browser.
5. Password reset and email changes must use Supabase Auth verified flows and redirect allowlists; never implement custom password storage or recovery tokens.
6. Backups must be encrypted, access-restricted, retention-defined, and restore-tested in staging. Never place backups in a public bucket or repository.
7. Run `npm test`, `npm run build`, RLS negative tests using a real support JWT, and owner/admin regression tests. Capture evidence and exact commit/deployment references.
8. Do not merge to `main` or promote a Vercel deployment until every gate passes and the owner approves.

## Current verification

- The preview branch contains a role/capability specification and Node tests.
- No live Supabase RLS enforcement, deployment validation, email recovery, or backup restore has been verified in this review.
- Release gate: BLOCKED until evidence is recorded.
