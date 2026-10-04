# V6.4.1 — Visual-only layout polish

- Enlarges the purchase invoice workspace to use nearly all available screen width and height.
- Keeps invoice header, line-item table, financial sidebar, fields, buttons, RPC calls, and calculations intact.
- Preserves independent scrolling for the purchase items and payment summary areas.
- Enlarges only the selected-day details drawer in the dashboard. The sales-evolution chart and chart sizing are untouched.
- No SQL or Supabase schema/function changes.

## Validation performed
- Source diff is limited to a new CSS file import, package version, and this changelog.
- CSS braces and media-query balance checked.
- ZIP archive integrity checked after packaging.
- No live Supabase, browser, or production deployment test was available in this environment; do not treat this as a live end-to-end test.
