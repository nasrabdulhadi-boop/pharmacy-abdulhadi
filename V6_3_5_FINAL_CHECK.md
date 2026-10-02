# Pharmacy Abdelhadi V6.3.5 — Final UI/Consistency Patch

## Fixed
- Purchase invoice modal rebuilt as a single contained workspace with RTL-safe columns, internal scrolling, fixed table widths, and no background/sidebar bleed-through.
- Dashboard sales/profit values are sanitized against non-finite values.
- Seven-day sales chart uses exact per-day dashboard RPC totals when available, with a safe fallback to the sales list.
- Seven-day chart remains column-based and each day opens one centered, single-scroll detail dialog.
- Day detail sections are kept inside the viewport and no longer split above/below the screen.
- Existing Supabase schema and RPC names are preserved.

## Verification performed locally
- ZIP source inspected.
- Main JSX changes are limited to numeric safety and dashboard chart data selection.
- CSS braces balanced by source inspection.
- No node_modules or dist included.

## Build limitation
`npm install` was attempted but timed out in this environment, so a full Vite production build could not be completed here. Do not claim a successful production build from this environment.
