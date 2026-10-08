# V6.4.15 staged test checklist
1. Backup Supabase before migration.
2. Run the migration in Supabase SQL Editor and confirm COMMIT.
3. Check product count before/after; must be identical.
4. Check purchases/suppliers/batches counts before/after; must be identical.
5. Confirm all existing products show SYP and their numeric sale_price is unchanged.
6. Set FX 15000; edit one product to 2 USD; POS should show 30000 SYP.
7. Change FX to 16000; same product should show 32000 SYP without changing stored 2 USD.
8. Confirm a 30000 SYP product remains 30000 SYP after FX change.
9. Save one SYP purchase and one USD purchase; confirm invoice FX snapshot does not change after central rate changes.
10. Test cash sale, credit sale, supplier payment, debtor payment, return, reports, and cashbox reconciliation.
11. If any live test fails, stop and do not run unrelated SQL.
