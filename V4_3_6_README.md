# Pharmacy Abdelhadi v4.3.6

## Fixes
- POS: fixes `column reference "b.id" is ambiguous` by renaming the PL/pgSQL batch record and qualifying the batches table alias.
- Security: the Details button is explicitly rendered as a visible button with a document icon.
- Sale audit details include product name, batch number, and quantity.
- Batch additions/deletions remain recorded in the audit log.

## Install
1. Supabase → SQL Editor → run `V4_3_6_POS_AUDIT_FIX.sql`.
2. Upload the project files to GitHub.
3. Let Vercel redeploy.
4. Hard refresh the browser / open the site in a new tab.
