# System Administration Center — Release Gate

**Status:** Preview only. Production deployment and production database writes are forbidden until all gates pass.

## Current verified CI baseline

- Branch: `feature/system-administration-center-preview-20261028`.
- Unit tests and Vite build passed at commit `8987289d99b9505d78bb9f6c41c390bd9dab3eb1`.
- CI does **not** prove browser behavior, RLS security, email delivery, backup integrity or restore success.

## Blocking release checks

| Gate | Acceptance criteria | Status |
| --- | --- | --- |
| Admin UI | Owner can navigate profile, access, backup and preferences in a real browser on desktop and mobile | Not tested |
| Support isolation | A real technical_support test account cannot read sensitive pharmacy, customer, financial or admin data via direct REST/RPC requests, even when bypassing UI | Not tested |
| Role provisioning | Server-issued role from app_metadata; unknown and revoked roles denied by RLS/RPC | Not tested |
| Password recovery | Isolated QA auth project, allowlisted preview redirect, test mailbox, complete recovery and expired-link tests | Not tested |
| Backup | Export created by trusted server, with authenticated authorization, encrypted storage and no browser service-role key | Not implemented |
| Restore | Restore a staging-only backup into a disposable staging target, verify counts and integrity, document rollback | Not implemented |
| Live diagnostics | Server endpoint provides allowlisted, sanitized health states without leaking secrets, emails or records | Not implemented |
| Regression | Full CI, browser workflows and permission-denial tests pass before merge | Not tested |

## Hard stop conditions

1. Never run migration or restore against production project `eewjjzgwoaxhojnjvzgq`.
2. Do not promote the preview branch to production until each blocking gate has dated evidence.
3. No technical support access to patient, inventory, financial, credential or other sensitive operational data.
4. Do not claim that client-side role checks constitute RLS authorization.
5. Backup manifest inspection is local file validation only; it does not verify the existence or recoverability of a backup.

## Recommended execution order

1. Confirm isolated QA project and test accounts, then audit existing RLS and RPC permissions without altering production.
2. Run deny/allow access matrix against QA for owner, admin, technical_support, anonymous and revoked sessions.
3. Verify password recovery email and allowed redirect end-to-end using QA-only test inboxes.
4. Build server-side backup and disposable restore flow; test integrity and failure recovery.
5. Add sanitized live diagnostics, browser tests, then perform security review and production release approval.
