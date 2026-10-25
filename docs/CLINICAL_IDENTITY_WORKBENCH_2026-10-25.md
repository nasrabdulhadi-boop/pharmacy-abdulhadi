# Local identity workbench — preview delivery, 2026-10-25

## Implemented

- The clinical preview can simulate bilingual identity overlap using structurally qualified aliases from an inspected local review CSV. Inputs, results and aliases remain in component memory; no clinical rules or product mappings are activated.
- Incomplete or conflicting combination aliases fail closed. The identity simulation preserves explicit salt identifiers, quarantines duplicate product identifiers and limits each simulation to 50 products.
- Reviewed-rule screening now requires license metadata in the bilingual path as well as the existing rule-engine path. Synthetic positive fixtures explicitly declare test-only licensing; missing, unknown and malformed license metadata yield no findings.
- Alias, mapping, manifest and rule provenance checks reject whitespace-only fields, impossible dates, invalid identifiers, non-text metadata and unsafe source URL schemes. These remain structural checks, not verification of authorship, source contents or legal rights.
- Source-file results are invalidated when the selection, CSV or catalog audit changes. Late file reads do not replace the latest inspection.
- Scoped narrow-screen wrapping and keyboard-focus styles were added; actual phone validation remains outstanding.

## Evidence and reproducibility

See `CLINICAL_OFFICIAL_SOURCE_REVIEW_2026-10-25.md`, the exact-query RxNorm snapshot and the 34-row bilingual candidate CSV. The research collector has no pharmacy connection. Candidate data are not imported into application runtime and contain no pharmacy records.

## Validation

- `npm run build`: passed, including 119 passing Node tests.
- Cases cover local CSV → aliases → Arabic/English identity matching; unknown aliases; fully and partly mapped combinations; salt separation; conflicting and duplicate identifiers; invalid provenance; unlicensed rules; and research-packet rejection.
- The main-file diff outside `ClinicalPreview` is unchanged except the new clinical helper import. No SQL, authentication, permissions, sale, purchase or accounting code was modified.
- The build still reports the pre-existing large-bundle warning.

## Explicitly incomplete

- This is an identity-data simulation, not a clinically validated DDI service. No approved runtime interaction dataset is supplied; no reassuring safety result is generated.
- Clinical source licensing, pharmacist verification of aliases and product compositions, and reference-case clinical validation are pending.
- Cloud browser operations and reset timed out during this session. Updated live UI/mobile behavior has not been confirmed.
- Authenticated non-admin testing remains unavailable without an existing suitable account. The separately communicated database access finding requires authorization to change permissions and was not modified.

No production merge, production data changes, purchase, permission change or supplier contact was performed.
