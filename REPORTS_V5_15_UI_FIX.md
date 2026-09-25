# Pharmacy Abdelhadi v5.15 — Reports UI & date refresh fix

- Fixes the report refresh bug where `PageHead` passed a click event into the report date loader, producing “التاريخ غير صالح”.
- Date validation now accepts only `YYYY-MM-DD`, validates real calendar dates, and uses an exclusive next-day end boundary for accurate full-day reporting.
- Previous-period comparison uses calendar-day counts and is DST-safe.
- Reorganized reports into three tabs: overview, movements, and integrity checks.
- Standardized report typography on Cairo with consistent sizes/weights.
- Added responsive cards, hover states, modal transitions, loading state, and report panel animations.
- No new SQL migration is required for this UI/date fix; the existing `REPORTS_V5_14_FIX.sql` remains the reporting RPC.
