# Privileged function review — preliminary inventory (2026-10-28)

**Production read-only inspection only. No SQL changes made.**

## Findings
- 126 SECURITY DEFINER functions in public schema.
- 111 contain a textual reference to is_admin().
- 36 contain a textual reference to auth.uid().
- 12 contain neither is_admin(), auth.uid(), nor app_metadata as a textual reference.
- Textual checks are a **triage heuristic, not a security proof**. Referenced helper functions, GRANT EXECUTE, SQL search_path, nested calls, and function bodies must be audited.

## Priority review list
- admin_cashbox_summary
- admin_supplier_return
- admin_supplier_return_bundle
- ab_apply_supplier_return_credit_v1
- ab_immutable_supplier_return_v1
- ab_validate_supplier_return_v1
- validate_supplier_payment_allocation
- rls_auto_enable
- create_public_order
- submit_medicine_request
- submit_public_prescription
- track_public_order

Public-order/request functions may be intentionally public and require abuse protection, not admin gating. Triggers and internal helpers must be reviewed for reachability; do not revoke blindly.

## Blocking security concerns
- public.is_admin() has a hard-coded email exception; Root UI also accepts that address. Do not change until a protected owner identity and verified recovery have been tested.
- Current production Auth has one admin user. Never create a technical-support account on production before completing the review.
- SECURITY DEFINER functions must be checked individually for authenticated/anon EXECUTE grants, role verification, row-level data leakage, write side effects, and safe search_path.

## Next steps
1. Confirm an isolated staging project dedicated to system administration. The existing clinical QA project is reserved for clinical tests and must not be repurposed without approval.
2. Use synthetic staging records, separate secrets, and a staging Vercel deployment.
3. Test each privileged function as anonymous, technical_support, and owner, including denied operations.
4. Create an explicit permission matrix; audit public endpoints and customer catalog separately.
5. Only then implement role-aware production migrations with a rollback plan.

No conclusion of exploitability follows from the heuristic counts alone.
