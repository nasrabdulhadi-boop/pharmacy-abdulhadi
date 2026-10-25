# Clinical catalog read-only audit — 2026-10-25

Supabase production project eewjjzgwoaxhojnjvzgq, public.products. **SELECT only**. No schema, product or transaction changes.

SQL predicate: `where active is true`.

| Metric | Count |
|---|---:|
| Active products | 17,819 |
| Missing or blank active_ingredient | 3,278 |
| active_ingredient contains Arabic characters | 450 |
| active_ingredient contains Latin characters | 14,105 |
| active_ingredient contains both Arabic and Latin | 14 |
| Missing or blank strength | 3,850 |
| Missing or blank dosage_form | 2,856 |

Language counts are **not mutually exclusive**. Presence of a script does not imply that an ingredient is verified, canonical or clinically usable.

## Review priority
1. Products missing ingredient data (cannot safely screen).
2. Mixed-script or ambiguous combination ingredient fields.
3. Arabic and English ingredient aliases: require authoritative composition evidence and human review.
4. Strength and dosage-form gaps: verify before any route-, formulation- or dose-dependent rules.
5. Do not automatically approve based on spelling, transliteration or brand-name similarity.

No clinical rule imports, no clinical POS alerts, no production writes.
