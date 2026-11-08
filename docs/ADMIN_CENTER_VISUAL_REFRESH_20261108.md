# QA: administration center visual refresh

This update changes the administration center's presentation, keeping the account, backup, role and security flows intact. Production is untouched.

## Design delivered

- Self-hosted IBM Plex Sans Arabic (regular/semibold), with its SIL Open Font License retained under `public/fonts/ibm-plex-arabic`. No new third-party runtime font request is required for the center. Other pharmacy pages retain their existing typography.
- Larger center/page/section headings, icon-led tabs, quieter surfaces, more consistent spacing and visible keyboard focus. Active navigation is emerald. Buttons distinguish save/add (emerald), reload (blue), account details/manual invitations (violet), and session termination (warm warning color). Disabled and hover states remain distinct.
- Account administration has a heading/action toolbar, a styled expandable invitation panel, role badges, and a readable table hierarchy. Email is not duplicated when a name is absent. Employee/facility records are not translated or changed.
- Backup creation and integrity verification have separate cards. Export passphrase and confirmation are vertically stacked, full-width fields with the export action below them. Existing shared passphrase/verification behavior and restore limits remain unchanged.
- Profile has an identity summary, display-name card, email-confirmation card, session-security card, own-password card and recovery card. Forms use vertical labels and full-width controls.
- Language/density selectors are presented as cards with explicit accessible names. Small-screen rules collapse settings/form columns and wrap navigation.
- The employee details modal shares the same type, fields, buttons, dark palette and spacing. Its centering, scroll preservation and manager-password step-up remain unchanged.

## Verification

- Existing suite: 159 passed, 0 failed; one optional live-support smoke check skipped without a disposable session. No real user/account operations were performed for this appearance change.
- Original workspace SSR: 63 passed.
- Staging build passed. Existing bundle-size warning remains. The two self-hosted font files total approximately 481 KB before transport compression and are used by the center/modal.
- AST comparison: 171 Auth/SDK/database calls across the edited operational components are identical to the preceding commit, including arguments. No database/Edge migrations or authorization changes.
- Local mocked browser fixture: Arabic/English navigation, accounts/details modal, vertical backup fields, profile cards, language cards and dark colors reviewed. The two backup labels shared the same 932px width and appeared at separate y positions (629.47 and 728.47). Dark modal and cards used the intended local font and dark surfaces. A low-contrast inactive-tab issue found during review was corrected.
- Browser fixture uses mocked Auth/RPC. This is visual/layout evidence, not a deployed signed-in Auth end-to-end claim. Responsive CSS is included; a real mobile viewport was not independently exercised in this run.

The new overrides are isolated in `src/SYSTEM_ADMIN_PREMIUM.css`. No changes to POS, inventory, accounting, original pharmacy data, employee permissions or password-confirmation rules.
