# v2.1 database bootstrap fix

The previous v2.0 package was missing the base schema migration. `v1_0_production.sql` therefore failed on a fresh Supabase project with `relation public.products does not exist`.

## Correct order on a fresh project
1. `database/00_base_schema.sql`
2. `database/v1_0_production.sql`
3. `database/v1_2_supabase_foundation.sql`
4. `database/v1_3_security_and_pos.sql`
5. `database/v1_4_atomic_pos_fefo.sql`
6. `database/v1_5_admin_rls.sql`
7. `database/v1_6_purchases_returns.sql`
8. `database/v1_7_orders_prescriptions.sql`
9. `database/v1_8_reports.sql`
10. `database/v1_9_security_hardening.sql`

Do not treat this as production certification. The remaining RPC contracts in v1.6-v1.8 still need implementation and end-to-end testing before live use.
