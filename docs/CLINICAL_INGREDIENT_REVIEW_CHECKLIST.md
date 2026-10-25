# Clinical ingredient mapping — pharmacist review checklist

**Preview branch only.** No automatic clinical approval, no database mutations, no interaction claims.

## Per-ingredient review
1. Confirm the exact active ingredient(s) from a trustworthy product label or approved local product monograph.
2. Confirm salt, ester, stereochemistry and route as relevant; do not equate ingredients by similar spelling.
3. For combinations, verify the complete ingredient list, not just one detected component.
4. Record the canonical name, identifier (RxCUI if applicable), source URL/document, version/date, reviewer, review date, and outcome.
5. Mark as **unresolved** if a brand cannot be matched confidently. Never treat unresolved as no interaction.
6. Re-review whenever the source or product composition changes.

## Mapping record proposal (not implemented)
- product_id
- ingredient_id
- composition_verified: boolean
- status: pending | approved | rejected
- source_reference_id
- source_version
- reviewer_id
- reviewed_at
- review_notes

## Priority
First: missing ingredients, then ambiguous combinations and dosage annotations, then missing strength/form.
This priority reflects *data completeness*, not clinical severity.

## Interaction rules (not yet populated)
Only a documented and pharmacist-reviewed rule with verified source, severity, recommendation, version and review metadata can be considered for future activation. Test fixtures must never be promoted as real clinical evidence.

## Production safeguards
- Separate test database before creating clinical tables.
- RLS and authenticated admin-only review controls.
- Audit every approval/revocation; preserve historical references.
- Clinical alerts must never silently block or alter POS accounting.
- Explicit user approval and acceptance testing before production merge.
