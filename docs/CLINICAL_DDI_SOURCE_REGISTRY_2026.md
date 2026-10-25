# Drug interaction evidence source registry — research only

Updated 2026-10-25. **Do not import into production or use for clinical alerts without rights verification, provenance checks, pharmacist review, and acceptance testing.**

| Source | Coverage / role | Access | Licensing and clinical gate | URL |
|---|---|---|---|---|
| DDInter 2.0 | 302,516 DDIs; 857 drug-food; 8,359 drug-disease; 6,033 therapeutic duplication records | Web, category CSV download page | Official terms: CC BY-NC-SA 4.0, non-commercial only; no production/commercial import without separate permission; confirm CSV completeness | https://ddinter2.scbdd.com/ |
| DDInter 1.0 | 236,834 DDIs; historical comparison | Category CSV files | Older release; not additive to v2 | https://ddinter.scbdd.com/download/ |
| DailyMed SPL | Original structured US label text, drug interactions section | Public REST/XML and label ZIP | Evidence source, NOT a normalized pairwise DDI knowledge base; review product/route/version | https://dailymed.nlm.nih.gov/dailymed/app-support-web-services.cfm |
| openFDA labeling | Searchable label drug_interactions fields | Public API | Not a clinical DDI checker; API itself warns against care decisions | https://open.fda.gov/apis/drug/label/how-to-use-the-endpoint/ |
| DailyMed-derived 2026 DDI dataset | Research dataset, 399,021 extracted rows reported | Zenodo | Derived extraction requires validation, licensing and false-positive assessment | https://zenodo.org/records/21597970 |
| DrugBank | Structured interactions and pharmacology | Licensed database | Commercial and safety-critical use restricted without contract; do not scrape or ingest | https://trust.drugbank.com/drugbank-trust-center/terms-of-use |
| RxNorm / RxNav | Standardized names and identifiers | NLM API | RxNav interaction service was discontinued 2024-01-02; use only for identity mapping | https://www.lhncbc.nlm.nih.gov/RxNav/information/FAQs.html |
| DrugCentral | Drug identities and structured pharmacology | Public downloadable database | Drug-target data is not equivalent to a clinical DDI database; inspect reuse terms | https://www.drugcentral.org/download |
| TWOSIDES | Mined drug-combination adverse-event signals | Research CSV | Signals are not proven causal clinical interactions; validation and license needed | https://tatonettilab.org/offsides/ |
| DDI Corpus 2013 | Annotated text for DDI extraction evaluation | Zenodo download | CC BY-NC 4.0, not for commercial use; not a clinical decision engine | https://zenodo.org/records/10560167 |
| DDI-HierPred 2026 | Research prediction datasets | Zenodo | DrugBank-derived: check downstream rights; predicted effects not validated alerts | https://zenodo.org/records/21986820 |
| KEGG DRUG | Drug and interaction research reference | Web/licensed | Nonacademic use requires commercial license | https://www.genome.jp/kegg/legal.html |

## Integration priority
1. DDInter 2.0 official terms explicitly require CC BY-NC-SA 4.0: do not ingest into a commercial pharmacy application without written permission; research and schema assessment only.
2. Use RxNorm for reviewed identity alignment and DailyMed/openFDA to verify original label passages, including label date and exact product formulation.
3. Evaluate 2026 DailyMed-derived dataset against primary labels and curated DDInter; quantify duplicate pairs, contradictions and unsupported claims.
4. Keep TWOSIDES and ML datasets in **signal/research only** category, never convert directly into severity-ranked warnings.
5. Seek an explicit license for commercial clinical use before deploying any protected source. Do not infer rights from free website access.

## Proposed provenance fields
source_id, source_url, source_license_status, source_version, downloaded_at, publication_date, original_drug_a, original_drug_b, canonical_ingredient_a, canonical_ingredient_b, route, mechanism, severity_original, management_original, evidence_type, label_set_id, reviewer_id, reviewed_at, review_status, extraction_confidence.

## Release gate
No database imports or production alerts until source terms are confirmed, ingredients are reconciled, high-risk cases clinically reviewed, false-positive/false-negative testing completed, and the user approves production rollout.

## Verified restriction
DDInter 2.0 official terms: https://ddinter2.scbdd.com/terms/ — CC BY-NC-SA 4.0. The site explicitly warns that no recorded interaction does not mean a combination is safe. The 2026 Zenodo DailyMed-derived dataset displays a license heading without a clearly rendered license value; obtain and verify rights before reuse.

## Additional candidates verified 2026-10-25

| Source | Public reported coverage | Reuse / limitations | URL |
|---|---|---|---|
| MedLens DDI Evidence (Hugging Face) | 21,810 interaction pairs, 105,460 pair-level adverse-effect rows, 162,600 raw signals | Dataset card claims CC BY 4.0. Independently verify provenance, original-source rights, data quality and evidence before clinical use | https://huggingface.co/datasets/ASHu2/medlens |
| Enzyme-resolved DDI severity resource (Noor 2026) | 1,900 pairs, 240 drugs, 35 enzymes/transporters | Repository claims CC BY 4.0, but harmonizes DDInter 2.0 and DrugBank; check upstream rights before commercial reuse; manuscript submitted, not necessarily peer-reviewed | https://github.com/adeebnoor/ddi-enzyme-severity-resource |
| DailyMed-derived DDI 2026 earlier release | Over 90,000 interaction pairs across 2,038 drugs per dataset card | Automated sentence-level extraction; verify licensing, provenance and false positives; supersession relationship to 399,021-row record unclear | https://zenodo.org/doi/10.5281/zenodo.19685458 |
| openFDA bulk drug labeling | Full zipped JSON drug label datasets; 14 label files listed as of 2026-10-08 | Primary labeling evidence, not a curated pairwise DDI database; snapshot/version required | https://open.fda.gov/data/downloads/ |
| DrugBank DDI API | Product-level DDI endpoint supports severity, evidence level and management | Licensed service; request quote/rights before production; do not harvest without authorization | https://docs.drugbank.com/api-docs |

### Important research distinction
The MedLens and enzyme-resolved dataset licenses as stated by publishers do not automatically override licenses of embedded upstream content. Do not merge them into commercial runtime without provenance and counsel/licensing review. The DailyMed-derived 399,021 **rows** are not necessarily 399,021 independent validated drug pairs. Research datasets, automated extraction and pharmacovigilance signals cannot be equated to clinically validated rules.
