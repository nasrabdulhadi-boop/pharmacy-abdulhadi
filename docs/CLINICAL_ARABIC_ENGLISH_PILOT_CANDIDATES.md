# Pharmacist bilingual alias pilot — review queue, not approved data

Based on the 2026-10-25 read-only count and top 25 strings. All proposed Arabic labels below are **candidates** requiring label and pharmacist verification; none should be inserted as `approved`.

| Recorded catalog label | Arabic review candidate | Main verification concern | Products |
|---|---|---|---:|
| paracetamol | باراسيتامول | Confirm exact active ingredient and combination status | 317 |
| diclofenacSodium | ديكلوفيناك الصوديوم | Sodium salt must remain explicit; not automatically identical to potassium | 222 |
| ibuprofen | إيبوبروفين | Verify product formulation | 206 |
| amoxicillin + clavulanicAcid | أموكسيسيلين + حمض كلافولانيك | Two active ingredients, verify form and salt details | 187 |
| aspirin | أسبرين / حمض أسيتيل الساليسيليك | Confirm aspirin identity and dose context | 131 |
| atorvastatin | أتورفاستاتين | Verify actual salt on product label | 127 |
| metronidazole | ميترونيدازول | Verify formulation and route | 125 |
| azithromycin | أزيثرومايسين | Verify salt/formulation | 123 |
| rosuvastatin | روسوفاستاتين | Verify actual salt | 118 |
| metformin | ميتفورمين | Verify strength and release form | 114 |
| amlodipine + valsartan | أملوديبين + فالسارتان | Combination composition completeness | 109 |
| dexamethasone | ديكساميثازون | Verify salt/ester, route | 106 |
| cefuroxime | سيفوروكسيم | Axetil versus sodium formulations require review | 100 |
| ciprofloxacin | سيبروفلوكساسين | Verify formulation | 95 |
| gentamicin | جنتاميسين | Verify salt/route | 93 |

## Required reviewer workflow
1. Identify exact product and manufacturer leaflet or official label; note label identifier and version.
2. Assign stable canonical ingredient ID only after validating chemical identity. Maintain separate IDs where clinically relevant for salts/esters or formulations.
3. Record each Arabic and English alias separately, source reference, review timestamp and pharmacist identity.
4. For combination products, review *all* ingredients and a composition manifest; partial coverage is not approval.
5. Feed only manually approved rows to isolated CSV review; the CSV import does not activate rules or change production.

## Explicit exclusions
No drug-interaction recommendations, severity assignments, license claims or production eligibility are implied by this candidate list. Do not auto-approve translations, infer identity from spelling, or mark unreviewed items safe.
