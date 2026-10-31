# QA recovery fix — 2026-10-31

Scope: feature/system-administration-center-preview-20261028 and QA vpjxdsprfcpqclnhbeoh only. No production, main, original manager, password or role changes.

## Evidence

QA Auth logs show recovery mail requests accepted at 06:40:59 and 06:49:04 UTC. The first verification succeeded 14 seconds after each mail; another verification 12 / 30 seconds later failed with `One-time token not found`. Edge logs show different browser user-agent versions on first and second visits, and no subsequent `/auth/v1/user` request within the examined window. This establishes prior consumption, not the identity of the first visitor. Email prefetching or an intervening browser/preview redirect is a hypothesis, not a proven cause.

The installed Auth SDK queues PASSWORD_RECOVERY after initialization. The frontend must not classify getSession completion as proof of an expired link. A pending callback now waits for the SDK event; after 15 seconds without confirmation, the UI describes inability to verify rather than asserting expiry. A real installed SDK test with an in-memory browser and synthetic callback covers that ordering.

## Changes

- QA recovery can verify a mailed numeric OTP with `verifyOtp({email,token,type:'recovery'})`.
- Only an Auth-verified recovery event opens the existing new-password form. Production and malformed-code calls fail before any Auth request.
- OTPs/passwords are not logged or persisted by application code.
- User-facing request limits and invalid-code messages remain sanitized.
- A QA-specific OTP-only email template is in `audits/qa/recovery_email_template.html`. Its static navigation link contains no credential and cannot consume a recovery code.

## Required configuration / remaining blocker

The template is prepared, but has NOT been applied to hosted QA Auth. The connector exposes no Auth configuration update; the dashboard has no authenticated browser session.

In Supabase QA Authentication > Emails / Email Templates > Reset Password, replace the message body with `audits/qa/recovery_email_template.html` and save. Preserve existing Auth rate limits and email confirmation. Do not apply this to production. Request one NEW recovery email after saving; existing mails contain the old one-use link and are not converted into codes.

The user must enter the received OTP and choose their own password. No successful personal-account password reset or email delivery is claimed by this change.

## Validation

- npm test: 97 pass, 0 fail, 1 skipped (existing credential-dependent smoke).
- Includes installed SDK callback-order integration, OTP recovery grant/session checks, production isolation, malformed input and sanitized failures.
- Shared workspace React SSR contract: 63 role/section cases.
- QA staging build: passes; existing bundle-size warning remains.
- Browser inspection verifies the deployed QA recovery-code input; actual email-to-password end-to-end test remains pending template configuration and user entry.

## Confirmed continuation — 2026-10-31

- User confirmed creating and saving the Gmail application password in QA SMTP.
- One recovery request to QA returned HTTP 200; the user then confirmed the application opened and everything worked after the password-setting instructions. This is user-reported recovery/login success, not an independently observed browser trace. No password or OTP was collected.
- The OTP-only template was already saved through the dashboard. Earlier instructions above to apply the template are superseded.
- Verified remote branch and latest ready Preview both remained at d71e344 before these changes.
- QA sale adapter now explicitly rejects unsupported invoice discounts (including malformed values) before sending any operation; previously a supplied discount could silently disappear. This does not enable discounts in the QA backend.
- Updated obsolete browser acceptance expectations to the shared original Admin shell. Interactive rerun remains pending: prior temporary account/session files are absent. No personal account password was requested or changed.
- Validation: 98 passed, zero failed, one skipped; 63 section/role render checks passed; build passed with existing chunk-size warning.
- No production database, main branch, or original administrator was modified.
