-- Pharmacy Abdulhadi — schema-only currency/accounting diagnostic
-- SAFE: read-only SELECT queries only. No patient/customer/product rows or business transactions are selected.
-- Run in Supabase SQL Editor. Export the result grids (CSV) and share them for implementation matching.

-- 1. Relevant tables and columns: types, nullability, defaults.
SELECT c.table_name, c.ordinal_position, c.column_name, c.data_type, c.udt_name,
       c.is_nullable, c.column_default, c.numeric_precision, c.numeric_scale
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name IN (
    'products','batches','stock_movements','purchases','purchase_items','suppliers',
    'supplier_payments','supplier_payment_allocations','sales','sale_items',
    'cashbox_entries','debtors','debtor_transactions','returns','audit_logs',
    'pharmacy_currency_settings','currency_history'
  )
ORDER BY c.table_name, c.ordinal_position;

-- 2. Existing relevant RPC signatures, return types and full definitions (no execution).
SELECT n.nspname AS schema_name, p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       pg_get_function_result(p.oid) AS return_type,
       p.prosecdef AS security_definer,
       p.provolatile AS volatility,
       pg_get_functiondef(p.oid) AS function_definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND (p.proname ILIKE '%complete_sale%'
    OR p.proname ILIKE '%create_purchase%'
    OR p.proname ILIKE '%supplier_payment%'
    OR p.proname ILIKE '%cashbox%'
    OR p.proname ILIKE '%accounting_report%'
    OR p.proname ILIKE '%financial_summary%'
    OR p.proname ILIKE '%currency%'
    OR p.proname ILIKE '%exchange%rate%'
    OR p.proname ILIKE '%search_pos_products%'
    OR p.proname ILIKE '%customer_return%')
ORDER BY p.proname, identity_arguments;

-- 3. Constraints and foreign keys on accounting tables.
SELECT tc.table_name, tc.constraint_name, tc.constraint_type,
       cc.check_clause, kcu.column_name,
       ccu.table_name AS referenced_table, ccu.column_name AS referenced_column
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.check_constraints cc
  ON cc.constraint_schema = tc.constraint_schema AND cc.constraint_name = tc.constraint_name
LEFT JOIN information_schema.key_column_usage kcu
  ON kcu.constraint_schema = tc.constraint_schema AND kcu.constraint_name = tc.constraint_name
 AND kcu.table_schema = tc.table_schema AND kcu.table_name = tc.table_name
LEFT JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_schema = tc.constraint_schema AND ccu.constraint_name = tc.constraint_name
 AND ccu.table_schema = tc.table_schema AND ccu.table_name = tc.table_name
WHERE tc.table_schema = 'public'
  AND tc.table_name IN ('products','batches','stock_movements','purchases','purchase_items',
    'supplier_payments','supplier_payment_allocations','sales','sale_items','cashbox_entries',
    'debtors','debtor_transactions','returns','pharmacy_currency_settings','currency_history')
ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name, kcu.ordinal_position;

-- 4. Triggers on those tables (needed to avoid breaking automatic accounting/audit behavior).
SELECT event_object_table AS table_name, trigger_name, event_manipulation,
       action_timing, action_orientation, action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table IN ('products','batches','stock_movements','purchases','purchase_items',
    'supplier_payments','supplier_payment_allocations','sales','sale_items','cashbox_entries',
    'debtors','debtor_transactions','returns','audit_logs')
ORDER BY event_object_table, trigger_name, event_manipulation;

-- 5. RLS and policy definitions for relevant tables.
SELECT n.nspname AS schema_name, c.relname AS table_name,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls,
       pol.polname AS policy_name, pol.polcmd AS command, pol.polroles::regrole[] AS roles,
       pg_get_expr(pol.polqual, pol.polrelid) AS using_expression,
       pg_get_expr(pol.polwithcheck, pol.polrelid) AS with_check_expression
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_policy pol ON pol.polrelid = c.oid
WHERE n.nspname = 'public'
  AND c.relname IN ('products','batches','stock_movements','purchases','purchase_items',
    'supplier_payments','supplier_payment_allocations','sales','sale_items','cashbox_entries',
    'debtors','debtor_transactions','returns','audit_logs','pharmacy_currency_settings')
ORDER BY c.relname, pol.polname;

-- 6. Relevant indexes (definitions only).
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('products','batches','stock_movements','purchases','purchase_items',
    'supplier_payments','supplier_payment_allocations','sales','sale_items','cashbox_entries',
    'debtors','debtor_transactions','returns')
ORDER BY tablename, indexname;

-- End: schema/definitions only. No business rows queried and no database changes performed.
