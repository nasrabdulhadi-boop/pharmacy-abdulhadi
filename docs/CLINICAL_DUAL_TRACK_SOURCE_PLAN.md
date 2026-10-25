# Clinical data sourcing — dual-track pilot (research only)

## Isolation and release gate
- Work on `feature/clinical-assistant-preview-v1` only. No writes to production Supabase; no POS integration or automated sale blocking.
- All ingested source excerpts are **research candidates**, never approved interaction rules.
- No interaction finding may be presented as exhaustive or as proof that a combination is safe.
- Clinical rules require source URL/document, version, reviewer, review timestamp, evidence, and **verified license reference**; the release gate remains disabled pending independent clinical validation.

## Free official sources
1. **DailyMed SPL**: https://dailymed.nlm.nih.gov/dailymed/app-support-web-services.cfm . Source label SET ID, label version, effective date, active ingredients, and DRUG INTERACTIONS section where available. This is label-specific US content, not a complete pairwise DDI knowledgebase.
2. **openFDA drug labeling**: https://open.fda.gov/apis/drug/label/how-to-use-the-endpoint/ . Use `https://api.fda.gov/drug/label.json`; collect `drug_interactions` plus label identifiers, source version, retrieval timestamp, and provenance. Do not infer pairwise clinical severity from raw label text. API coverage and clinical suitability are limited; check terms before redistribution or commercial integration.
3. **DailyMed–RxNorm mapping**: https://dailymed.nlm.nih.gov/dailymed/app-support.cfm . Use available SPL-to-RxNorm links as **candidate identifiers** only. US brand-name coverage does not guarantee Syrian products match.

## Bilingual ingredient identity pipeline
1. Export the pharmacy catalog **read-only**, in paginated chunks, to an isolated review workspace. Retain product ID, Arabic/English display names, active ingredient, strength, form, and manufacturer; do not export prices, patient or transaction data.
2. Normalize Arabic hamza/diacritics and Latin case for candidate discovery, but **never** auto-approve chemical equivalence, salts, esters, strengths or combinations.
3. For each candidate, attach canonical ingredient ID, approved Arabic/English aliases, source identifiers, product composition manifest (all ingredients), and pharmacist reviewer/date.
4. Quarantine ambiguous, unmatched and multi-ingredient entries. The bilingual rule engine fails closed for unverified identity or incomplete composition.
5. Evaluate using synthetic Arabic/English pair tests; after human validation, measure catalog coverage, unresolved rows and false-positive/false-negative cases. No clinical rollout without explicit signoff.

## Commercial vendor evaluation (no purchase)
- **DrugBank Clinical API**: https://docs.drugbank.com/api-docs . Provides dedicated DDI endpoints, descriptions, severity and management fields. Commercial use requires a separate license: https://trust.drugbank.com/drugbank-trust-center/drugbank-terms-of-service . Request a quote covering Syrian pharmacy use, end-user access, hosted integration, redistribution/caching, API limits, update cadence, and support; no price is assumed.
- Evaluate any second licensed vendor against the same rubric: **legal use in Syria**, availability and sanctions/compliance, Syrian brands and ingredient mapping, DDI breadth, evidence/references, severity/management, update policy, SLA, integration and total cost. Do not ingest a proprietary DDI dataset without permission.

## Pilot acceptance
- Reproducible source snapshots with license status and citations.
- At least one reviewed Arabic/English synonym pair and one fully reviewed combination, plus deliberate unknown/conflicting cases, exercised in **synthetic tests only**.
- No imported label text promoted to `approved` without pharmacist review and license verification.
- Build/tests pass on preview; production stays unchanged.
- Coverage and clinical reliability must be separately validated; green CI is not clinical approval.
