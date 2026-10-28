# System administration role compatibility — staging only

## Verified observation
The isolated QA Auth project has one account with app_metadata.role=admin and one with app_metadata.role=user. Neither account currently has app_metadata.system_role. The preview currently requires a new system_role to show privileged panels, so the legacy admin may see only Overview.

## Proposed compatibility
- Resolve roles from server-managed app_metadata only. Never authorize from email, user_metadata, or localStorage.
- Prefer explicit system_role in {system_owner,system_admin,technical_support}.
- Only when system_role is absent, map legacy app_metadata.role=admin to system_admin for UI continuity.
- Unknown or conflicting role claims fail closed; support is never upgraded by a legacy role.
- Keep the UI guard separate from server-side authorization: RLS and privileged RPCs must independently deny support and unauthenticated users.

## Acceptance criteria
1. Legacy staging admin sees the intended preview panels; regular user does not.
2. Explicit technical_support can see only sanitized diagnostics; never product lists, sales, purchases, suppliers, debts, or prescriptions.
3. A forged user_metadata.role or changed email grants nothing.
4. Tests run with separate real Auth identities and verify database/RPC denies, not only hidden UI.
5. No changes to production or existing role assignments until acceptance checks pass.

## Current blocker
The QA database contains a SECURITY DEFINER admin_get_products_page RPC and an is_admin function with a legacy email exception. Their existing authorization semantics need review before introducing support accounts. No production data should be copied into QA for these tests.
