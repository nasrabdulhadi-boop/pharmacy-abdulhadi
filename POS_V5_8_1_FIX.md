# POS v5.8.1

- Repeated USB barcode scans are supported without requiring a page refresh or waiting between scans.
- After each POS add/remove/scan action, the POS search input is returned to focus.
- Added a keyboard-scanner fallback that captures rapid barcode characters + Enter even if the POS search input temporarily loses focus.
- No duplicate suppression is applied: scanning the same barcode again increases the existing line quantity according to the POS default quantity.
- Search panel is now a distinct interactive panel above the sale invoice, not styled as another invoice table.
- Sale invoice columns and search behavior are preserved.
- Product identity now shows product name together with strength and dosage form, with active ingredient shown as secondary information in both search results and invoice.
- Existing v5.8 SQL search behavior is retained: Arabic/English text matching, ingredient contains-search, and nearest saleable expiry ordering.
