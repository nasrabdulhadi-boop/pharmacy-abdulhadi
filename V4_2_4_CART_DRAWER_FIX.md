# v4.2.4 — Cart Drawer Fix

Replaced the cart modal with a React portal-based fixed cart drawer rendered directly under document.body. This avoids clipping/stacking issues caused by the main site container and guarantees the cart overlay appears above the page. No new SQL is required.
