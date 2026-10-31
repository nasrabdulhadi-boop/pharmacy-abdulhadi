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

## Execution prerequisites checked in continuation

No full backup or restore has been performed in this continuation. `psql`, `pg_dump` and Docker were unavailable, and no protected database connection was configured. SQL access through the connector does not replace a consistent database dump.

Use the existing QA project first; do not buy a plan, enable PITR, or create a billed branch. Install compatible PostgreSQL/Supabase CLI tooling on a trusted host and discover its actual `db dump --help` flags before execution. Supply credentials through a protected local mechanism, never chat, Git, frontend configuration or command logs.

The official CLI procedure exports roles, schema and data separately (`--role-only`, ordinary schema dump, and `--data-only --use-copy`). Take exports during a controlled QA write pause so separately exported files cannot disagree. Include custom application schemas explicitly and verify the actual dump contents; default internal-schema exclusions must be reviewed for Auth/Storage recovery needs. Retain encrypted off-site copies with hashes and a manifest identifying source project, versions, scope and timestamp.

Restore only into a disposable compatible local Supabase/Postgres target, with error-on-failure and transaction handling. Do not run any restore command against either hosted project. Check row counts and content hashes, foreign keys, supplier USD/SYP separation, cash/profit separation, debtor balances, stock quantities, role grants, RLS, trigger behavior and Auth recovery before accepting the result. Test a corrupt/truncated dump is rejected. Record actual elapsed recovery time rather than estimating success.

Storage database metadata does not contain file bytes: inventory and copy restricted objects separately, verify their hashes and access policies, and never expose prescription files to support. SMTP, Auth redirects/providers, API keys and deployment secrets need separately secured configuration recovery.

Official references reviewed: https://supabase.com/docs/guides/platform/backups and https://supabase.com/docs/guides/self-hosting/restore-from-platform . The admin-center backup gate must stay disabled until a real artifact and an isolated restore have passed.
