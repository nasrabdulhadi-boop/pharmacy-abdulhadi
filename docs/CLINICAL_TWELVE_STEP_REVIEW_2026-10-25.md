# Twelve-step clinical preview delivery review — 2026-10-25

Branch: `feature/clinical-assistant-preview-v1`. Baseline: `172ec21`.
This closes a development/QA iteration, **not clinical acceptance or a production release**.

| # | Requested step | Evidence delivered | Remaining gate |
| --- | --- | --- | --- |
| 1 | Code audit and fixes | Corrected missing/extra/duplicate mapping reasons; shared fail-closed rule registry; source conflict quarantine; 138 passing software tests | Bounded code review, not proof of all possible defects |
| 2 | Data protection and permissions | Nine passing in-memory SQL role/grant/RLS tests, synthetic records only | Live finding unresolved; no authenticated non-admin account; no live permission changes |
| 3 | Smart medicine search | Arabic hamza/diacritics/numeral and Latin normalization; complete-audit search supplements live RPC; additional-barcode/live results retained and prioritized | Real-device/live regression of new UI pending; text search does not infer chemical identity |
| 4 | Product-to-ingredient mapping | CSV local identity sandbox, conflict/combination guards, existing 34 candidate rows | Independently documented pharmacist-approved aliases and complete product compositions |
| 5 | Medical source database | Official-source research packet and 17 RxNorm exact-query candidates; stricter evidence metadata and whole-record quarantine | Clinical interaction dataset, rights and ongoing update process |
| 6 | Interaction engine | Both prototype paths now share license/duplicate/conflict rules; synthetic positive/negative/unknown cases | No approved runtime DDI rules; no clinical validation |
| 7 | Therapeutic duplication | Exact text overlap and local canonical identity overlap are implemented | These do not establish same-class therapeutic duplication, dose or route appropriateness |
| 8 | Advanced clinical alerts | Existing unavailable/incomplete warnings preserved; no reassuring result inferred | Pregnancy, breastfeeding, renal function, age, dose and route rules are not implemented/validated |
| 9 | Product audit and CSV | Existing read-only audit/review exports; shared spreadsheet-safe cell quoting; new invisible-prefix formula tests | New live-browser export regression pending; source review is not clinical approval |
| 10 | UI and phone | Scoped responsive/focus styles and accessible search; result-source disclosure | Actual phone and current live UI testing remain unverified after cloud browser failure |
| 11 | Final clinical/security testing | 138 software tests, 9 isolated SQL tests, successful Vite build; synthetic 18k benchmark | Clinical reference cases, live non-admin/JWT/Data API and phone acceptance remain incomplete |
| 12 | Final release/report and approval gate | This report, reproducible tests, preview-only commit/deployment preparation | No production merge or POS activation; release remains blocked |

## New changes in this iteration

- Baseline had 125 tests, including two failures caused by a newer duplicate-mapping branch catching missing/extra mappings under the wrong reason. The duplicate check now compares the count of valid rows with their unique ingredient IDs; missing/extra ingredients still fail closed under the established reason.
- Added `clinicalCatalogSearch.js`; live RPC results remain the first source so additional barcode matching and live field values are retained. Complete-audit text results supplement them, with explicit cache-age disclosure. No public site or POS search was changed.
- Added shared `clinicalCsvCell`; all four clinical CSV exporters quote cells and neutralize formula prefixes after whitespace/invisible characters. Imported files still do not activate clinical rules.
- Added shared reviewed-rule preparation to eliminate differing conflict handling between the two prototype engines. Non-text explanations cannot qualify as clinical rules.
- Conflicting source-record evidence is fully quarantined instead of retaining its first version as an accepted research candidate. All retained evidence remains pending and clinically unapproved.

## Exact validation scope

- `npm run build`: 138 software tests passed, 0 failed, 0 skipped; Vite build passed. The existing >500 kB bundle warning remains.
- `npm run test:clinical:security`: 9 isolated SQL tests passed, 0 failed, 0 skipped. See `qa/clinical-security/README.md` for boundaries.
- Synthetic 18,000-record benchmark on workspace Node 24: index build 83.36 ms; ten searches median 11.21 ms, maximum 22.13 ms. These are server measurements, not phone/browser guarantees.
- The main application diff is confined to `ClinicalPreview` plus its search-helper import. Other changes are clinical helpers/tests/docs and an isolated QA package/script. No pharmacy SQL, roles, records, sales, purchases or accounting logic were changed.

## Release decision

**BLOCKED / RESEARCH PREVIEW ONLY.** Software tests do not establish medical correctness, legitimate licensing or live authorization safety. No percentage of “clinical completion” is reported because the missing external validation is a release gate, not a cosmetic task.

Do not merge to `main`, apply grants/migrations to the live pharmacy, or activate POS alerts from this iteration. Preserve a separately authorized staging validation and independent pharmacist/clinical sign-off before proposing production work.
