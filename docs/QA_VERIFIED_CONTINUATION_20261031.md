# Verified continuation — 2026-10-31

Scope: preview branch only. Baseline f9618c233d8a8fea17da5c4da41b50c231c302f5; inspected branch head 949795b9dd1699f9c62af07213be5b94d2cee299. QA project vpjxdsprfcpqclnhbeoh. Production eewjjzgwoaxhojnjvzgq received read-only queries only. No service, paid feature, production migration, personal password change, or production deployment was created.

## Executed evidence

| Check | Observed result | Interpretation |
| --- | --- | --- |
| Baseline `npm test` in detached worktree | 6 pass, 0 fail, 0 skip | The six original policy tests actually ran; they are not database tests. |
| Current branch `npm test` after `npm ci --ignore-scripts` | 112 pass, 0 fail, 1 skip | Includes installed Auth SDK recovery callback ordering and mocked password/OTP flows. |
| `node scripts/qa/render-workspace-contract.mjs` | 63 pass, 0 fail | React server-rendered role/section contracts, not browser interaction. |
| `npm run build -- --mode staging` | exit 0, Vite 7.3.7 | Local compilation only; no QA credentials supplied to this build. Existing >500 kB chunk warning remains. |
| `audits/qa/debtors_and_employee_audit_acceptance.sql` via QA execute_sql | 64 assertions pass, ROLLBACK | Synthetic Auth rows/claims. Checks debtor collections, receipts, cash/profit separation, idempotency, mandatory audit and injected failure rollback. Runs through privileged SQL connection; not HTTP authentication. |
| `audits/qa/employee_daily_operations_acceptance.sql` via QA execute_sql | 50 assertions pass, ROLLBACK | Synthetic users/sessions; purchases + bonus, USD debt, fractional sale, SYP cash, oversell rollback, manager-approved stock count/returns. Not complete production business parity. |
| `audits/qa/support_authenticated_role_acceptance.sql` via QA execute_sql | 8 assertions pass, ROLLBACK | Executes as actual Postgres `authenticated`, with synthetic support session claims. Role, sanitized snapshot, empty privileged catalog RPC, no direct product rows, denied debtors/audit and no private schema USAGE. Not a signed HTTP JWT test. |

The first current-branch run failed because dependencies were absent (SDK import unavailable). Installing the lockfile dependencies resolved that environmental failure; no application fix was required. The first authenticated-role SQL harness failed while resolving a private table name because schema USAGE was correctly denied. The harness was corrected to assert the schema denial; no database permissions were changed.

Production read-only observation: 17,980 products; 1,919 batches; 119 purchases; 475 sales; 494 cashbox entries. Negative-stock batches: 0. Expired batches with positive stock: 0. Core sale/purchase/accounting/cashbox RPC signatures exist. These observations are not an end-to-end production regression test or a before/after data checksum.

## Changes in this continuation

- Daily SQL acceptance now provisions transaction-only fixtures itself, so it no longer needs an undocumented TEST_CLAIMS replacement.
- Added support test under the actual database authenticated role.
- Strengthened HTTP support smoke: Auth must first accept the identity and the database must confirm the live support role. An invalid JWT returning 401 can no longer falsely establish authorization isolation. Network calls have timeouts. This credential-dependent test remains skipped, not passed.
- Added explicit backup/restore execution prerequisites and release blockers below. Backup UI remains disabled.

## Advisor observations

QA security advisor: 48 informational RLS-without-policy findings, 33 warnings for authenticated-callable SECURITY DEFINER functions, and leaked-password protection disabled. Restricted private tables may intentionally have no policies; this is not permission to broadly grant access. SECURITY DEFINER warnings need endpoint-by-endpoint authorization review; the assertions above cover a subset, not all 33 functions.

References: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable and https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection . No paid protection feature was enabled.

## Remaining release blockers

1. Real QA support HTTP smoke and browser acceptance require a newly authenticated QA support session. No ephemeral credentials/session files were present. No personal passwords or recovery codes were requested or collected.
2. A new recovery email → OTP verification → own-password update → fresh login flow has not been independently observed in this run. Prior documentation records user-reported success; it is not substituted for current evidence. Mail delivery, SMTP configuration, redirect allowlist and token reuse/expiry need live QA confirmation.
3. No full database backup artifact was produced or restored. The environment has no psql, pg_dump or Docker and no protected database connection credentials. The connector exposes SQL but no backup export/restore capability. Do not label a SQL row export or a UI manifest as a complete backup.
4. Full restore into a disposable target, including roles/grants/RLS/functions/triggers and FK/currency invariants, remains untested. Auth settings, SMTP, API keys, deployment settings, and Storage file bytes need separate recovery procedures.
5. Complete pharmacy regression and all privileged RPC checks remain pending. Existing production was not exercised with synthetic sale/purchase writes.

Release state: BLOCKED. The documented passes above do not authorize production rollout.
