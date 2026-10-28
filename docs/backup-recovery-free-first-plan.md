# No-cost backup and restore design (planning only)

## Safety
- Never embed database service-role keys, DB passwords or access tokens in browser code.
- Never expose full backups to technical_support or public users.
- Do not claim a backup exists unless a backup artifact is verified.
- Do not run restore against production.

## Backup inventory
- Database: schema, data, functions, grants, policies, triggers.
- Authentication: user identity recovery procedure (password hashes and Auth internals require provider-supported mechanisms).
- Storage: files and prescriptions, with restricted access and separate restore verification.
- Deployment: GitHub commit/tag and Vercel environment configuration (secrets must not be copied into client-visible files).

## Free-first plan
1. Review existing Supabase plan's included backup capabilities without purchasing upgrades.
2. If no provider backup is included, document a manual administrator-only export procedure to encrypted local storage using standard PostgreSQL tooling, subject to safe credential handling.
3. Store an inventory/manifest with timestamp, project ref, schema version, and checksums; never store raw secrets in Git.
4. Test restoration using a local disposable PostgreSQL instance or separately approved isolated environment with synthetic data first.
5. Verify row counts, key relationships, currency invariants, RLS, and application smoke tests.
6. Document recovery time and manual limitations; schedule only after a tested procedure exists.

## Admin center UI
Until a real secure backup service exists, show 'not configured' and an explanation, not a misleading 'backup now' button.
