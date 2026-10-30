# Full original-interface supplier payment preview

Updated 2026-10-30 on `feature/supplier-payment-currency-preview-20261030`.

Uses the original `Admin` shell, navigation, screens, CSS and login form from production source `901e0081e78396c7f4df62740d5b3074a1473f41`. The separate two-screen workbench is removed. The currency selector is integrated into the original supplier ledger.

## Original administrator login

Use the original administrator account, currently `drnaser@pharmahadi.com`, and its existing password. No new QA user, password copy, reset or email change was performed.

The browser authenticates directly with production Supabase Auth using a public key and separate browser session storage. The QA Edge Function validates the bearer token through production `/auth/v1/user`, requiring the exact original administrator ID and its server-managed administrator role. Passwords never pass through QA. The function implements this authentication itself, so the legacy QA-project JWT gate is disabled; anonymous/invalid tokens are denied by the handler.

All pharmacy data operations go to the fixed QA gateway, with no production data fallback. The QA service key remains in the Edge Function environment. The database gateway is callable only by `service_role`, validates the verified actor, restricts operation names/arguments, and dispatches only within `pharmacy_supplier_stage`.

## Isolation

- Existing QA project `vpjxdsprfcpqclnhbeoh`; new private schema `pharmacy_supplier_stage`.
- Original structure: 30 tables, 129 operational functions plus staging authorization, constraints, 47 additional indexes and original triggers.
- No real products, financial data, customers, passwords, users or sessions copied.
- Three synthetic products and three linked purchase invoices: USD debt 150; SYP debt 14000.
- RLS on every table; anonymous/authenticated direct schema access revoked. No direct policies is intentional: only the server gateway accesses these private tables.
- Separate private Storage bucket `supplier-preview-prescriptions` for preview files.
- No production database migration, merge, deployment, account change or historical rewrite.

## Payment behavior

Tender currency is independent of debt currency. SYP-per-USD rate is frozen per payment. Allocations retain debt currency; additive tender fields retain actual money paid. The original cashbox, invoice balances, receipt, supplier ledger and audit share one transaction. Request UUID prevents duplicate retries. Cash-recording failure rolls back settlement.

## Validation

- Production and full-preview Vite builds passed.
- Eight Node tests passed: original navigation/login HTML rendering; routing isolation; session failures; query compatibility; gateway authorization; wrong account/role denial; production identity-only access.
- Deployed Edge Function returned HTTP 401 to a real unauthenticated request.
- Real QA SQL passed original dashboard/read APIs, inventory joins, table mutation, supplier ledger/cashbox/report integration, four currency combinations, retries and access isolation.
- Original POS sale passed with stock/cash/report integration.
- All test writes rolled back; seed invoices remain unpaid for manual testing.
- Private function search paths pinned; unrelated QA advisories left unchanged.

The owner's actual password login and final visual browser inspection were not performed. Prior browser access was blocked by the automatic usage-limit review; no browser pass is claimed. Manual end-to-end review is still required before production integration.

## Setup

Full-system SQL files in this directory are QA-only. Edge Function: `supabase/functions/supplier-original-admin-preview/index.ts`. Branch-scoped Preview variables separate original Auth URL from QA data URL. Never enable this preview flag for Production.
