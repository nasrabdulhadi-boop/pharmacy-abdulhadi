# QA permissions acceptance gate

Updated 2026-10-30: see `QA_ACCEPTANCE_REPORT_20261030.md` and `audits/qa/results/` for current evidence. The limited sandbox acceptance has passed API tests; full production-shaped regression and authenticated browser acceptance remain open.

Environment: QA Supabase project `vpjxdsprfcpqclnhbeoh`, GitHub branch `feature/system-administration-center-preview-20261028`, Vercel Preview only. Production project `eewjjzgwoaxhojnjvzgq` and `main` MUST NOT be modified.

## Role boundaries
- Owner/manager: review QA employee requests and approve/reject only in QA.
- Employee: queue `sale`, `inventory_count`, `purchase_draft`, `order_process`, `return_request`; metadata-only. No actual sale, stock movement, financial edit, product price change, user administration, or destructive action.
- Technical support: sanitized status read only. No employee operations, customer data, finance, raw logs, or access to secrets.

## Acceptance checklist (not yet complete)
- [x] GitHub CI tests passed for prior preview changes.
- [x] QA employee simulated JWT can submit metadata-only operation in a rolled-back SQL transaction.
- [x] QA technical support simulated JWT sees zero employee operations.
- [x] QA preview manager review UI added and deployed.
- [x] Create isolated, authenticated QA manager without touching production or reusing production credentials.
- [x] Sign in with real QA employee JWT; submit operation; verify persistent pending request.
- [x] Sign in with real QA manager JWT; approve and reject distinct pending requests; verify state transition and decided_by.
- [x] Verify employee cannot approve, support cannot submit/read/approve, anonymous cannot invoke RPCs.
- [x] Verify repeated approval/rejection is idempotent (returns false for decided requests).
- [x] Verify role changes and refresh/revocation under real JWT sessions.
- [ ] Prepare QA operational schema without importing sensitive production records.
- [ ] Build dedicated employee RLS/RPC for real sales and stock updates with FEFO, inventory and accounting invariants.
- [ ] Verify regression tests across purchase, sale, stock, supplier debts, currencies, customer returns, cashbox, reporting.
- [ ] Require explicit release approval before merging to main or production deployment.

## Known limitation
`qa_review_employee_operation` executes requests marked `payload.sandbox=true` atomically against `pharmacy_qa_private` only. Legacy metadata-only requests still change queue status only. This is a dedicated QA implementation; it does not establish production POS/accounting compatibility. QA support health is unknown; do not treat it as live monitoring.

## Test-account provisioning — completed in isolated QA

Four distinct synthetic identities were created through server-side Auth Admin API, with cryptographically random passwords and server-issued app metadata. The short-lived, capability-protected provisioning function was immediately replaced with a disabled handler and JWT verification re-enabled. Existing users were not modified. Credentials and access tokens are excluded from this repository. Personal QA manager handoff requires a user-controlled QA email and secure password setup.

## Provisioning policy
Use Supabase Auth Admin API via authorized console/connector if available; create a distinct QA-only identity and use app_metadata.system_role=system_admin. Do not fabricate credentials, copy owner passwords, or edit production users. If provisioning cannot be completed safely, leave the acceptance gate open and report it.
