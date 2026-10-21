-- Currency backend readiness contract, to be applied LAST after all reviewed currency RPCs.
-- The frontend must not expose USD purchase/debt screens unless this returns ready=true.
-- This is a read-only SECURITY DEFINER RPC; it never creates an invoice, payment or cash entry.
BEGIN;
CREATE OR REPLACE FUNCTION public.admin_currency_backend_contract_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public','auth'
AS $fn$
DECLARE v_rate numeric; v_writes boolean; v_reads boolean; v_columns boolean;
        v_triggers boolean; v_balances boolean;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT usd_to_syp INTO v_rate FROM public.pharmacy_currency_settings WHERE id=1;
 v_writes :=
  to_regprocedure('public.admin_create_purchase_usd_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric)') IS NOT NULL
  AND to_regprocedure('public.admin_record_supplier_payment_usd_v1(uuid,numeric,uuid,text,text)') IS NOT NULL;
 v_reads :=
  to_regprocedure('public.admin_currency_purchase_list_v1()') IS NOT NULL
  AND to_regprocedure('public.admin_currency_supplier_debt_list_v1()') IS NOT NULL
  AND to_regprocedure('public.admin_currency_supplier_ledger_v1(uuid,text)') IS NOT NULL
  AND to_regprocedure('public.admin_currency_purchase_detail_v1(uuid)') IS NOT NULL
  AND to_regprocedure('public.admin_currency_supplier_return_options_v1()') IS NOT NULL
  AND to_regprocedure('public.admin_currency_supplier_purchase_history_v1(uuid)') IS NOT NULL
  AND to_regprocedure('public.admin_currency_accounting_report_v1(timestamptz,timestamptz,timestamptz,timestamptz)') IS NOT NULL;
 v_columns :=
  (SELECT COUNT(*)=3 FROM information_schema.columns
   WHERE table_schema='public' AND table_name='purchases'
   AND column_name IN ('currency','fx_rate','total_syp'))
  AND (SELECT COUNT(*)=3 FROM information_schema.columns
   WHERE table_schema='public' AND table_name='supplier_payments'
   AND column_name IN ('currency','fx_rate','amount_syp'))
  AND (SELECT COUNT(*)=3 FROM information_schema.columns
   WHERE table_schema='public' AND table_name='supplier_payment_allocations'
   AND column_name IN ('currency','fx_rate','amount_syp'));
 v_triggers := EXISTS (SELECT 1 FROM pg_trigger
   WHERE tgrelid='public.supplier_payment_allocations'::regclass
     AND tgname='trg_ab_allocation_metadata_guard_v1' AND tgenabled IN ('O','A'))
  AND EXISTS (SELECT 1 FROM pg_trigger
   WHERE tgrelid='public.returns'::regclass
     AND tgname='trg_guard_usd_supplier_return_currency_v1' AND tgenabled IN ('O','A'));
 v_balances :=
  NOT EXISTS (SELECT 1 FROM public.purchases p
    WHERE ABS(COALESCE(p.total,0)-COALESCE(p.paid_amount,0)-COALESCE(p.due_amount,0))>0.01)
  AND NOT EXISTS (SELECT 1 FROM public.supplier_payment_allocations a
    JOIN public.supplier_payments sp ON sp.id=a.payment_id
    JOIN public.purchases p ON p.id=a.purchase_id
    WHERE sp.supplier_id IS DISTINCT FROM p.supplier_id OR
      sp.currency IS DISTINCT FROM p.currency OR a.currency IS DISTINCT FROM p.currency)
  AND NOT EXISTS (SELECT 1 FROM public.cashbox_entries
    WHERE currency='SYP' AND amount_syp IS DISTINCT FROM amount)
  AND NOT EXISTS (SELECT 1 FROM public.purchases
    WHERE currency='USD' AND (fx_rate<=1 OR total_syp IS NULL))
  AND NOT EXISTS (SELECT 1 FROM public.supplier_payments
    WHERE currency='USD' AND (fx_rate<=1 OR amount_syp IS NULL));
 RETURN jsonb_build_object('ready', v_writes AND v_reads AND v_columns AND v_triggers AND v_balances AND v_rate>1,
   'writes',v_writes,'reads',v_reads,'columns',v_columns,'guards',v_triggers,'balances',v_balances,
   'rate_valid',COALESCE(v_rate>1,false),
   'usd_supplier_returns_supported',false);
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_backend_contract_v1() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_backend_contract_v1() TO authenticated;
COMMIT;
