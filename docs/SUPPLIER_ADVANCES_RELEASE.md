# Supplier advances release

An invoice of 100 paid with 120 is settled for 100 and creates a separate 20 credit in the supplier's account. Payments without invoices can create advances. Later invoices automatically apply same-currency advances before new money. A selected invoice receives its own settlement; otherwise payments settle oldest outstanding same-currency invoices before creating credit.

The entire actual cash tender is recorded once. Reusing advance credit creates allocations against the original receipt and an application history, without a new cash entry, expense or profit adjustment. USD/SYP account balances remain separate; converted tender uses a frozen exchange rate. Credit is shown in green with an explicit pharmacy-credit label in supplier accounts, purchase entry/detail and reports.

## Preservation and security

Three additive tables and guarded functions; no historical rows, existing table columns, inventory prices, roles, passwords or accounts are rewritten. Each migration independently fingerprints existing tables and aborts on change. A separate before/after comparison matched all 30 pre-existing tables. Supplier locks serialize financial changes, request identifiers prevent duplicate saves, and stale credit quotes reject before inventory changes. Financial history has restrictive foreign keys against accidental deletion. Core creation/application helpers are not callable by authenticated clients; public entry points require admin authorization.

## Validation

Eight Node tests and the production build passed. SQL acceptance passed on isolated staging and production with rolled-back fixtures: invoice/payment excess, auto reuse, currency conversions, rate changes, no double cash, no-invoice advances, discount, retry/payload conflicts, invalid inputs, owner/currency validation, reports, return/refund and permissions. Existing POS/stock/currency/report regression suite also passed. Real concurrent staging requests proved shared credit cannot be double spent and identical purchases/payments commit once. Production integrity counters are zero. Authenticated browser visual testing was not performed.

## Deployment and recovery

Apply production SQL files 1, 2 and 3 sequentially (already applied for this release), run acceptance, then deploy the production source. The complete migration file is the equivalent single-transaction alternative for a fresh installation; do not apply both variants. Keep the original manager login unchanged.

If frontend recovery is necessary, retain the new tables, purchase wrappers, credit application logic and financial projections. Do not delete advances or revert the integrity check to assume every payment is fully allocated. A frontend rollback must preserve users' financial history.
