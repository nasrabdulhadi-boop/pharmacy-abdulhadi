# Read-only active-ingredient inventory — 2026-10-25

Source: production `public.products`, read-only SQL aggregates. **No patient, purchase, sale, stock or price data exported.**

- Total product rows: **17,819**
- Nonblank active ingredient field: **14,541** (81.60%)
- Missing/blank active ingredient: **3,278** (18.40%)
- Distinct case-folded, trimmed nonblank ingredient labels: **2,373**. These are **labels**, not validated chemical entities.

## Top recorded ingredient strings (frequency, not clinical validation)

| Recorded string | Products |
|---|---:|
| paracetamol | 317 |
| diclofenacSodium | 222 |
| ibuprofen | 206 |
| amoxicillin + clavulanicAcid | 187 |
| aspirin | 131 |
| atorvastatin | 127 |
| metronidazole | 125 |
| azithromycin | 123 |
| rosuvastatin | 118 |
| metformin | 114 |
| amlodipine + valsartan | 109 |
| dexamethasone | 106 |
| cefuroxime | 100 |
| ciprofloxacin | 95 |
| gentamicin | 93 |
| ampicillin | 86 |
| cefixime | 82 |
| amoxicillin | 79 |
| prednisolone | 77 |
| amlodipine + HydroChlorThiaZide ( H.C.T.Z. ) + valsartan | 73 |
| lidocaine | 72 |
| ampicillin + cloxacillin | 67 |
| sitagliptin | 66 |
| glycerol | 64 |
| ceftriaxone | 62 |

## Pilot queue policy
- These are **candidate labels only**; no aliases, products, compositions or interactions are clinically approved by this inventory.
- Verify each candidate against manufacturer label / official SPL and identity terminology, preserving salt, strength, route, and all components of combination products.
- Keep English and Arabic synonyms as separate reviewed aliases mapped to one canonical ingredient identifier only after pharmacist verification.
- Prioritize frequent single-ingredient labels for pilot; review combination products separately, including completeness of every ingredient.
- Missing-ingredient rows remain **unresolved**, never interpreted as interaction-free.
- All work remains on the preview branch; no changes to production Supabase.
