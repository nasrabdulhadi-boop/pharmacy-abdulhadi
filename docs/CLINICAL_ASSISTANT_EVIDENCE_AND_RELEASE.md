# Clinical assistant: evidence and release policy (preview only)

**Status:** prototype. No approved interaction rules, no live clinical alerts, no claims of medication safety.

## Sources and their roles
- RxNorm: https://www.nlm.nih.gov/research/umls/rxnorm/index.html — concept/ingredient normalization for supported medicines; not a comprehensive interaction checker. Validate coverage for Syrian brands.
- DailyMed: https://dailymed.nlm.nih.gov/ — manufacturer labeling, including warnings and interactions in labels; labeling is not a complete structured pairwise interaction database.
- openFDA Drug Label: https://open.fda.gov/apis/drug/label/ — structured access to labeling data; do not infer an interaction rule from free text without review.
- Specialist commercial references: evaluate licensing, geography, maintenance and redistribution rights before using in production.

## Required schema before interaction alerts
- clinical_ingredients(id, canonical_name, rxcui_nullable, status, reviewed_at)
- clinical_ingredient_aliases(id, ingredient_id, alias, locale, source_id, reviewed_at)
- clinical_product_ingredients(product_id, ingredient_id, mapping_status, source_id, reviewer_id, reviewed_at)
- clinical_references(id, publisher, title, url, version, retrieved_at, license_status)
- clinical_interaction_rules(id, ingredient_a_id, ingredient_b_id, severity, mechanism, recommendation, reference_id, reviewed_at, active)
- clinical_screening_logs(id, actor_id, result_summary, ruleset_version, created_at)

**No DDL has been applied.** All schema names above are design proposals only.

## Release gates
1. Obtain and document license/permissions for clinical rule data.
2. Pharmacist-review all rule entries, product ingredient mappings and synonym/combination handling.
3. Test positive and negative reference cases, missing ingredient cases, multiple actives, and route/dose dependence.
4. Treat unknown/unmapped products as incomplete screening, never as a green/clearance result.
5. Enforce admin authorization and RLS; do not transmit identifiable patient data to external services.
6. Verify latency and resilience; screening must not alter sale or stock accounting.
7. Preview build and authenticated QA, then explicit approval before any production merge.

## Preview audit
The preview calls existing `admin_get_products_page(p_limit:500,p_offset:0)` read-only and reports **only the first 500 records**. It does not represent the full inventory or clinically validated ingredient coverage. The prototype flags exact ingredient text overlap, not proven therapeutic duplication.
