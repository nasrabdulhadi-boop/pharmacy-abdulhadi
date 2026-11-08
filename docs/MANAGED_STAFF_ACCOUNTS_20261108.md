# QA: manager-provisioned employee and support accounts

Scope: QA branch `feature/system-administration-center-preview-20261028`; Supabase `vpjxdsprfcpqclnhbeoh`. No production changes.

## Behavior

Roles & Access now provides **Add employee or support account**. The manager enters a sign-in email, initial password and confirmation, full name, optional phone/address/job title/employee code/start date/notes, and selects Employee or Technical support. Creation is direct and sends no email. The credentials are manager-provisioned; email ownership is not independently verified. Existing manual invitations remain available as a collapsed alternative.

New accounts are linked on the server to the manager who created them. The list shows their names; **Details and password** opens the saved personal record and a separate password-reset form. Managers can edit their linked staff records, change employee/support role, disable/reactivate them and assign a new password. Owners retain oversight. Old unlinked accounts retain their existing role-management behavior; they are not automatically assigned to a manager or given invented personal details. This feature is not a claim that the whole application has tenant isolation.

Passwords are never returned, logged, included in staff profiles or shown after saving. They must be 12–128 characters with English letters, numbers and symbols. Creation starts banned and disabled until a live-session DB completion links the record and grants its intended role. Reset first disables access and deletes existing sessions, then changes the credential through Supabase's server-only Auth Admin API. Completion rechecks the manager's live role/session and ownership before restoring the intended role. Partial failures stay disabled; the UI advises refreshing and checking state instead of claiming success. A failed reset can be retried and its role deliberately re-enabled after confirmation; an interrupted pending operation may require technical review. No automatic unsafe activation is performed.

Private staff profiles and command reservations have RLS and no client grants. Staff cannot forge their manager through editable metadata or profile fields. Other managers cannot list or modify the new linked records. Existing role RPC now also checks the linkage and blocks role changes during a pending password reset. Security events record actor/action/target and session revocation; they exclude password values and profile contents.

## Verification

- **148 automated tests passed**, 0 failures/skips, including the disposable live support check; six new handler/validation cases cover unauthorized roles, production guard, invalid fields, ordering, partial failure and secret exclusion.
- **27 rollback SQL checks passed**: creation/linking, personal fields, cross-manager listing/edit/role/reset denial, role escalation, replay, revoked creator, disabled partial reset, session revocation, audit and client grants.
- Existing role-management SQL acceptance: **13 passed**.
- Actual QA Auth/Edge/API acceptance: **24 passed**. A disposable manager created an employee and a support user; both signed in with their exact live role. Personal details persisted, the old password and session stopped working after reset, the new password worked, and employee/support/other-manager reset requests were rejected.
- Local no-network browser fixture verified create and edit forms, all seven profile fields, preserved Arabic typed names through EN switching, password controls and list names. Auth/RPC are mocked in this fixture; the separate live API checks supply backend evidence. This is not a signed-in deployed-browser end-to-end claim.
- Staging build passed. Existing bundle-size warning remains.
- All six disposable Auth accounts were removed and the fixture endpoint replaced by HTTP 410. No original pharmacy records were modified.

QA migration: `qa_managed_staff_accounts_20261108`. Permanent Edge function: `qa-admin-staff-account` (JWT verification enabled, live identity/role rechecked). Code and acceptance runners are committed; fixture credentials and helper guard are excluded.

Security advisor notes: new private tables intentionally have no client policies/grants; privileged RPC warnings correspond to explicit live role/ownership guards. The pre-existing leaked-password-protection warning remains outside this change.
