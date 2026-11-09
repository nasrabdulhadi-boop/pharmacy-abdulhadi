# Recovering the hosted pharmacy system

The current encrypted QA application archive can reconstruct and restart a local database. The report records exact row matching after reopening the generated database file and integrity checks on archived attachments. It does not certify a hosted restore or authorize activation. The application archive does not contain Auth credentials, the complete provider configuration, or a deployable copy of every Edge Function.

## Prepare an isolated candidate

1. Allocate a separate recovery Supabase instance and Vercel preview. Record both project references, the source backup timestamp, application commit and recovery operator. The target must be distinct from the live system and the existing QA source. Start the first rehearsal using synthetic accounts, documents and transactions only.
2. Take a consistent provider database backup covering the application and Auth schema. Separately preserve file bytes and hashes, bucket configuration, Edge Function source and deploy settings, Auth redirects and provider configuration, and the application build configuration. Recover secrets through the secured platform configuration. Keep the files and manifest encrypted at rest.
3. Restore into the candidate. Block outbound notifications, scheduled jobs and production integration credentials before serving traffic. Deploy the pinned application commit against the candidate, then perform a fresh start with new sessions.

## Verify the restarted candidate

Record expected and actual values and attach test results. Any failure or skipped check blocks activation.

| Check | Required evidence |
|---|---|
| Database | Tables and rows match the backup, including IDs, links, constraints, grants, sequence positions and currencies. |
| Operations | Verify stock by batch, invoice totals, debts, advances and cash balances. In the synthetic rehearsal run a sale, purchase and return, and verify their effects and audit logs. |
| Access | Fresh synthetic manager, employee and support sign-ins behave according to their roles. Test prohibited actions and private-data access directly against the candidate APIs. |
| Files | Restore files and bucket policies, then check counts, SHA-256 digests and authorized download behavior. |
| Runtime | Verify the exact commit, candidate URL and project reference, Edge Function configuration and public/private workflows with outbound actions safely contained. |
| Restart | Restart or redeploy the candidate, clear previous sessions and repeat the read and authorization smoke checks. |

## Activate and retain rollback

Record the recovery point and compare it with the current system's latest transaction. If operations continued after the backup, reconcile that gap before any switch. Schedule a write pause, take a fresh safety backup, and record the old deployment and connection settings. The owner reviews the candidate evidence and approves the switch separately. Point a new deployment at the verified candidate, then repeat the smoke checks before reopening writes. Retain the old system isolated for rollback. If writes have already resumed on the candidate, reconcile those writes before switching back.

Provider references:
- https://supabase.com/docs/guides/platform/clone-project
- https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore
