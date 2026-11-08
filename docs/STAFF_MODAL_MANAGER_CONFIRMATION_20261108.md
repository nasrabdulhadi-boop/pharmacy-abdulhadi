# QA: staff details dialog and manager password confirmation

The Details and password button now opens a native modal dialog with the staff profile, sign-in email, current role, linked manager and creation date when available. Personal fields remain editable; password reset is in a separate expandable form. The dialog uses the browser's modal focus handling, restores focus on close, supports Escape, scrolls on smaller screens and blocks closing while a save is running. Arabic/English labels and dark styling are included.

The selected security option is **the managing account's current password**, rather than adding a four-digit PIN. Each staff password reset requires a fresh manager-password confirmation. The current employee password is never displayed. Profile editing and account creation keep their existing flow.

## Enforcement

- Edge validates the original live manager identity and server role. The client cannot choose the account whose password is checked: its email comes from authenticated getUser.
- A DB reservation first records an attempt scoped to actor, original session, target and request ID. Limit: five attempts per manager per 15 minutes. No passwords, PINs or bearer tokens are stored in this table.
- An isolated, nonpersistent Auth client verifies the manager password. Its temporary session is signed out with local scope. The original manager session is not replaced or globally signed out.
- Only the server service role may mark a check verified. The DB rechecks the original manager's live session/role/ownership. The proof expires after 90 seconds and is consumed exactly once by the matching reset reservation.
- Calling the reset RPC directly without a verified check fails before disabling the employee or revoking their sessions. Wrong/missing manager passwords leave the target unchanged. Successful reset still invalidates employee sessions.
- Both password inputs and manager confirmation clear after an attempted server operation or closing/unmounting the dialog. Neither credential is recorded in audit events or returned in responses.

## Verification

- **158 automated tests passed**, 0 failed/skipped, including disposable live support check. Handler cases cover missing/wrong confirmation and local-only proof-session logout. Component-submit tests cover requiring and clearing manager confirmation.
- **13 new rollback SQL checks passed**: direct bypass, unverified check, target/session binding, one-time consumption/replay, expiry, revoked session, attempt limit and grants.
- Existing staff acceptance adapted to require proof: **27 rollback checks passed**.
- Actual QA API/Auth tests: **29 passed**. Wrong/missing manager confirmation rejected, original employee session remained valid after rejection, direct RPC denied, correct password reset succeeded, old employee password/session rejected, new password accepted and original manager session survived confirmation.
- Local no-network browser fixture: modal opens with all seven profile fields, reset form includes manager-password confirmation, empty submission has visible errors, Escape closes the dialog, English labels render. This is mocked browser UI verification plus separate actual API tests; it is not a signed-in deployed-browser end-to-end claim.
- Staging build passed. Existing bundle-size warning remains.
- Six disposable Auth accounts were removed; fixture endpoint disabled with HTTP 410. Production and original pharmacy records remain untouched.

QA migration: `qa_staff_password_manager_confirmation_20261108`; permanent Edge `qa-admin-staff-account` version 2. Private RLS tables intentionally have no client policies or grants. Privileged RPC advisor entries have explicit live-session/ownership guards. The prior leaked-password-protection advisory is unchanged.
