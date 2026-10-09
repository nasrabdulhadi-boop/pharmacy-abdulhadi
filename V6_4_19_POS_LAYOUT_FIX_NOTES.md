# V6.4.19 — POS layout correction

- Corrected POS workspace to use a two-column desktop grid: quick-sale panel on the left and invoice on the right.
- Moved the three quick-sale section tabs into a single horizontal row at the top of the quick-sale panel.
- Added compact, responsive styling for quick items and invoice table without changing POS handlers, Supabase RPC calls, pricing calculations, stock checks, cash/credit sale logic, or schema.
- On narrow screens, the quick-sale panel moves above the invoice to preserve usability.

## Validation status
- CSS and source changes reviewed at file level.
- Full Vite build not confirmed in this environment: dependency installation timed out.
- Must test in local preview before deployment; do not assume production-safe until functional checks pass.
