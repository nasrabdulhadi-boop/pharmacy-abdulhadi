# System Administration Center — Preview Implementation Plan

Status: **preview only**. Production database, Auth users, RLS policies, financial data, and current admin login are untouched by this branch.

## Verified baseline (2026-10-28)
- React 19 + Vite 7 + Supabase JS v2; UI in src/main.jsx.
- Exactly one Auth user currently has app_metadata.role=admin (count only; no user secrets exported).
- Login uses signInWithPassword. No resetPasswordForEmail or updateUser flow in current UI.
- Root admin gate accepts app_metadata.role=admin OR a hard-coded email. public.is_admin() also includes this email exception. **Security migration blocker:** do not remove until a tested owner account and recovery flow exist.
- RLS enabled for all inspected public tables, but some products are intentionally public for customer catalog; technical-support account must not receive access to sensitive RPCs or operational records.
- Existing audit_logs and pharmacy_settings. No dedicated user roles/profile/backup metadata tables detected.
- Admin RPCs frequently SECURITY DEFINER; each must be reviewed for role checks before any new authenticated role is issued.
- The preview shell currently reads only the signed-in user's own Auth identity via supabase.auth.getUser(); it does not query pharmacy business records.

## Target roles
1. system_owner — immutable protected owner with recovery and MFA.
2. system_admin — explicitly delegated permissions; never automatically equal to owner.
3. technical_support — technical health telemetry only, no operational/financial/customer/patient data, no writes or user-management actions.
4. pharmacy_staff — future scoped operational privileges.

## Security architecture / release gates
1. Inventory all RPCs, SECURITY DEFINER functions, grants, RLS policies and Edge Functions. Build explicit deny-by-default permission matrix.
2. Provision an **isolated** Supabase staging project with synthetic test records and independent Vercel preview environment variables. A Git branch or preview URL alone is NOT a database isolation boundary.
3. Add role tables and admin-only role management through reviewed migrations in staging, with least-privilege RLS and tests for direct REST and RPC calls.
4. Protect ownership transitions, enforce verified-email recovery and MFA, and replace hard-coded email exception only after account recovery is tested.
5. Design minimal technical telemetry endpoints that reveal no row data, secrets, financial totals, or personally identifying information.
6. Implement localized UI using Arabic/English translation keys; keep numeric formatting and USD/SYP accounting unchanged.
7. Backup/recovery: inspect Supabase plan features and cost; define encrypted, access-controlled backups, retention, audit, and a staging restore drill. Never expose a client-side restore endpoint.
8. Acceptance tests: technical-support read/write denial for every sensitive table/RPC, owner recovery, session revocation, localization, backup restore, production regression, and rollback plan.

## Preview functionality implemented
- New sidebar section: مركز إدارة النظام.
- Read-only navigation tabs: overview, profile, access, backup, language/appearance.
- No role editor, backup buttons, or incomplete account-recovery actions are exposed.
- All existing pharmacy modules and authentication paths retained.

## Explicit non-goals in this preview commit
- No production migrations or changes to auth.users.
- No real backup or restore job.
- No new support account.
- No claim that security separation is implemented until staging tests pass.
