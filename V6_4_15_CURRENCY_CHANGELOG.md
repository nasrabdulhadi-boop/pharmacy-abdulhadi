# V6.4.15 — USD/SYP Currency Foundation

Non-destructive dual-currency addition built directly on V6.4.14.

## Safety guarantees
- No table deletion, truncation, reset, or product mass conversion.
- Existing product numeric prices are preserved and classified as SYP.
- Existing historical transactions are preserved as SYP snapshots; no invented historical FX rate is applied.
- USD-linked product sale prices remain stored in USD; current SYP is calculated from the central rate.
- Purchase invoices capture currency and FX snapshot; batch cost remains historical.
- Existing RPCs remain available for backward compatibility.

## Supabase
Run `CURRENCY_V6_4_15_NON_DESTRUCTIVE.sql` once. Do not run reset scripts.

## Important verification limitation
This package was statically checked and zipped from the V6.4.14 source. It has not been run against the user's live Supabase/Vercel environment here, so live production behavior still needs the staged SQL + UI test checklist.
