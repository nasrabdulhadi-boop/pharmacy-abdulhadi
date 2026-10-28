# Production RPC privilege review — 2026-10-28

Inspection was read-only. No live RPC calls, data writes, or privilege changes.

| Public RPC | EXECUTE granted to anon/authenticated | Direct admin check | Downstream check | Initial classification |
| --- | --- | --- | --- | --- |
| admin_cashbox_summary | yes/yes | no | admin_cashbox_summary_v2 checks public.is_admin() first | Indirectly guarded; test with anonymous/support session |
| admin_supplier_return | yes/yes | no | admin_currency_supplier_return_v2 checks public.is_admin() first | Indirectly guarded; wrapper reads batch purchase_id before delegated check |
| admin_supplier_return_bundle | yes/yes | no | admin_currency_supplier_return_v2 checks public.is_admin() first | Indirectly guarded |
| create_public_order | yes/yes | no | not reviewed | Intentionally public endpoint candidate |
| submit_medicine_request | yes/yes | no | not reviewed | Intentionally public endpoint candidate |
| submit_public_prescription | yes/yes | no | not reviewed | Intentionally public endpoint candidate |
| track_public_order | yes/yes | no | not reviewed | Intentionally public endpoint candidate |
| rls_auto_enable | yes/yes | no | event trigger | Review trigger reachability, not normal RPC execution |

**Caution:** EXECUTE privileges and function-name heuristics do not prove exploitability. Do not revoke or alter production permissions until dependencies, public customer workflows and denial tests are covered.

## Proposed staging assertions (not executed)
- anon and technical_support cannot call admin_cashbox_summary or obtain cashbox rows.
- anon and technical_support cannot modify stock using admin_supplier_return or admin_supplier_return_bundle.
- owner can use legitimate admin operations on synthetic data only.
- public endpoints allow intended public operations but cannot expose customer/patient data or leak financial records.
- technical_support can read only sanitized technical health via a dedicated, carefully scoped API.
- no owner email bypass is used for new roles.

## Follow-up
Inspect EXECUTE grants on all SECURITY DEFINER functions, then run staging-only denial tests using real role JWTs. Preserve production until all tests pass.
