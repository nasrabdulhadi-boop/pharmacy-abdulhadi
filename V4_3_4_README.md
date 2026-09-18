# Pharmacy Abdelhadi v4.3.4

## Changes
- Fixed the Reports page crash caused by the missing `ReportList` component.
- Reports now show a local error message instead of crashing the whole interface if a data source fails.
- Added **Delete order** button in Orders.
- Added **Delete batch** button in Inventory.
  - A batch linked to previous sales is protected and cannot be deleted.
  - Unused batch stock-movement records are removed with the batch.
- Added a third audit-log column: **تفاصيل العملية**.
- Security log now formats common operation names and displays JSON details.
- Added/refreshened admin report RPCs in the SQL upgrade file.

## Supabase
Run `V4_3_4_REPORTS_DELETE_AUDIT.sql` once in Supabase SQL Editor.

## Deploy
Replace the project files in GitHub with this version, then wait for Vercel to deploy.
