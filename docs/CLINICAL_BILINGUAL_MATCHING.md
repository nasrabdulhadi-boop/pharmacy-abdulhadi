# Arabic–English clinical identity matching

The POS may contain an Arabic product name and an English product name. **Do not compare brand strings to detect drug interactions.** Instead map each product to complete, reviewed canonical active ingredient IDs, and evaluate approved interaction pairs against those IDs.

## Pipeline
1. Preserve original Arabic and English product/ingredient strings, barcode and dosage form.
2. Normalize typography for lookup only (Arabic hamza/diacritics, Latin case); never automatically translate, transliterate or infer synonyms.
3. Review each alias against a traceable label or reference and approve a canonical ingredient ID.
4. Quarantine collisions: a shared alias mapped to different ingredient IDs is ambiguous, not a valid match.
5. For fixed-dose combinations, require **all ingredients** and product formulation/route to be verified before clinical evaluation.
6. Only approved, licensed, sufficiently complete interaction evidence can become a clinical rule. No-match never means safe.
7. Preview-only code currently resolves bilingual aliases but explicitly disables clinical eligibility until completeness and clinical coverage are validated.

## Example (synthetic identity demonstration)
An approved alias record for Arabic "باراسيتامول" and English "Paracetamol" may both map to canonical ID ingredient-1, subject to evidence review. This demonstrates identity resolution, **not a drug interaction claim**. A branded product still needs separate composition verification.

## Integration safeguards
No production POS alerts, no Supabase writes, no modifications to sale processing or stock; test branch only.
