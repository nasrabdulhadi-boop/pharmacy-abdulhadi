# QA permissions acceptance gate

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
- [ ] Create isolated, authenticated QA manager without touching production or reusing production credentials.
- [ ] Sign in with real QA employee JWT; submit operation; verify persistent pending request.
- [ ] Sign in with real QA manager JWT; approve and reject distinct pending requests; verify state transition and decided_by.
- [ ] Verify employee cannot approve, support cannot submit/read/approve, anonymous cannot invoke RPCs.
- [ ] Verify repeated approval/rejection is idempotent (returns false for decided requests).
- [ ] Verify role changes and refresh/revocation under real JWT sessions.
- [ ] Prepare QA operational schema without importing sensitive production records.
- [ ] Build dedicated employee RLS/RPC for real sales and stock updates with FEFO, inventory and accounting invariants.
- [ ] Verify regression tests across purchase, sale, stock, supplier debts, currencies, customer returns, cashbox, reporting.
- [ ] Require explicit release approval before merging to main or production deployment.

## Known limitation
`qa_review_employee_operation` changes only a QA queue status. It does not execute a sale, mutate stock, or affect pharmacy accounting. QA support health values are synthetic/unknown; do not treat as live monitoring.

## Test-account provisioning
Use Supabase Auth Admin API via authorized console/connector if available; create a distinct QA-only identity and use app_metadata.system_role=system_admin. Do not fabricate credentials, copy owner passwords, or edit production users. If provisioning cannot be completed safely, leave the acceptance gate open and report it.
