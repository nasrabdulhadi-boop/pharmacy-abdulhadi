# Clinical preview UI follow-up — 2026-10-25

Branch: `feature/clinical-assistant-preview-v1`. Based on `17e2791`.

## Changes

- Invalidate obsolete search results/errors when the query changes. Ignore late responses after a newer request or unmount; prevent repeated Enter submissions while a search is active.
- Invalidate pending CSV reads and clear the previous inspection when catalog auditing restarts. Ignore late file results after a newer file or unmount.
- Localize alias-validation and catalog-review reasons; limit the combined displayed CSV issue list to 50 items, rather than up to 50 per category. Describe CSV record numbering explicitly because quoted records can span lines.
- Keep the existing all-products review export, label it with its scope/count, and add a separate export containing priorities 1–4 only. The filtered count matches the review heading.
- Include unsupported/other scripts in alias summary counts. Add a search input accessible label and announce CSV errors/results.

## Validation

- Baseline: 96 automated tests passed.
- Updated: 102 automated tests passed, including deferred asynchronous success/error cases and CSV rejection presentation.
- `npm run build`: passed; existing bundle-size warning remains.
- Build/unit results are not browser end-to-end, mobile, authorization, or clinical validation.

## Boundaries

No database schema, records, credentials, roles, sales, purchases, production branch, or clinical rules changed. Existing read RPC names/arguments remain unchanged. Imported review files remain local inspections and never grant clinical approval.

Arabic/English clinical matching still requires independently documented, reviewed aliases and complete composition mapping. No approved interaction rules are supplied. Non-admin account testing, direct unauthorized Data API requests, and mobile browser validation remain outstanding.
