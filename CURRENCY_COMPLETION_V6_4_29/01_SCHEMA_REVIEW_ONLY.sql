-- Pharmacy Abdulhadi | Currency / Phase 5A | SCHEMA-ONLY, NON-DESTRUCTIVE
-- REVIEW / STAGING FIRST. Do NOT apply on production without a full backup and staging test.
-- Purpose: store native purchase/payment/return currencies without converting legacy balances.
-- Historical purchase/payment/return amounts remain numerically unchanged.
-- Existing business RPCs and triggers are NOT replaced or executed by this file.
-- WARNING: Until new currency-aware RPCs are deployed and verified, ONLY use legacy SYP
-- purchasing/supplier-payment paths. No USD invoice or USD supplier payment is enabled here.
-- Existing records are assumed SYP by policy based on your current legacy setup;
-- if this assumption is inaccurate, STOP and classify legacy records before executing.

BEGIN;

-- Check essential prerequisites without changing data.
DO $guard$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(t.table_name, ', ' ORDER BY t.table_name) INTO v_missing
  FROM (VALUES ('purchases'),('purchase_items'),('batches'),('supplier_payments'),
               ('supplier_payment_allocations'),('returns')) AS t(table_name)
  WHERE to_regclass('public.'||t.table_name) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'Missing prerequisite tables: %', v_missing;
  END IF;
  IF (SELECT COUNT(*) FROM public.purchases WHERE supplier_id IS NULL) > 0 THEN
    RAISE EXCEPTION 'Unlinked purchases exist: resolve before migrating';
  END IF;
  IF EXISTS (SELECT 1 FROM public.pharmacy_currency_settings WHERE id=1 AND usd_to_syp IS NULL) THEN
    RAISE EXCEPTION 'Currency configuration has a NULL rate';
  END IF;
END
$guard$;

-- Native invoice amounts (purchases.total, paid_amount, due_amount) stay in invoice currency.
ALTER TABLE public.purchases
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP',
  ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS total_syp numeric;

-- Purchase-item.purchase_price is its ORIGINAL invoice-currency price.
-- For old records price in SYP; new USD rows require price_syp frozen at purchase time.
ALTER TABLE public.purchase_items
  ADD COLUMN IF NOT EXISTS purchase_currency text NOT NULL DEFAULT 'SYP',
  ADD COLUMN IF NOT EXISTS purchase_fx_rate numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS purchase_price_syp numeric,
  ADD COLUMN IF NOT EXISTS sale_price_currency text NOT NULL DEFAULT 'SYP';

-- Sale-price currency is a line-level snapshot; historical lines default to SYP.

-- IMPORTANT: batches.purchase_price remains SYP unit cost for POS/COGS compatibility.
-- For new USD invoices keep original supplier USD unit price in original_purchase_price.
ALTER TABLE public.batches
  ADD COLUMN IF NOT EXISTS purchase_currency text NOT NULL DEFAULT 'SYP',
  ADD COLUMN IF NOT EXISTS purchase_fx_rate numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS original_purchase_price numeric;

-- Supplier payments.amount remains native currency. New USD paths must write both.
ALTER TABLE public.supplier_payments
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP',
  ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS amount_syp numeric;

-- Payment allocations.amount always has same native currency as invoice AND payment.
ALTER TABLE public.supplier_payment_allocations
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP',
  ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS amount_syp numeric;

-- Returns.amount is in the original sale or purchase currency; normalize in amount_syp.
ALTER TABLE public.returns
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP',
  ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS amount_syp numeric;

-- Enforce valid new metadata, without changing existing original amount columns.
DO $check$
DECLARE v_table text; v_currency_col text; v_fx_col text; v_constraint text;
BEGIN
  FOR v_table, v_currency_col, v_fx_col IN
    SELECT x.t, x.c, x.f FROM (VALUES
      ('purchases','currency','fx_rate'),
      ('purchase_items','purchase_currency','purchase_fx_rate'),
      ('batches','purchase_currency','purchase_fx_rate'),
      ('supplier_payments','currency','fx_rate'),
      ('supplier_payment_allocations','currency','fx_rate'),
      ('returns','currency','fx_rate')
    ) x(t,c,f)
  LOOP
    v_constraint := 'chk_ab_currency_'||v_table;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c
                   WHERE c.conrelid=to_regclass('public.'||v_table)
                     AND c.conname=v_constraint) THEN
      EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I CHECK (%I IN (''SYP'',''USD'')) NOT VALID',
                     v_table,v_constraint,v_currency_col);
    END IF;
    v_constraint := 'chk_ab_fx_'||v_table;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint c
                   WHERE c.conrelid=to_regclass('public.'||v_table)
                     AND c.conname=v_constraint) THEN
      EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I CHECK (%I > 0) NOT VALID',
                     v_table,v_constraint,v_fx_col);
    END IF;
  END LOOP;
END
$check$;

-- Never rewrite currency settings, historic balances, purchases, batches, cash movements.
COMMIT;

-- A completed transaction here indicates SCHEMA ONLY is installed, NOT that USD is enabled.
