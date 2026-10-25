# Official-source research packet — 2026-10-25

Research and preview only. No approval, database import, purchase, supplier contact, production deployment, or clinical advice.

## Identity research completed

`CLINICAL_RXNORM_CANDIDATES_2026-10-25.json` contains 17 exact-query candidate identities from NLM's public RxNorm API. It records query URLs, concept properties (including IN/PIN type), retrieval time, dataset/API versions before and after the run, and NLM attribution. Both version checks agreed: dataset `05-Oct-2026`, API `3.1.356`.

The reproducible read-only collector is `scripts/research_rxnorm_candidates.py`. It uses `search=0`. NLM documents that normalized search can ignore salt forms; approximate/normalized matches are therefore excluded from this packet. Even an exact query may return multiple concepts; the collector retains all candidates rather than choosing silently.

Documentation:
- https://lhncbc.nlm.nih.gov/RxNav/APIs/api-RxNorm.findRxcuiByString.html
- https://lhncbc.nlm.nih.gov/RxNav/APIs/api-RxNorm.getRxConceptProperties.html
- https://lhncbc.nlm.nih.gov/RxNav/APIs/api-RxNorm.getRxNormVersion.html

`CLINICAL_BILINGUAL_PILOT_REVIEW_2026-10-25.csv` contains 34 **candidate** rows: 17 English queries and 17 proposed Arabic names. RxNorm identifiers are proposals for review, not product mappings. Arabic rows deliberately lack an authoritative source reference/version and reviewer/date. They must not qualify for matching until independently documented and reviewed. Do not change status mechanically to make validation pass. The local intake will also report aliases absent from the current catalog as unrecognized.

Official Arabic starting points inspected or located during research:
- SFDA paracetamol page: https://www.sfda.gov.sa/ar/node/15386
- SFDA bilingual paracetamol article title: https://www.sfda.gov.sa/ar/awarenessarticle/باراسيتامول-paracetamol (search metadata located; direct page fetch timed out).
- SFDA medicine registry: https://www.sfda.gov.sa/ar/drugs-list . Registry product labels, routes, salts and formulations must be reviewed individually; a trade name does not establish a universal ingredient synonym.

## Interaction-source assessment

| Source | Role | Current decision |
| --- | --- | --- |
| RxNorm | Drug identity terminology | Use for candidate identifiers only; no interaction rules inferred. |
| openFDA labeling | Manufacturer-submitted label evidence | Evidence research only; not a validated pairwise interaction checker. |
| DrugBank | Dedicated interaction API documented by provider | Commercial clinical rights require provider confirmation and an appropriate agreement; no subscription or purchase made. |
| Medi-Span | Embedded clinical screening content | Obtain a use-case-specific licensing/coverage response before integration. |
| FDB | Drug knowledge and screening modules | A potential licensed provider; no integration or purchase. |

Primary sources reviewed:
- FDA labeling API: https://open.fda.gov/apis/drug/label/ — includes limitations about care decisions and submitted label contents.
- DrugBank DDI guide: https://dev.drugbank.com/guides/implementation/ddi_checker — documents severity, evidence, management, references and identifiers. Documentation availability alone does not establish the service's availability for this account or territory.
- DrugBank general terms: https://trust.drugbank.com/drugbank-trust-center/terms-of-use — distinguish general non-clinical research rights from a negotiated commercial license.
- Medi-Span: https://www.wolterskluwer.com/en/solutions/medi-span/medi-span/drug-data
- FDB: https://www.fdbhealth.com/solutions/medknowledge-drug-database

No verified quote is available. Before choosing a provider, confirm Syria/end-user territory, pharmacy use, Arabic presentation rights, local ingredient coverage, caching/offline rights, update delivery, API limits, and references/formulation support. No contact was sent.

## Remaining release gates

1. Independently verify Arabic/English alias identity and every active ingredient of each product, including salt/ester, route and formulation.
2. Verify license rights and obtain reviewed interaction evidence with provenance.
3. Measure missed findings and false positives using qualified clinical reference cases; synthetic tests are software checks only.
4. Complete actual browser/mobile and authenticated non-admin tests. The cloud browser was unresponsive during this session; do not mark them passed.
5. Resolve the separately communicated access-control finding with explicit authorization before considering a production release. No database policies or grants were changed.
