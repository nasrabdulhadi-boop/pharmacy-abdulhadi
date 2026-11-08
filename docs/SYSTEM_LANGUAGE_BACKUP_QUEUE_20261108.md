# QA: shared language, manager backup and overview decisions

Date: 2026-11-08. Scope: `feature/system-administration-center-preview-20261028`, Supabase QA `vpjxdsprfcpqclnhbeoh`. No production database, data, branch or deployment changes.

## Delivered behavior

- One persisted Arabic/English setting now drives the application shell and operational sections, including POS, inventory, purchases, suppliers, debtor accounts, cashbox, returns, reports, profit and security. Administration settings and the header toggle share this setting. Direction switches between RTL and LTR; English still uses Latin digits and separated currency amounts.
- Interface text is translated offline. Medicine/customer/supplier names, typed searches, numeric amounts and stored enum values remain unchanged. Changing language directly from the POS header preserves the current input/draft. Native confirmation prompts, CSV column labels and report narratives use the same catalog.
- Employee presentation restrictions recognize translated labels. Server RPC/RLS authorization remains authoritative and unchanged for pharmacy operations. AST comparison found exactly 178 original and current Supabase/Auth calls in main.jsx with no changed arguments or additional business calls.
- The manager decision queue/workbench is mounted only inside Administration Overview. Profile, Roles & Access, Backup & Recovery, and Language & Appearance no longer repeat it.
- Encrypted application backup is available to system owner and system administrator on QA. Both Edge and database recheck the authenticated actor's live role. Employee/support remain denied. The completion audit records the actual actor role. Legacy manager metadata remains supported by the database role resolver.
- Full platform recovery is still unavailable: this export excludes Auth passwords/tokens/sessions. It is not a verified Supabase/Auth/Storage disaster-recovery restore.

## Verification and limits

- Existing suite plus localization behavior tests: **141 passed, 0 failed, 0 skipped**, including a disposable live support session.
- Administration SSR checks: **63 passed**.
- SQL role/export/audit acceptance: **16 rollback assertions passed**.
- Actual manager login, snapshot, complete Edge export, encryption/decryption and employee/support rejection: **12 passed**. Archive summary: 73 tables, 406 rows, 0 storage files, 1,019,885 encrypted bytes. Exact decrypted application data matched the exported JSON. Authentication credentials were excluded.
- Local isolated browser fixture: 21 application sections reviewed, Arabic search input survived AR/EN switching, intentional Arabic supplier names remained intact, employee restricted controls remained disabled in English. Decision heading appeared once on Overview and zero times on each of the other four tabs. This fixture mocks Auth/RPC and is not a signed-in deployed browser end-to-end claim.
- Production-mode and staging builds passed. Existing large-bundle warning remains; no unrelated bundle restructuring was attempted.
- Four synthetic QA accounts were removed; remaining fixture accounts = 0. Temporary account fixture endpoint was replaced with a 410 response. QA public tables without RLS = 0.

## Implementation

Shared store and display helpers: `src/systemLocale.js`; catalog: `src/systemTranslations.js`; LTR layout: `src/SYSTEM_LANGUAGE.css`. Surgical JSX conversion tools are in `scripts/i18n/`; they exclude input values, handlers and database call arguments. Babel development dependencies are pinned. The local browser fixture is excluded from commits and deployments.

QA migration applied: `qa_manager_encrypted_backup_access_20261108`. Permanent Edge function `qa-admin-application-backup` deployed at version 3. SQL source/acceptance and the manager backup acceptance runner are retained for review. Earlier owner-only backup descriptions are superseded by this report.
