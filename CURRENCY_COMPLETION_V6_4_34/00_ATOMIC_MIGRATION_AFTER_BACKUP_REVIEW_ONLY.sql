-- PHARMACY ABDELHADI — V6.4.34 consolidated rollout (reviewed by rollback test).
-- Intended for a TRANSACTIONAL migration runner; no ALTER/INSERT/UPDATE on historical row values.
-- Stop if an earlier migration has already been partly applied, or live data no longer matches precheck.
SET LOCAL lock_timeout='4s';
SET LOCAL statement_timeout='120s';

-- PHASE 01_SCHEMA_REVIEW_ONLY.sql
-- Pharmacy Abdulhadi | Currency / Phase 5A | SCHEMA-ONLY, NON-DESTRUCTIVE
-- REVIEW / STAGING FIRST. Do NOT apply on production without a full backup and staging test.
-- Purpose: store native purchase/payment/return currencies without converting legacy balances.
-- Historical purchase/payment/return amounts remain numerically unchanged.
-- Existing business RPCs and triggers are NOT replaced or executed by this file.
-- WARNING: Until new currency-aware RPCs are deployed and verified, ONLY use legacy SYP
-- purchasing/supplier-payment paths. No USD invoice or USD supplier payment is enabled here.
-- Existing records are assumed SYP by policy based on your current legacy setup;
-- if this assumption is inaccurate, STOP and classify legacy records before executing.


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
  ADD COLUMN IF NOT EXISTS total_syp numeric,
  ADD COLUMN IF NOT EXISTS credit_amount numeric NOT NULL DEFAULT 0;

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

-- Supplier refunds are separate from original invoice payment allocations.
-- Historical data is never reclassified, backfilled or reduced.
CREATE TABLE IF NOT EXISTS public.supplier_refund_receipts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 supplier_id uuid NOT NULL REFERENCES public.suppliers(id),
 purchase_id uuid NOT NULL REFERENCES public.purchases(id),
 currency text NOT NULL CHECK (currency IN ('SYP','USD')),
 amount numeric NOT NULL CHECK (amount>0),
 fx_rate numeric NOT NULL CHECK (fx_rate>0),
 amount_syp numeric NOT NULL CHECK (amount_syp>0),
 payment_method text NOT NULL CHECK (payment_method IN ('cash','other')),
 cashbox_entry_id uuid REFERENCES public.cashbox_entries(id),
 notes text,
 created_by uuid,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_supplier_refunds_purchase ON public.supplier_refund_receipts(purchase_id);
ALTER TABLE public.supplier_refund_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.supplier_refund_receipts FROM PUBLIC,anon,authenticated;
DO $credit$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.purchases'::regclass AND conname='chk_ab_purchase_credits_valid') THEN
  ALTER TABLE public.purchases ADD CONSTRAINT chk_ab_purchase_credits_valid
    CHECK(credit_amount>=0 AND credit_amount<=total+0.05) NOT VALID;
 END IF;
END
$credit$;

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

-- A completed transaction here indicates SCHEMA ONLY is installed, NOT that USD is enabled.


-- PHASE 02_GUARD_SUPPLIER_ALLOCATIONS_STAGING_ONLY.sql
-- Review and run on staging ONLY after 01_SCHEMA_REVIEW_ONLY.sql.
-- Replaces only the known existing trigger function. Historic rows untouched.
-- Enforces payment supplier, payment/invoice currency agreement and both amount limits.

CREATE OR REPLACE FUNCTION public.validate_supplier_payment_allocation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v_supplier uuid; v_purchase_supplier uuid; v_invoice_currency text;
        v_payment_currency text; v_invoice_total numeric; v_payment_total numeric;
        v_already_invoice numeric; v_already_payment numeric; v_payment_fx numeric;
BEGIN
  SELECT supplier_id, currency, amount, fx_rate INTO v_supplier,v_payment_currency,v_payment_total,v_payment_fx
    FROM public.supplier_payments WHERE id=NEW.payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'دفعة المورد غير موجودة'; END IF;
  SELECT supplier_id,currency,GREATEST(total-COALESCE(credit_amount,0),0) INTO v_purchase_supplier,v_invoice_currency,v_invoice_total
    FROM public.purchases WHERE id=NEW.purchase_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة الشراء غير موجودة'; END IF;
  IF v_supplier IS DISTINCT FROM v_purchase_supplier THEN
    RAISE EXCEPTION 'لا يمكن تخصيص دفعة لمورد مختلف'; END IF;
  IF v_payment_currency IS DISTINCT FROM v_invoice_currency THEN
    RAISE EXCEPTION 'لا يمكن تخصيص دفعة بعملة مختلفة عن عملة الفاتورة'; END IF;
  IF NEW.currency IS DISTINCT FROM v_invoice_currency THEN
    RAISE EXCEPTION 'عملة التوزيع لا تطابق عملة الفاتورة'; END IF;
  IF NEW.amount IS NULL OR NEW.amount<=0 THEN RAISE EXCEPTION 'مبلغ التوزيع غير صالح'; END IF;
  IF NEW.fx_rate IS DISTINCT FROM v_payment_fx THEN
    RAISE EXCEPTION 'سعر صرف التخصيص لا يطابق سعر صرف الدفعة'; END IF;
  IF v_payment_currency='USD' AND
     (NEW.amount_syp IS NULL OR NEW.amount_syp IS DISTINCT FROM ROUND(NEW.amount*v_payment_fx,2)) THEN
    RAISE EXCEPTION 'قيمة تحويل تخصيص الدولار إلى الليرة غير صحيحة'; END IF;
  IF v_payment_currency='SYP' AND NEW.amount_syp IS NOT NULL AND
     NEW.amount_syp IS DISTINCT FROM NEW.amount THEN
    RAISE EXCEPTION 'تخصيص الليرة يحتوي مقابلاً غير مطابق بالليرة'; END IF;

  SELECT COALESCE(SUM(amount),0) INTO v_already_invoice
    FROM public.supplier_payment_allocations
    WHERE purchase_id=NEW.purchase_id AND id IS DISTINCT FROM NEW.id;
  SELECT COALESCE(SUM(amount),0) INTO v_already_payment
    FROM public.supplier_payment_allocations
    WHERE payment_id=NEW.payment_id AND id IS DISTINCT FROM NEW.id;
  IF v_already_invoice+NEW.amount>v_invoice_total+0.0000001 THEN
    RAISE EXCEPTION 'التوزيع يتجاوز قيمة الفاتورة'; END IF;
  IF v_already_payment+NEW.amount>v_payment_total+0.0000001 THEN
    RAISE EXCEPTION 'التوزيع يتجاوز قيمة الدفعة'; END IF;
  RETURN NEW;
END;
$fn$;
-- The historic allocation trigger fires on INSERT and UPDATE of amount, payment and
-- purchase IDs. Cover direct changes to metadata without dropping the old trigger.
DO $guard$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.supplier_payment_allocations'::regclass
   AND tgname='trg_ab_allocation_metadata_guard_v1' AND NOT tgisinternal) THEN
   CREATE TRIGGER trg_ab_allocation_metadata_guard_v1
    BEFORE UPDATE OF currency, fx_rate, amount_syp ON public.supplier_payment_allocations
    FOR EACH ROW EXECUTE FUNCTION public.validate_supplier_payment_allocation();
 END IF;
END;
$guard$;


-- PHASE 13_SYP_SUPPLIER_PAYMENT_GUARD_STAGING_ONLY.sql
-- Pharmacy Abdulhadi | currency staging: protect the legacy SYP supplier-payment RPC.
-- REVIEW/STAGING ONLY. Apply AFTER 01_SCHEMA_REVIEW_ONLY.sql and
-- 02_GUARD_SUPPLIER_ALLOCATIONS_STAGING_ONLY.sql; not on production without tests.
-- Keep public RPC name/signature/response keys so old SYP UI keeps working.
-- Make USD invoices invisible to this SYP-only payment path. Do not change historic rows.

CREATE OR REPLACE FUNCTION public.admin_record_supplier_payment(
  p_supplier_id uuid, p_amount numeric, p_purchase_id uuid DEFAULT NULL,
  p_payment_method text DEFAULT 'cash', p_notes text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE
  v_payment_id uuid := gen_random_uuid();
  v_cash_id uuid;
  v_remaining numeric := p_amount;
  v_invoice_due numeric;
  v_alloc numeric;
  v_previous_debt numeric;
  v_new_debt numeric;
  v_supplier_name text;
  r record;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'مبلغ دفعة المورد يجب أن يكون موجباً'; END IF;
  IF p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الدفع غير صالحة'; END IF;
  SELECT name INTO v_supplier_name FROM public.suppliers WHERE id=p_supplier_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
  SELECT COALESCE(SUM(GREATEST(due_amount,0)),0)
    INTO v_previous_debt FROM public.purchases
    WHERE supplier_id=p_supplier_id AND currency='SYP';
  IF p_amount>v_previous_debt+0.0000001 THEN
    RAISE EXCEPTION 'الدفعة بالليرة تتجاوز رصيد المورد المستحق بالليرة';
  END IF;
  IF p_purchase_id IS NOT NULL THEN
    SELECT GREATEST(due_amount,0) INTO v_invoice_due
      FROM public.purchases WHERE id=p_purchase_id AND supplier_id=p_supplier_id
      AND currency='SYP' FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'الفاتورة غير موجودة لهذا المورد أو عملتها ليست الليرة السورية';
    END IF;
    IF v_invoice_due<=0 THEN RAISE EXCEPTION 'هذه الفاتورة مسددة بالكامل'; END IF;
    IF p_amount>v_invoice_due+0.0000001 THEN
      RAISE EXCEPTION 'الدفعة أكبر من المتبقي بالليرة: %',v_invoice_due;
    END IF;
  END IF;
  INSERT INTO public.supplier_payments
   (id,supplier_id,amount,payment_method,notes,created_by,currency,fx_rate,amount_syp)
   VALUES (v_payment_id,p_supplier_id,p_amount,p_payment_method,
     NULLIF(trim(COALESCE(p_notes,'')),''),auth.uid(),'SYP',1,p_amount);
  IF p_purchase_id IS NOT NULL THEN
    INSERT INTO public.supplier_payment_allocations
      (payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
    VALUES (v_payment_id,p_purchase_id,p_amount,'SYP',1,p_amount);
    v_remaining:=0;
  ELSE
    FOR r IN SELECT id,GREATEST(due_amount,0) AS due
     FROM public.purchases
     WHERE supplier_id=p_supplier_id AND currency='SYP'
       AND GREATEST(due_amount,0)>0
     ORDER BY COALESCE(invoice_date,created_at::date),created_at,id FOR UPDATE
    LOOP
      EXIT WHEN v_remaining<=0;
      v_alloc:=LEAST(v_remaining,r.due);
      INSERT INTO public.supplier_payment_allocations
        (payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
      VALUES (v_payment_id,r.id,v_alloc,'SYP',1,v_alloc);
      v_remaining:=v_remaining-v_alloc;
    END LOOP;
    IF v_remaining>0.0000001 THEN
      RAISE EXCEPTION 'الدفعة تتجاوز الرصيد المتاح بالليرة';
    END IF;
  END IF;
  FOR r IN SELECT DISTINCT purchase_id FROM public.supplier_payment_allocations
           WHERE payment_id=v_payment_id LOOP
    PERFORM public.admin_refresh_purchase_balance(r.purchase_id);
  END LOOP;
  IF p_payment_method='cash' THEN
    INSERT INTO public.cashbox_entries
      (entry_type,amount,description,purchase_id,supplier_payment_id,created_by,
       currency,fx_rate,amount_syp)
    VALUES ('purchase_payment',-p_amount,
      'دفع للمورد بالليرة: '||v_supplier_name||
       CASE WHEN p_purchase_id IS NULL THEN ' — توزيع على الفواتير المفتوحة'
         ELSE ' — فاتورة '||COALESCE((SELECT invoice_number FROM public.purchases
           WHERE id=p_purchase_id),'—') END,
      p_purchase_id,v_payment_id,auth.uid(),'SYP',1,-p_amount)
    RETURNING id INTO v_cash_id;
    UPDATE public.supplier_payments SET cashbox_entry_id=v_cash_id WHERE id=v_payment_id;
  END IF;
  SELECT COALESCE(SUM(GREATEST(due_amount,0)),0)
    INTO v_new_debt FROM public.purchases
    WHERE supplier_id=p_supplier_id AND currency='SYP';
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'supplier_payment','supplier',p_supplier_id,
    jsonb_build_object('supplier_name',v_supplier_name,'amount',p_amount,
      'currency','SYP','payment_method',p_payment_method,'purchase_id',p_purchase_id,
      'previous_debt',v_previous_debt,'new_debt',v_new_debt,
      'cashbox_entry_id',v_cash_id,'notes',p_notes));
  RETURN jsonb_build_object('payment_id',v_payment_id,'amount',p_amount,
    'currency','SYP','previous_debt',v_previous_debt,'new_debt',v_new_debt,
    'cashbox_entry_id',v_cash_id);
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_record_supplier_payment(uuid,numeric,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_record_supplier_payment(uuid,numeric,uuid,text,text) TO authenticated;


-- PHASE 03_USD_SUPPLIER_PAYMENTS_STAGING_ONLY.sql
-- Staging only. USD-only supplier settlement; existing SYP legacy function kept intact.
-- Invoice/payment balances are in USD; cashbox keeps USD native and amount_syp snapshot.

CREATE OR REPLACE FUNCTION public.admin_record_supplier_payment_usd_v1(
 p_supplier_id uuid, p_amount numeric, p_purchase_id uuid DEFAULT NULL,
 p_payment_method text DEFAULT 'cash', p_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v_rate numeric; v_name text; v_id uuid:=gen_random_uuid(); v_cash_id uuid;
        v_left numeric:=p_amount; v_part numeric; v_debt numeric;
        v_before numeric; v_after numeric; r record;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'مبلغ الدفعة بالدولار يجب أن يكون موجباً'; END IF;
 IF p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الدفع غير صالحة'; END IF;
 SELECT name INTO v_name FROM public.suppliers WHERE id=p_supplier_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 SELECT usd_to_syp INTO v_rate FROM public.pharmacy_currency_settings WHERE id=1 FOR SHARE;
 IF v_rate IS NULL OR v_rate<=1 THEN RAISE EXCEPTION 'حدد سعر صرف معتمد قبل دفع الدولار'; END IF;
 SELECT COALESCE(SUM(GREATEST(due_amount,0)),0) INTO v_before
   FROM public.purchases WHERE supplier_id=p_supplier_id AND currency='USD';
 IF p_amount>v_before+0.0000001 THEN RAISE EXCEPTION 'الدفعة تتجاوز رصيد الدولار المستحق على المورد'; END IF;
 IF p_purchase_id IS NOT NULL THEN
   SELECT COALESCE(due_amount,0) INTO v_debt FROM public.purchases
    WHERE id=p_purchase_id AND supplier_id=p_supplier_id AND currency='USD' FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة الدولار المحددة غير موجودة عند هذا المورد'; END IF;
   IF p_amount>v_debt+0.0000001 THEN RAISE EXCEPTION 'الدفعة أكبر من المتبقي بالدولار'; END IF;
 END IF;
 INSERT INTO public.supplier_payments(id,supplier_id,amount,payment_method,notes,created_by,currency,fx_rate,amount_syp)
 VALUES(v_id,p_supplier_id,p_amount,p_payment_method,NULLIF(trim(COALESCE(p_notes,'')),''),auth.uid(),'USD',v_rate,ROUND(p_amount*v_rate,2));
 IF p_purchase_id IS NOT NULL THEN
   INSERT INTO public.supplier_payment_allocations(payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
   VALUES(v_id,p_purchase_id,p_amount,'USD',v_rate,ROUND(p_amount*v_rate,2));
 ELSE
   FOR r IN SELECT id,GREATEST(due_amount,0) AS due FROM public.purchases
    WHERE supplier_id=p_supplier_id AND currency='USD' AND GREATEST(due_amount,0)>0
    ORDER BY COALESCE(invoice_date,created_at::date),created_at,id FOR UPDATE
   LOOP
    EXIT WHEN v_left<=0;
    v_part:=LEAST(v_left,r.due);
    INSERT INTO public.supplier_payment_allocations(payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
    VALUES(v_id,r.id,v_part,'USD',v_rate,ROUND(v_part*v_rate,2));
    v_left:=v_left-v_part;
   END LOOP;
   IF v_left>0.0000001 THEN RAISE EXCEPTION 'لا توجد فواتير دولار تكفي لتوزيع الدفعة'; END IF;
 END IF;
 FOR r IN SELECT DISTINCT purchase_id FROM public.supplier_payment_allocations WHERE payment_id=v_id LOOP
   PERFORM public.admin_refresh_purchase_balance(r.purchase_id);
 END LOOP;
 IF p_payment_method='cash' THEN
  INSERT INTO public.cashbox_entries(entry_type,amount,description,purchase_id,supplier_payment_id,created_by,currency,fx_rate,amount_syp)
  VALUES('purchase_payment',-p_amount,'دفع للمورد بالدولار: '||v_name,p_purchase_id,v_id,auth.uid(),'USD',v_rate,-ROUND(p_amount*v_rate,2))
  RETURNING id INTO v_cash_id;
  UPDATE public.supplier_payments SET cashbox_entry_id=v_cash_id WHERE id=v_id;
 END IF;
 SELECT COALESCE(SUM(GREATEST(due_amount,0)),0) INTO v_after
 FROM public.purchases WHERE supplier_id=p_supplier_id AND currency='USD';
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'supplier_payment_usd','supplier',p_supplier_id,
 jsonb_build_object('payment_id',v_id,'amount_usd',p_amount,'amount_syp',ROUND(p_amount*v_rate,2),
 'fx_rate',v_rate,'before_usd',v_before,'after_usd',v_after,'purchase_id',p_purchase_id));
 RETURN jsonb_build_object('payment_id',v_id,'currency','USD','amount',p_amount,'fx_rate',v_rate,
 'amount_syp',ROUND(p_amount*v_rate,2),'previous_debt_usd',v_before,'new_debt_usd',v_after,'cashbox_entry_id',v_cash_id);
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_record_supplier_payment_usd_v1(uuid,numeric,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_record_supplier_payment_usd_v1(uuid,numeric,uuid,text,text) TO authenticated;


-- PHASE 04_USD_PURCHASES_STAGING_ONLY.sql
-- Stage 6: USD supplier invoice. Staging only; must run after schema + allocation guard + USD payments.
-- Does NOT invoke the legacy purchase function (which treats purchase cost as SYP).
-- Original invoice values and supplier debts stay USD; batch.purchase_price stays SYP.
CREATE OR REPLACE FUNCTION public.admin_create_purchase_usd_v1(
 p_supplier_id uuid, p_new_supplier jsonb, p_invoice_number text, p_invoice_date date,
 p_notes text, p_items jsonb, p_payment_amount numeric, p_payment_method text,
 p_payment_notes text, p_discount_type text, p_discount_value numeric
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE
 v_supplier uuid:=p_supplier_id; v_supplier_name text; v_id uuid:=gen_random_uuid();
 v_invoice text; v_fx numeric; v_sum numeric:=0; v_discount numeric:=0; v_total numeric:=0;
 v_factor numeric; v_due numeric; v_paid numeric:=COALESCE(p_payment_amount,0);
 v_discount_type text:=COALESCE(NULLIF(p_discount_type,''),'none');
 v_discount_value numeric:=COALESCE(p_discount_value,0);
 v_json jsonb; v_product uuid; v_qty numeric; v_bonus numeric; v_net_usd numeric;
 v_sale_price numeric; v_sale_currency text; v_cost_syp numeric;
 v_expiry date; v_line uuid; v_batch uuid; v_batch_bonus uuid;
 v_payment jsonb:=NULL; v_count int:=0; v_p record; v_seen uuid[]:=ARRAY[]::uuid[];
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT usd_to_syp INTO v_fx FROM public.pharmacy_currency_settings WHERE id=1 FOR SHARE;
 IF v_fx IS NULL OR v_fx<=1 THEN RAISE EXCEPTION 'سعر صرف الدولار غير مضبوط، لا يمكن إنشاء فاتورة'; END IF;
 IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items)=0 THEN
  RAISE EXCEPTION 'فاتورة الشراء تحتاج صنفاً واحداً على الأقل'; END IF;
 IF v_discount_type NOT IN ('none','percent','amount') OR v_discount_value<0 OR
  (v_discount_type='percent' AND v_discount_value>100) THEN RAISE EXCEPTION 'خصم الفاتورة غير صالح'; END IF;
 IF v_paid<0 OR v_paid<>ROUND(v_paid,2) OR p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الدفع أو المبلغ غير صالح'; END IF;
 IF v_supplier IS NULL THEN
   IF jsonb_typeof(p_new_supplier) IS DISTINCT FROM 'object' OR
      NULLIF(trim(p_new_supplier->>'name'),'') IS NULL THEN RAISE EXCEPTION 'اسم المورد مطلوب'; END IF;
   IF EXISTS (SELECT 1 FROM public.suppliers WHERE lower(trim(name))=lower(trim(p_new_supplier->>'name'))) THEN
     RAISE EXCEPTION 'اسم المورد موجود مسبقاً، اختر المورد الحالي'; END IF;
   INSERT INTO public.suppliers(name,phone,address,notes)
   VALUES(trim(p_new_supplier->>'name'),NULLIF(trim(p_new_supplier->>'phone'),''),
    NULLIF(trim(p_new_supplier->>'address'),''),NULLIF(trim(p_new_supplier->>'notes'),''))
   RETURNING id,name INTO v_supplier,v_supplier_name;
 ELSE
   SELECT name INTO v_supplier_name FROM public.suppliers WHERE id=v_supplier;
   IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 END IF;
 -- First pass calculates USD subtotal, validates all products, amounts and expiry.
 FOR v_json IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   v_product:=NULLIF(v_json->>'product_id','')::uuid;
   v_qty:=NULLIF(v_json->>'quantity','')::numeric;
   v_bonus:=COALESCE(NULLIF(v_json->>'bonus_quantity','')::numeric,0);
   v_net_usd:=NULLIF(v_json->>'purchase_price','')::numeric;
   v_sale_price:=NULLIF(v_json->>'sale_price','')::numeric;
   v_expiry:=NULLIF(v_json->>'expiry_date','')::date;
   IF v_product IS NULL OR v_qty IS NULL OR v_qty<=0 OR v_bonus<0 OR v_net_usd IS NULL
      OR v_net_usd<=0 OR v_sale_price IS NULL OR v_sale_price<=0 OR v_expiry IS NULL THEN
     RAISE EXCEPTION 'بيانات صنف الشراء غير مكتملة أو غير صالحة'; END IF;
   IF v_product=ANY(v_seen) THEN RAISE EXCEPTION 'لا يمكن تكرار الدواء في نفس فاتورة المورد'; END IF;
   v_seen:=array_append(v_seen,v_product);
   IF v_expiry<CURRENT_DATE THEN RAISE EXCEPTION 'لا يمكن شراء دفعة منتهية الصلاحية'; END IF;
   SELECT sale_currency INTO v_sale_currency FROM public.products WHERE id=v_product AND COALESCE(active,true);
   IF NOT FOUND THEN RAISE EXCEPTION 'الدواء المحدد غير موجود أو غير فعّال'; END IF;
   v_sale_currency:=upper(COALESCE(NULLIF(v_json->>'sale_currency',''),v_sale_currency,'SYP'));
   IF v_sale_currency NOT IN ('SYP','USD') THEN RAISE EXCEPTION 'عملة سعر مبيع الصنف غير صالحة'; END IF;
   v_sum:=v_sum+v_qty*v_net_usd; v_count:=v_count+1;
 END LOOP;
 v_sum:=ROUND(v_sum,2);
 IF v_discount_type='percent' THEN v_discount:=ROUND(v_sum*v_discount_value/100,2);
 ELSIF v_discount_type='amount' THEN v_discount:=ROUND(v_discount_value,2); END IF;
 IF v_discount>v_sum THEN RAISE EXCEPTION 'الخصم يتجاوز إجمالي الفاتورة'; END IF;
 v_total:=ROUND(v_sum-v_discount,2); v_due:=v_total-v_paid;
 IF v_paid>v_total THEN RAISE EXCEPTION 'المدفوع أكبر من قيمة الفاتورة بالدولار'; END IF;
 v_factor:=CASE WHEN v_sum>0 THEN v_total/v_sum ELSE 1 END;
 v_invoice:=NULLIF(trim(COALESCE(p_invoice_number,'')),'');
 IF v_invoice IS NULL THEN v_invoice:='USD-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'); END IF;
 INSERT INTO public.purchases(id,supplier_id,invoice_number,invoice_date,notes,status,
   currency,fx_rate,subtotal,discount_type,discount_value,discount_amount,total,total_syp)
 VALUES(v_id,v_supplier,v_invoice,COALESCE(p_invoice_date,CURRENT_DATE),NULLIF(trim(COALESCE(p_notes,'')),''),
  'received','USD',v_fx,v_sum,v_discount_type,v_discount_value,v_discount,v_total,ROUND(v_total*v_fx,2));
 FOR v_json IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   v_product:=(v_json->>'product_id')::uuid;
   v_qty:=(v_json->>'quantity')::numeric;
   v_bonus:=COALESCE(NULLIF(v_json->>'bonus_quantity','')::numeric,0);
   v_net_usd:=(v_json->>'purchase_price')::numeric;
   v_sale_price:=(v_json->>'sale_price')::numeric;
   v_expiry:=(v_json->>'expiry_date')::date;
   SELECT sale_currency INTO v_sale_currency FROM public.products WHERE id=v_product FOR UPDATE;
   v_sale_currency:=upper(COALESCE(NULLIF(v_json->>'sale_currency',''),v_sale_currency,'SYP'));
   -- Net paid inventory cost per item: after invoice discount, in SYP, rate frozen.
   v_cost_syp:=ROUND(v_net_usd*v_fx*v_factor,6);
   INSERT INTO public.purchase_items(purchase_id,product_id,quantity,bonus_quantity,purchase_price,
      expiry_date,sale_price,sale_price_currency,purchase_currency,purchase_fx_rate,purchase_price_syp)
   VALUES(v_id,v_product,v_qty,v_bonus,v_net_usd,v_expiry,v_sale_price,v_sale_currency,'USD',v_fx,v_cost_syp)
   RETURNING id INTO v_line;
   v_batch:=gen_random_uuid();
   INSERT INTO public.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,
     received_date,supplier_id,purchase_id,purchase_item_id,purchase_currency,purchase_fx_rate,original_purchase_price)
   VALUES(v_batch,v_product,'USD-'||substr(replace(v_line::text,'-',''),1,12),v_expiry,v_qty,v_cost_syp,
     COALESCE(p_invoice_date,CURRENT_DATE),v_supplier,v_id,v_line,'USD',v_fx,v_net_usd);
   UPDATE public.purchase_items SET batch_id=v_batch WHERE id=v_line;
   INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
   VALUES(v_product,v_batch,'purchase',v_qty,'فاتورة دولار '||v_invoice,auth.uid());
   IF v_bonus>0 THEN
     v_batch_bonus:=gen_random_uuid();
     INSERT INTO public.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,
       received_date,supplier_id,purchase_id,purchase_item_id,purchase_currency,purchase_fx_rate,original_purchase_price)
     VALUES(v_batch_bonus,v_product,'USD-'||substr(replace(v_line::text,'-',''),1,12)||'-BONUS',v_expiry,v_bonus,0,
       COALESCE(p_invoice_date,CURRENT_DATE),v_supplier,v_id,v_line,'USD',v_fx,0);
     INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
     VALUES(v_product,v_batch_bonus,'purchase_bonus',v_bonus,'بونص فاتورة دولار '||v_invoice,auth.uid());
   END IF;
   -- Existing sale prices change only when the invoice explicitly specifies sale_price.
   UPDATE public.products SET purchase_price=v_cost_syp,sale_price=v_sale_price,
      sale_currency=v_sale_currency,updated_at=now() WHERE id=v_product;
 END LOOP;
 IF v_paid>0 THEN
   v_payment:=public.admin_record_supplier_payment_usd_v1(v_supplier,v_paid,v_id,p_payment_method,p_payment_notes);
 ELSE
   PERFORM public.admin_refresh_purchase_balance(v_id);
 END IF;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'create_purchase_usd','purchase',v_id,
 jsonb_build_object('invoice_number',v_invoice,'supplier_id',v_supplier,'subtotal_usd',v_sum,
 'discount_usd',v_discount,'total_usd',v_total,'paid_usd',v_paid,'fx_rate',v_fx,'total_syp',ROUND(v_total*v_fx,2)));
 RETURN jsonb_build_object('id',v_id,'public_code',v_invoice,'supplier_id',v_supplier,
  'supplier_name',v_supplier_name,'currency','USD','fx_rate',v_fx,'total',v_total,
  'total_syp',ROUND(v_total*v_fx,2),'paid_amount',v_paid,'due_amount',v_due,
  'discount_amount',v_discount,'payment',v_payment);
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_create_purchase_usd_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_purchase_usd_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric) TO authenticated;


-- PHASE 05_CURRENCY_SAFE_READ_APIS_STAGING_ONLY.sql
-- USD + legacy SYP data exposed without ever mixing numeric currencies.
-- Staging only, run after scripts 01-04. No modification of stored amounts.

CREATE OR REPLACE FUNCTION public.admin_currency_purchase_list_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
  'id',x.id,'supplier_id',x.supplier_id,'supplier_name',x.supplier_name,
  'invoice_number',x.invoice_number,'invoice_date',x.invoice_date,
  'created_at',x.created_at,'status',x.status,'notes',x.notes,
  'total',x.total,'subtotal',x.subtotal,'discount_type',x.discount_type,
  'discount_value',x.discount_value,'discount_amount',x.discount_amount,
  'paid_amount',x.paid_amount,'due_amount',x.due_amount,'payment_status',x.payment_status,
  'item_count',x.item_count,'bonus_quantity',x.bonus_quantity,
  'currency',x.currency,'fx_rate',x.fx_rate,'total_syp',x.total_syp
 ) ORDER BY x.created_at DESC), '[]'::jsonb)
 FROM (
 SELECT p.id,p.supplier_id,s.name supplier_name,p.invoice_number,p.invoice_date,p.created_at,
 p.status,p.notes,p.total,p.subtotal,p.discount_type,p.discount_value,p.discount_amount,
 p.paid_amount,p.due_amount,p.payment_status,p.currency,p.fx_rate,
 CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END total_syp,
 COUNT(pi.id)::bigint item_count,COALESCE(SUM(pi.bonus_quantity),0) bonus_quantity
 FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id
 LEFT JOIN public.purchase_items pi ON pi.purchase_id=p.id
 WHERE public.is_admin() GROUP BY p.id,s.name
 ) x;
$fn$;
CREATE OR REPLACE FUNCTION public.admin_currency_supplier_debt_list_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
  'id',x.id,'name',x.name,'phone',x.phone,'address',x.address,
  'currency',x.currency,'invoice_total',x.invoice_total,'paid_total',x.paid_total,
  'balance',x.balance,'invoice_count',x.invoice_count,'payment_count',x.payment_count,
  'last_payment',x.last_payment,'last_invoice',x.last_invoice
 ) ORDER BY x.balance DESC,x.name,x.currency),'[]'::jsonb)
 FROM (
 SELECT s.id,s.name,s.phone,s.address,p.currency,
 SUM(p.total) invoice_total,SUM(p.paid_amount) paid_total,
 SUM(GREATEST(p.total-p.paid_amount,0)) balance,COUNT(*) invoice_count,
 (SELECT COUNT(*) FROM public.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=p.currency) payment_count,
 (SELECT MAX(sp.created_at) FROM public.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=p.currency) last_payment,
 MAX(p.created_at) last_invoice
 FROM public.suppliers s JOIN public.purchases p ON p.supplier_id=s.id
 WHERE public.is_admin() GROUP BY s.id,p.currency
 ) x;
$fn$;
CREATE OR REPLACE FUNCTION public.admin_currency_supplier_ledger_v1(p_supplier_id uuid,p_currency text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v jsonb; v_currency text:=upper(COALESCE(p_currency,''));
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF v_currency NOT IN ('USD','SYP') THEN RAISE EXCEPTION 'عملة المورد غير صالحة'; END IF;
 SELECT jsonb_build_object(
 'supplier',to_jsonb(s)||jsonb_build_object('currency',v_currency),
 'summary',jsonb_build_object(
 'invoice_total',COALESCE((SELECT SUM(total) FROM public.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
 'paid_total',COALESCE((SELECT SUM(paid_amount) FROM public.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
 'balance',COALESCE((SELECT SUM(GREATEST(total-paid_amount,0)) FROM public.purchases WHERE supplier_id=s.id AND currency=v_currency),0)),
 'invoices',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'invoice_number',p.invoice_number,
 'invoice_date',p.invoice_date,'created_at',p.created_at,'total',p.total,'paid_amount',p.paid_amount,
 'due_amount',p.due_amount,'payment_status',p.payment_status,'currency',p.currency,'fx_rate',p.fx_rate,
 'total_syp',CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END,
 'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',pr.name,'barcode',pr.barcode,
 'quantity',pi.quantity,'purchase_price',pi.purchase_price,'purchase_price_syp',pi.purchase_price_syp,
 'sale_price',pi.sale_price,'sale_currency',pi.sale_price_currency,'expiry_date',pi.expiry_date,'batch_id',pi.batch_id))
 FROM public.purchase_items pi JOIN public.products pr ON pr.id=pi.product_id WHERE pi.purchase_id=p.id),'[]'::jsonb))
 ORDER BY p.created_at DESC) FROM public.purchases p WHERE p.supplier_id=s.id AND p.currency=v_currency),'[]'::jsonb),
 'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',sp.id,'amount',sp.amount,
 'currency',sp.currency,'fx_rate',sp.fx_rate,'amount_syp',sp.amount_syp,'payment_method',sp.payment_method,
 'notes',sp.notes,'created_at',sp.created_at,
 'allocations',COALESCE((SELECT jsonb_agg(jsonb_build_object('purchase_id',spa.purchase_id,
 'amount',spa.amount,'invoice_number',p2.invoice_number))
 FROM public.supplier_payment_allocations spa JOIN public.purchases p2 ON p2.id=spa.purchase_id
 WHERE spa.payment_id=sp.id),'[]'::jsonb)) ORDER BY sp.created_at DESC)
 FROM public.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=v_currency),'[]'::jsonb))
 INTO v FROM public.suppliers s WHERE s.id=p_supplier_id;
 IF v IS NULL THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 RETURN v;
END;
$fn$;
CREATE OR REPLACE FUNCTION public.admin_currency_purchase_detail_v1(p_purchase_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object('id',p.id,'supplier_id',p.supplier_id,'supplier_name',s.name,
 'invoice_number',p.invoice_number,'invoice_date',p.invoice_date,'subtotal',p.subtotal,
 'discount_type',p.discount_type,'discount_value',p.discount_value,'discount_amount',p.discount_amount,
 'total',p.total,'paid_amount',p.paid_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,
 'status',p.status,'notes',p.notes,'created_at',p.created_at,'currency',p.currency,'fx_rate',p.fx_rate,
 'total_syp',CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END,
 'bonus_quantity',COALESCE((SELECT SUM(bonus_quantity) FROM public.purchase_items WHERE purchase_id=p.id),0),
 'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pi.id,'product_id',pi.product_id,
 'product_name',pr.name,'barcode',pr.barcode,'active_ingredient',pr.active_ingredient,
 'quantity',pi.quantity,'bonus_quantity',pi.bonus_quantity,'purchase_price',pi.purchase_price,
 'purchase_price_syp',pi.purchase_price_syp,'sale_price',pi.sale_price,'sale_currency',pi.sale_price_currency,'expiry_date',pi.expiry_date,
 'batch_id',pi.batch_id)) FROM public.purchase_items pi JOIN public.products pr ON pr.id=pi.product_id
 WHERE pi.purchase_id=p.id),'[]'::jsonb),
 'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',sp.id,'amount',spa.amount,
 'currency',sp.currency,'fx_rate',sp.fx_rate,'payment_method',sp.payment_method,
 'notes',sp.notes,'created_at',sp.created_at,'cashbox_entry_id',sp.cashbox_entry_id))
 FROM public.supplier_payment_allocations spa JOIN public.supplier_payments sp ON sp.id=spa.payment_id
 WHERE spa.purchase_id=p.id),'[]'::jsonb)) INTO v FROM public.purchases p
 LEFT JOIN public.suppliers s ON s.id=p.supplier_id WHERE p.id=p_purchase_id;
 RETURN v;
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_purchase_list_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_currency_supplier_debt_list_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_currency_supplier_ledger_v1(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_currency_purchase_detail_v1(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_purchase_list_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_debt_list_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_ledger_v1(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_currency_purchase_detail_v1(uuid) TO authenticated;


-- PHASE 06_CASHBOX_FINANCIAL_REPORTS_STAGING_ONLY.sql
-- Staging only. Preserve public RPC signatures/output keys; normalize all mixed-ledger sums to SYP.
-- Native supplier debts remain segregated by currency via admin_currency_supplier_*_v1.

CREATE OR REPLACE FUNCTION public.admin_cashbox_summary_v2(
 p_start timestamptz DEFAULT NULL,p_end timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE s timestamptz:=COALESCE(p_start,'1900-01-01'::timestamptz);
 e timestamptz:=COALESCE(p_end,'2999-12-31'::timestamptz); v jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF e<=s THEN RAISE EXCEPTION 'فترة الصندوق غير صالحة'; END IF;
 IF EXISTS(SELECT 1 FROM public.cashbox_entries WHERE currency='USD' AND amount_syp IS NULL) THEN
   RAISE EXCEPTION 'حركات دولار بلا مقابل ليرة؛ أوقف التقرير وصحح المصدر'; END IF;
 SELECT jsonb_build_object(
  'cash_in',COALESCE(SUM(GREATEST(COALESCE(c.amount_syp,c.amount),0)),0),
  'cash_out',COALESCE(SUM(GREATEST(-COALESCE(c.amount_syp,c.amount),0)),0),
  'net',COALESCE(SUM(COALESCE(c.amount_syp,c.amount)),0),
  'balance',COALESCE((SELECT SUM(COALESCE(x.amount_syp,x.amount)) FROM public.cashbox_entries x),0),
  'entries',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'id',x.id,'type',x.entry_type,'amount',COALESCE(x.amount_syp,x.amount),
    'original_amount',x.amount,'currency',x.currency,'fx_rate',x.fx_rate,
    'description',x.description,'created_at',x.created_at
  ) ORDER BY x.created_at DESC) FROM public.cashbox_entries x WHERE x.created_at>=s AND x.created_at<e),'[]'::jsonb)
 ) INTO v FROM public.cashbox_entries c WHERE c.created_at>=s AND c.created_at<e;
 RETURN v;
END;
$fn$;
CREATE OR REPLACE FUNCTION public.admin_dashboard_financial_summary(p_start timestamptz,p_end timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v_sales numeric:=0;v_gross_cost numeric:=0;v_returns numeric:=0;
 v_return_cost numeric:=0;v_purchases numeric:=0;v_profit numeric:=0;v_net_cost numeric:=0;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid financial period'; END IF;
 IF EXISTS(SELECT 1 FROM public.cashbox_entries WHERE currency='USD' AND amount_syp IS NULL) OR
    EXISTS(SELECT 1 FROM public.supplier_payments WHERE currency='USD' AND amount_syp IS NULL) OR
    EXISTS(SELECT 1 FROM public.purchases WHERE currency='USD' AND total_syp IS NULL) OR
    EXISTS(SELECT 1 FROM public.returns WHERE currency='USD' AND amount_syp IS NULL) THEN
  RAISE EXCEPTION 'سجلات دولار بلا تحويل بالليرة؛ التقرير المالي متوقف للحماية'; END IF;
 SELECT COALESCE(SUM(COALESCE(s.total_syp,s.total)),0) INTO v_sales
 FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end;
 SELECT COALESCE(SUM(si.quantity*si.unit_cost),0) INTO v_gross_cost
 FROM public.sale_items si JOIN public.sales s ON s.id=si.sale_id
 WHERE s.created_at>=p_start AND s.created_at<p_end;
 SELECT COALESCE(SUM(COALESCE(r.amount_syp,r.amount)),0) INTO v_returns
 FROM public.returns r WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end;
 SELECT COALESCE(SUM(r.quantity*si.unit_cost),0) INTO v_return_cost
 FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id
 WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end;
 SELECT COALESCE(SUM(COALESCE(p.total_syp,p.total)),0) INTO v_purchases
 FROM public.purchases p WHERE p.created_at>=p_start AND p.created_at<p_end;
 v_net_cost:=v_gross_cost-v_return_cost;
 v_profit:=v_sales-v_returns-v_net_cost;
 RETURN jsonb_build_object(
  'sales',v_sales,'cost_of_goods',v_net_cost,'gross_cost_of_goods',v_gross_cost,
  'customer_returns',v_returns,'customer_return_cost',v_return_cost,
  'net_sales',v_sales-v_returns,'profit',v_profit,
  'margin',CASE WHEN (v_sales-v_returns)=0 THEN 0 ELSE ROUND(v_profit/(v_sales-v_returns)*100,2) END,
  'purchases',v_purchases,
  'invoice_count',(SELECT COUNT(*) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),
  'purchase_count',(SELECT COUNT(*) FROM public.purchases WHERE created_at>=p_start AND created_at<p_end),
  'cash_in',COALESCE((SELECT SUM(COALESCE(amount_syp,amount)) FROM public.cashbox_entries
     WHERE COALESCE(amount_syp,amount)>0 AND created_at>=p_start AND created_at<p_end),0),
  'cash_out',COALESCE((SELECT SUM(-COALESCE(amount_syp,amount)) FROM public.cashbox_entries
     WHERE COALESCE(amount_syp,amount)<0 AND created_at>=p_start AND created_at<p_end),0),
  'cash_net',COALESCE((SELECT SUM(COALESCE(amount_syp,amount)) FROM public.cashbox_entries
     WHERE created_at>=p_start AND created_at<p_end),0),
  'debtor_payments',COALESCE((SELECT SUM(COALESCE(amount_syp,amount))
     FROM public.debtor_transactions WHERE transaction_type='payment'
     AND created_at>=p_start AND created_at<p_end),0),
  'supplier_payments',COALESCE((SELECT SUM(COALESCE(amount_syp,amount))
     FROM public.supplier_payments WHERE created_at>=p_start AND created_at<p_end),0),
  'orders_count',(SELECT COUNT(*) FROM public.orders WHERE created_at>=p_start AND created_at<p_end),
  'prescriptions_count',(SELECT COUNT(*) FROM public.prescriptions WHERE created_at>=p_start AND created_at<p_end)
 );
END;
$fn$;
-- Old admin_accounting_report is retained. New wrapper returns its keys with corrected SYP totals/rows.
CREATE OR REPLACE FUNCTION public.admin_currency_accounting_report_v1(
 p_start timestamptz,p_end timestamptz,p_compare_start timestamptz DEFAULT NULL,p_compare_end timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v jsonb; v_supplier_returns numeric; v_purchase_total numeric; v_cash_balance numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 v:=public.admin_accounting_report(p_start,p_end,p_compare_start,p_compare_end);
 SELECT COALESCE(SUM(COALESCE(amount_syp,amount)),0) INTO v_supplier_returns
  FROM public.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end;
 SELECT COALESCE(SUM(COALESCE(total_syp,total)),0) INTO v_purchase_total
  FROM public.purchases WHERE created_at>=p_start AND created_at<p_end;
 SELECT COALESCE(SUM(COALESCE(amount_syp,amount)),0) INTO v_cash_balance FROM public.cashbox_entries;
 v:=jsonb_set(v,'{summary,supplier_returns}',to_jsonb(v_supplier_returns));
 v:=jsonb_set(v,'{summary,net_purchases}',to_jsonb(v_purchase_total-v_supplier_returns));
 v:=jsonb_set(v,'{summary,cash_balance}',to_jsonb(v_cash_balance));
 v:=jsonb_set(v,'{purchase_rows}',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,'supplier_name',s.name,
 'total',COALESCE(p.total_syp,p.total),'original_total',p.total,'currency',p.currency,
 'fx_rate',p.fx_rate,'bonus_quantity',COALESCE((SELECT SUM(pi.bonus_quantity) FROM public.purchase_items pi WHERE pi.purchase_id=p.id),0)
 ) ORDER BY p.created_at DESC) FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id
 WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb));
 v:=jsonb_set(v,'{cash_rows}',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'id',c.id,'created_at',c.created_at,'type',c.entry_type,
 'amount',COALESCE(c.amount_syp,c.amount),'original_amount',c.amount,
 'currency',c.currency,'fx_rate',c.fx_rate,'description',c.description
 ) ORDER BY c.created_at DESC) FROM public.cashbox_entries c
 WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb));
 v:=jsonb_set(v,'{return_rows}',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',p.name,
 'quantity',r.quantity,'amount',COALESCE(r.amount_syp,r.amount),
 'original_amount',r.amount,'currency',r.currency,'fx_rate',r.fx_rate,'reason',r.reason
 ) ORDER BY r.created_at DESC) FROM public.returns r LEFT JOIN public.products p ON p.id=r.product_id
 WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb));
 RETURN v;
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_accounting_report_v1(timestamptz,timestamptz,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_accounting_report_v1(timestamptz,timestamptz,timestamptz,timestamptz) TO authenticated;


-- PHASE 08_SYP_MANUAL_CASHBOX_STAGING_ONLY.sql
-- صيدلية عبدالهادي — تصحيح دوال الصندوق اليدوي فقط (غير منفذ)
-- إضافة حقول SYP بوضوح إلى الحركات اليدوية الجديدة، دون تغيير أي سجل سابق.
-- Version: currency-stage2 / 2026-10-20
-- NOTICE: Apply only after reviewing on staging. This script has not been run on production.
-- This patch includes ONLY CREATE OR REPLACE FUNCTION; no destructive DDL or data updates.

CREATE OR REPLACE FUNCTION public.admin_cashbox_entry(
  p_type text, p_amount numeric, p_description text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','auth'
AS $function$
DECLARE v_id uuid; v_amount numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_amount IS NULL OR p_amount=0 THEN RAISE EXCEPTION 'المبلغ لا يمكن أن يكون صفراً'; END IF;
 IF p_type NOT IN ('expense','income','withdrawal','deposit','adjustment') THEN RAISE EXCEPTION 'نوع حركة صندوق غير صالح'; END IF;
 v_amount:=CASE WHEN p_type IN ('expense','withdrawal') THEN -abs(p_amount) ELSE abs(p_amount) END;
 INSERT INTO public.cashbox_entries(entry_type,amount,description,created_by,currency,fx_rate,amount_syp) VALUES(p_type,v_amount,p_description,auth.uid(),'SYP',1,v_amount) RETURNING id INTO v_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'cashbox_entry','cashbox',v_id,
 jsonb_build_object('type',p_type,'amount',p_amount,'signed_amount',v_amount,'currency','SYP','description',p_description));
 RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_cashbox_manual_entry(
  p_type text, p_amount numeric, p_description text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','auth'
AS $function$
DECLARE v_id uuid; v_amount numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_type NOT IN ('expense','income','withdrawal','deposit','adjustment') THEN RAISE EXCEPTION 'نوع حركة صندوق غير صالح'; END IF;
 IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر'; END IF;
 v_amount:=CASE WHEN p_type IN ('expense','withdrawal') THEN -abs(p_amount) ELSE abs(p_amount) END;
 INSERT INTO public.cashbox_entries(entry_type,amount,description,created_by,currency,fx_rate,amount_syp)
 VALUES(p_type,v_amount,NULLIF(trim(COALESCE(p_description,'')),''),auth.uid(),'SYP',1,v_amount)
 RETURNING id INTO v_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'cashbox_entry','cashbox',v_id,
 jsonb_build_object('type',p_type,'amount',abs(p_amount),'signed_amount',v_amount,'currency','SYP','description',p_description));
 RETURN jsonb_build_object('id',v_id,'type',p_type,'amount',v_amount);
END;
$function$;


-- PHASE 09_SYP_DEBTOR_PAYMENT_STAGING_ONLY.sql
-- PHARMACY ABDULHADI / STAGE 3 / FUNCTION CODE / NOT EXECUTED
-- For review on a *staging* copy ONLY. Never run blindly on production.
-- Safeguards: no DROP/TRUNCATE/DELETE; no INSERT/UPDATE except when a user calls
-- the created business functions. Running CREATE OR REPLACE changes definitions.
-- All amounts for existing customer debt payments remain SYP only.
-- Requires public.is_admin(), audit_logs, debtor_transactions and cashbox_entries.

CREATE OR REPLACE FUNCTION public.admin_record_debtor_payment(
  p_debtor_id uuid,
  p_amount numeric,
  p_notes text DEFAULT NULL::text,
  p_payment_method text DEFAULT 'cash'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','auth'
AS $function$
DECLARE
  v_balance numeric;
  v_tx uuid;
  v_name text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'مبلغ الدفعة يجب أن يكون أكبر من صفر';
  END IF;
  IF p_payment_method NOT IN ('cash','other') THEN
    RAISE EXCEPTION 'طريقة الدفع غير صالحة';
  END IF;

  -- The existing receivables ledger is SYP-denominated. Prevent mixed currencies
  -- from silently entering a single debtor balance until full USD debtor migration.
  IF EXISTS (
    SELECT 1 FROM public.debtor_transactions t
    WHERE t.debtor_id=p_debtor_id AND t.currency <> 'SYP'
  ) THEN
    RAISE EXCEPTION 'لا يمكن قبض دين متعدد العملات عبر دالة تحصيل الليرة';
  END IF;

  SELECT d.name,
         COALESCE((SELECT SUM(t.debit-t.credit)
                   FROM public.debtor_transactions t
                   WHERE t.debtor_id=d.id),0)
    INTO v_name,v_balance
  FROM public.debtors d
  WHERE d.id=p_debtor_id
  FOR UPDATE OF d;
  IF NOT FOUND THEN RAISE EXCEPTION 'المتدين غير موجود'; END IF;
  IF p_amount > v_balance THEN
    RAISE EXCEPTION 'الدفعة أكبر من الدين الحالي';
  END IF;

  INSERT INTO public.debtor_transactions
    (debtor_id,transaction_type,amount,debit,credit,payment_method,notes,
     created_by,currency,fx_rate,amount_syp)
  VALUES
    (p_debtor_id,'payment',p_amount,0,p_amount,p_payment_method,p_notes,
     auth.uid(),'SYP',1,p_amount)
  RETURNING id INTO v_tx;

  IF p_payment_method='cash' THEN
    INSERT INTO public.cashbox_entries
      (entry_type,amount,description,debtor_transaction_id,created_by,
       currency,fx_rate,amount_syp)
    VALUES
      ('debtor_payment',p_amount,'تحصيل دفعة من المتدين: '||v_name,v_tx,
       auth.uid(),'SYP',1,p_amount);
  END IF;

  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'debtor_payment','debtor',p_debtor_id,
         jsonb_build_object('name',v_name,'amount',p_amount,'currency','SYP',
                            'payment_method',p_payment_method,'notes',p_notes,
                            'previous_balance',v_balance,'new_balance',v_balance-p_amount));

  RETURN jsonb_build_object('transaction_id',v_tx,
                            'previous_balance',v_balance,
                            'new_balance',v_balance-p_amount,
                            'currency','SYP');
END;
$function$;


-- PHASE 10_SUPPLIER_HISTORY_SAFE_STAGING_ONLY.sql
-- Preserve existing supplier history UI with currency explicitly included. STAGING ONLY.

CREATE OR REPLACE FUNCTION public.admin_currency_supplier_purchase_history_v1(p_supplier_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
 'id',x.id,'invoice_number',x.invoice_number,'invoice_date',x.invoice_date,
 'total',x.total,'status',x.status,'paid_amount',x.paid_amount,'due_amount',x.due_amount,
 'payment_status',x.payment_status,'created_at',x.created_at,'item_count',x.item_count,
 'currency',x.currency,'fx_rate',x.fx_rate,'total_syp',x.total_syp
 ) ORDER BY x.created_at DESC),'[]'::jsonb)
 FROM (
 SELECT p.id,p.invoice_number,p.invoice_date,p.total,p.status,p.paid_amount,p.due_amount,
 p.payment_status,p.created_at,p.currency,p.fx_rate,
 CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END total_syp,
 COUNT(pi.id)::bigint item_count
 FROM public.purchases p LEFT JOIN public.purchase_items pi ON pi.purchase_id=p.id
 WHERE public.is_admin() AND p.supplier_id=p_supplier_id GROUP BY p.id
 ) x;
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_supplier_purchase_history_v1(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_purchase_history_v1(uuid) TO authenticated;


-- PHASE 12_SUPPLIER_RETURN_OPTIONS_READ_STAGING_ONLY.sql
-- Safe listing: price currency is explicitly tied to the original purchase invoice.
-- USD supplier return remains blocked pending supplier credit note/debt settlement.

CREATE OR REPLACE FUNCTION public.admin_currency_supplier_return_options_v1()
RETURNS TABLE(purchase_id uuid,invoice_number text,supplier_name text,purchase_date date,
 purchase_item_id uuid,batch_id uuid,product_id uuid,product_name text,
 purchased_quantity numeric,available_quantity numeric,purchase_price numeric,expiry_date date,currency text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
 SELECT p.id,p.invoice_number,s.name,p.invoice_date,pi.id,b.id,pr.id,pr.name,
   CASE WHEN b.id=pi.batch_id THEN pi.quantity ELSE pi.bonus_quantity END,
   COALESCE(b.quantity,0),CASE WHEN b.id=pi.batch_id THEN pi.purchase_price ELSE 0 END,b.expiry_date,p.currency
 FROM public.purchase_items pi JOIN public.purchases p ON p.id=pi.purchase_id
 JOIN public.products pr ON pr.id=pi.product_id
 LEFT JOIN public.suppliers s ON s.id=p.supplier_id
 JOIN public.batches b ON b.purchase_item_id=pi.id
 WHERE public.is_admin() AND b.id IS NOT NULL AND COALESCE(b.quantity,0)>0
 ORDER BY p.created_at DESC NULLS LAST,pr.name;
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_supplier_return_options_v1() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_return_options_v1() TO authenticated;


-- PHASE 15_SUPPLIER_RETURNS_CREDIT_NOTES.sql
-- V6.4.33 | Supplier credit notes in original purchase currency.
-- Run only AFTER 01..06 and 13; keep original transactions for audit.

-- The invariant is: total = allocated payments + credit notes + due (or refund receivable).
-- Old invoices had credit_amount=0, so old unpaid balances remain unchanged on deployment.
CREATE OR REPLACE FUNCTION public.admin_refresh_purchase_balance(p_purchase_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v_total numeric;v_credit numeric;v_paid numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT total,credit_amount INTO v_total,v_credit FROM public.purchases WHERE id=p_purchase_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة الشراء غير موجودة'; END IF;
 SELECT COALESCE(SUM(amount),0) INTO v_paid FROM public.supplier_payment_allocations WHERE purchase_id=p_purchase_id;
 IF v_paid>v_total+0.000001 THEN RAISE EXCEPTION 'دفعات الفاتورة تتجاوز قيمتها'; END IF;
 UPDATE public.purchases SET
  paid_amount=v_paid,
  due_amount=GREATEST(v_total-v_paid-v_credit,0),
  payment_status=CASE WHEN v_paid+v_credit>=v_total-0.000001 THEN 'paid'
    WHEN v_paid>0 OR v_credit>0 THEN 'partial' ELSE 'unpaid' END
 WHERE id=p_purchase_id;
END;
$fn$;

-- Preserve trigger behavior for old purchases, but account for credit notes on any future change.
CREATE OR REPLACE FUNCTION public.sync_purchase_payment_state()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
 IF TG_OP='INSERT' OR NEW.total IS DISTINCT FROM OLD.total
     OR NEW.credit_amount IS DISTINCT FROM OLD.credit_amount THEN
  NEW.paid_amount:=LEAST(GREATEST(COALESCE(NEW.paid_amount,0),0),COALESCE(NEW.total,0));
  NEW.due_amount:=GREATEST(COALESCE(NEW.total,0)-NEW.paid_amount-COALESCE(NEW.credit_amount,0),0);
  NEW.payment_status:=CASE WHEN NEW.paid_amount+COALESCE(NEW.credit_amount,0)>=NEW.total-0.000001
    THEN 'paid' WHEN NEW.paid_amount>0 OR COALESCE(NEW.credit_amount,0)>0 THEN 'partial' ELSE 'unpaid' END;
 END IF;
 RETURN NEW;
END;
$fn$;
-- Include credit changes in the existing trigger's update column list by a second trigger.
DO $guard$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.purchases'::regclass
     AND tgname='trg_ab_sync_purchase_credit_amount_v1') THEN
  CREATE TRIGGER trg_ab_sync_purchase_credit_amount_v1 BEFORE UPDATE OF credit_amount ON public.purchases
   FOR EACH ROW EXECUTE FUNCTION public.sync_purchase_payment_state();
 END IF;
END;
$guard$;

-- Return metadata is verified at insert; this blocks legacy RPCs from accidentally recording USD as SYP.
CREATE OR REPLACE FUNCTION public.ab_validate_supplier_return_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v_currency text;v_rate numeric;v_total numeric;v_subtotal numeric;v_credit numeric;
 v_batch_price numeric;v_pi_cost numeric;v_batch_purchase uuid;v_expected numeric;
BEGIN
 IF NEW.return_type<>'supplier' OR NEW.purchase_id IS NULL THEN RETURN NEW; END IF;
 SELECT currency,fx_rate,total,subtotal,credit_amount INTO v_currency,v_rate,v_total,v_subtotal,v_credit
 FROM public.purchases WHERE id=NEW.purchase_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة المرتجع غير موجودة'; END IF;
 SELECT b.purchase_price,b.purchase_id,pi.purchase_price_syp
 INTO v_batch_price,v_batch_purchase,v_pi_cost
 FROM public.batches b LEFT JOIN public.purchase_items pi ON pi.id=b.purchase_item_id
 WHERE b.id=NEW.batch_id;
 IF NOT FOUND OR v_batch_purchase IS DISTINCT FROM NEW.purchase_id THEN
  RAISE EXCEPTION 'دفعة المرتجع لا تتبع لفاتورة المورد'; END IF;
 IF NEW.currency IS DISTINCT FROM v_currency OR NEW.fx_rate IS DISTINCT FROM v_rate THEN
  RAISE EXCEPTION 'عملة أو سعر صرف المرتجع لا يطابق فاتورة المورد'; END IF;
 IF NEW.quantity IS NULL OR NEW.quantity<=0 THEN RAISE EXCEPTION 'كمية المرتجع غير صالحة'; END IF;
 v_expected:=CASE WHEN v_currency='USD' THEN
    ROUND(NEW.quantity*v_batch_price/v_rate,2)
   WHEN v_pi_cost IS NOT NULL THEN ROUND(NEW.quantity*v_batch_price,2)
   ELSE ROUND(NEW.quantity*v_batch_price*
       CASE WHEN v_subtotal>0 THEN v_total/v_subtotal ELSE 1 END,2) END;
 -- The last returned line may be rounded down to the invoice's remaining creditable total.
 v_expected:=LEAST(v_expected,GREATEST(v_total-v_credit,0));
 IF NEW.amount IS NULL OR ABS(NEW.amount-v_expected)>0.01 THEN
  RAISE EXCEPTION 'قيمة إشعار الدائن لا تطابق تكلفة المرتجع المحاسبية'; END IF;
 IF NEW.amount_syp IS DISTINCT FROM (CASE WHEN v_currency='USD'
      THEN ROUND(NEW.amount*v_rate,2) ELSE NEW.amount END) THEN
  RAISE EXCEPTION 'تحويل إشعار الدائن إلى الليرة غير مطابق'; END IF;
 RETURN NEW;
END;
$fn$;
CREATE OR REPLACE FUNCTION public.ab_apply_supplier_return_credit_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
BEGIN
 IF NEW.return_type='supplier' AND NEW.purchase_id IS NOT NULL THEN
  UPDATE public.purchases SET credit_amount=credit_amount+NEW.amount WHERE id=NEW.purchase_id;
  PERFORM public.admin_refresh_purchase_balance(NEW.purchase_id);
 END IF;
 RETURN NEW;
END;
$fn$;
CREATE OR REPLACE FUNCTION public.ab_immutable_supplier_return_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
BEGIN
 IF OLD.return_type='supplier' THEN
  RAISE EXCEPTION 'لا يمكن تعديل أو حذف إشعار دائن مسجل. استخدم تسوية موثقة بدلاً من ذلك';
 END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END;
$fn$;
DO $guard$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.returns'::regclass AND tgname='trg_ab_validate_supplier_return_v1') THEN
  CREATE TRIGGER trg_ab_validate_supplier_return_v1 BEFORE INSERT ON public.returns
  FOR EACH ROW EXECUTE FUNCTION public.ab_validate_supplier_return_v1();
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.returns'::regclass AND tgname='trg_ab_apply_supplier_return_credit_v1') THEN
  CREATE TRIGGER trg_ab_apply_supplier_return_credit_v1 AFTER INSERT ON public.returns
  FOR EACH ROW EXECUTE FUNCTION public.ab_apply_supplier_return_credit_v1();
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.returns'::regclass AND tgname='trg_ab_immutable_supplier_return_v1') THEN
  CREATE TRIGGER trg_ab_immutable_supplier_return_v1 BEFORE UPDATE OR DELETE ON public.returns
  FOR EACH ROW EXECUTE FUNCTION public.ab_immutable_supplier_return_v1();
 END IF;
END;
$guard$;

-- Atomic stock movement + correct native-currency credit note; never touches existing invoice total.
CREATE OR REPLACE FUNCTION public.admin_currency_supplier_return_v2(
 p_purchase_id uuid,p_mode text,p_items jsonb DEFAULT '[]'::jsonb,
 p_reason text DEFAULT 'مرتجع إلى المورد') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE inv record; r record;it jsonb;v_batch uuid;v_qty numeric;v_amount numeric;
 v_expected numeric;v_total numeric:=0;v_count integer:=0;v_lines jsonb:='[]'::jsonb;
 v_seen uuid[]:=ARRAY[]::uuid[];
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_purchase_id IS NULL OR p_mode NOT IN ('full','count_1','count_2','count_3','selected') THEN
  RAISE EXCEPTION 'نوع المرتجع غير صالح'; END IF;
 SELECT * INTO inv FROM public.purchases WHERE id=p_purchase_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة الشراء غير موجودة'; END IF;
 IF p_mode<>'full' AND jsonb_typeof(COALESCE(p_items,'[]'::jsonb))<>'array' THEN
  RAISE EXCEPTION 'بيانات المرتجع يجب أن تكون قائمة'; END IF;
 IF p_mode IN ('count_1','count_2','count_3') AND
   jsonb_array_length(COALESCE(p_items,'[]'::jsonb)) <> split_part(p_mode,'_',2)::int THEN
  RAISE EXCEPTION 'عدد الأصناف المحدد لا يطابق نوع المرتجع'; END IF;
 IF p_mode='selected' AND jsonb_array_length(COALESCE(p_items,'[]'::jsonb))=0 THEN
  RAISE EXCEPTION 'اختر مادة واحدة على الأقل'; END IF;
 IF p_mode='full' THEN
  FOR r IN SELECT b.id batch_id,b.product_id,pr.name product_name,b.quantity available,
    b.purchase_price,pi.purchase_price_syp,pi.quantity paid_qty,pi.bonus_quantity,b.batch_number
    FROM public.purchase_items pi JOIN public.batches b ON b.purchase_item_id=pi.id
    JOIN public.products pr ON pr.id=pi.product_id
    WHERE pi.purchase_id=p_purchase_id AND b.quantity>0 ORDER BY b.id FOR UPDATE OF b
  LOOP
   v_qty:=r.available;
   v_expected:=CASE WHEN inv.currency='USD' THEN ROUND(v_qty*r.purchase_price/inv.fx_rate,2)
       WHEN r.purchase_price_syp IS NOT NULL THEN ROUND(v_qty*r.purchase_price,2)
       ELSE ROUND(v_qty*r.purchase_price*CASE WHEN inv.subtotal>0 THEN inv.total/inv.subtotal ELSE 1 END,2) END;
   v_amount:=LEAST(v_expected,GREATEST(inv.total-inv.credit_amount-v_total,0));
   UPDATE public.batches SET quantity=quantity-v_qty WHERE id=r.batch_id;
   INSERT INTO public.returns(return_type,purchase_id,product_id,batch_id,quantity,amount,amount_syp,currency,fx_rate,reason,created_by)
   VALUES('supplier',p_purchase_id,r.product_id,r.batch_id,v_qty,v_amount,
     CASE WHEN inv.currency='USD' THEN ROUND(v_amount*inv.fx_rate,2) ELSE v_amount END,
     inv.currency,inv.fx_rate,COALESCE(p_reason,'مرتجع للمورد'),auth.uid());
   INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by)
   VALUES(r.product_id,r.batch_id,'supplier_return',-v_qty,p_purchase_id,COALESCE(p_reason,'مرتجع للمورد'),auth.uid());
   v_total:=v_total+v_amount;v_count:=v_count+1;
   v_lines:=v_lines||jsonb_build_object('product_name',r.product_name,'quantity',v_qty,'amount',v_amount,'batch_id',r.batch_id);
  END LOOP;
 ELSE
  FOR it IN SELECT value FROM jsonb_array_elements(COALESCE(p_items,'[]'::jsonb)) LOOP
   v_batch:=NULLIF(it->>'batch_id','')::uuid;
   v_qty:=NULLIF(it->>'quantity','')::numeric;
   IF v_batch IS NULL OR v_qty IS NULL OR v_qty<=0 OR v_batch=ANY(v_seen) THEN
    RAISE EXCEPTION 'دفعة مرتجع مكررة أو كمية غير صالحة'; END IF;
   v_seen:=array_append(v_seen,v_batch);
   SELECT b.id batch_id,b.product_id,pr.name product_name,b.quantity available,
     b.purchase_price,pi.purchase_price_syp,pi.quantity paid_qty,pi.bonus_quantity,b.batch_number
     INTO r FROM public.purchase_items pi JOIN public.batches b ON b.purchase_item_id=pi.id
     JOIN public.products pr ON pr.id=pi.product_id
     WHERE pi.purchase_id=p_purchase_id AND b.id=v_batch FOR UPDATE OF b;
   IF NOT FOUND THEN RAISE EXCEPTION 'دفعة المرتجع لا تتبع هذه الفاتورة'; END IF;
   IF v_qty>r.available+0.000001 THEN RAISE EXCEPTION 'الكمية تتجاوز مخزون الدفعة'; END IF;
   v_expected:=CASE WHEN inv.currency='USD' THEN ROUND(v_qty*r.purchase_price/inv.fx_rate,2)
       WHEN r.purchase_price_syp IS NOT NULL THEN ROUND(v_qty*r.purchase_price,2)
       ELSE ROUND(v_qty*r.purchase_price*CASE WHEN inv.subtotal>0 THEN inv.total/inv.subtotal ELSE 1 END,2) END;
   v_amount:=LEAST(v_expected,GREATEST(inv.total-inv.credit_amount-v_total,0));
   UPDATE public.batches SET quantity=quantity-v_qty WHERE id=v_batch;
   INSERT INTO public.returns(return_type,purchase_id,product_id,batch_id,quantity,amount,amount_syp,currency,fx_rate,reason,created_by)
   VALUES('supplier',p_purchase_id,r.product_id,v_batch,v_qty,v_amount,
     CASE WHEN inv.currency='USD' THEN ROUND(v_amount*inv.fx_rate,2) ELSE v_amount END,
     inv.currency,inv.fx_rate,COALESCE(p_reason,'مرتجع للمورد'),auth.uid());
   INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by)
   VALUES(r.product_id,v_batch,'supplier_return',-v_qty,p_purchase_id,COALESCE(p_reason,'مرتجع للمورد'),auth.uid());
   v_total:=v_total+v_amount;v_count:=v_count+1;
   v_lines:=v_lines||jsonb_build_object('product_name',r.product_name,'quantity',v_qty,'amount',v_amount,'batch_id',v_batch);
  END LOOP;
 END IF;
 IF v_count=0 THEN RAISE EXCEPTION 'لا توجد دفعات متاحة للإرجاع'; END IF;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'supplier_credit_note','purchase',p_purchase_id,
  jsonb_build_object('currency',inv.currency,'fx_rate',inv.fx_rate,'amount',v_total,'items',v_lines,'reason',p_reason));
 RETURN jsonb_build_object('purchase_id',p_purchase_id,'currency',inv.currency,'credit_amount',v_total,
   'items_count',v_count,'items',v_lines);
END;
$fn$;

-- Preserve old RPC interfaces while sending every new supplier return through the safe currency-aware implementation.
CREATE OR REPLACE FUNCTION public.admin_supplier_return_bundle(
 p_purchase_id uuid,p_mode text,p_items jsonb DEFAULT '[]'::jsonb,
 p_reason text DEFAULT 'مرتجع إلى المورد') RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public','auth' AS $fn$
 SELECT public.admin_currency_supplier_return_v2(p_purchase_id,p_mode,p_items,p_reason);
$fn$;
CREATE OR REPLACE FUNCTION public.admin_supplier_return(
 p_batch_id uuid,p_quantity numeric,p_reason text DEFAULT 'مرتجع إلى المورد')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth' AS $fn$
DECLARE v_purchase uuid;v_result jsonb;
BEGIN
 SELECT purchase_id INTO v_purchase FROM public.batches WHERE id=p_batch_id;
 IF v_purchase IS NULL THEN RAISE EXCEPTION 'لا يمكن تنفيذ مرتجع بدون فاتورة شراء مرتبطة'; END IF;
 v_result:=public.admin_currency_supplier_return_v2(v_purchase,'selected',
  jsonb_build_array(jsonb_build_object('batch_id',p_batch_id,'quantity',p_quantity)),p_reason);
 RETURN jsonb_build_object('batch_id',p_batch_id,'quantity',p_quantity,'amount',v_result->'credit_amount',   'currency',v_result->'currency');
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_supplier_return_v2(uuid,text,jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_return_v2(uuid,text,jsonb,text) TO authenticated;


-- PHASE 16_SUPPLIER_REFUNDS_RECEIPTS.sql
-- V6.4.33 Supplier refund collection after a paid invoice receives a supplier credit note.
-- Invoice total remains unchanged; refund receivable = paid + credit - total - refunds.

CREATE OR REPLACE FUNCTION public.admin_currency_supplier_refund_receipt_v1(
 p_purchase_id uuid,p_amount numeric,p_payment_method text DEFAULT 'cash',p_notes text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE inv record; v_refunded numeric;v_available numeric;v_rate numeric;v_amount_syp numeric;
 v_refund_id uuid; v_cash_id uuid;v_supplier_name text;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_amount IS NULL OR p_amount<=0 OR p_amount<>ROUND(p_amount,2) THEN
  RAISE EXCEPTION 'المبلغ المسترد يجب أن يكون موجباً وبحد أقصى منزلتين عشريتين'; END IF;
 IF p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الاسترداد غير صالحة'; END IF;
 SELECT * INTO inv FROM public.purchases WHERE id=p_purchase_id FOR UPDATE;
 IF NOT FOUND OR inv.supplier_id IS NULL THEN RAISE EXCEPTION 'فاتورة المورد غير موجودة'; END IF;
 SELECT name INTO v_supplier_name FROM public.suppliers WHERE id=inv.supplier_id;
 SELECT COALESCE(SUM(amount),0) INTO v_refunded FROM public.supplier_refund_receipts WHERE purchase_id=p_purchase_id;
 v_available:=GREATEST(inv.paid_amount+COALESCE(inv.credit_amount,0)-inv.total-v_refunded,0);
 IF p_amount>v_available+0.000001 THEN RAISE EXCEPTION 'قيمة الاسترداد تتجاوز المبلغ المستحق من المورد: %',v_available; END IF;
 IF inv.currency='USD' THEN
  SELECT usd_to_syp INTO v_rate FROM public.pharmacy_currency_settings WHERE id=1 FOR SHARE;
  IF v_rate IS NULL OR v_rate<=1 THEN RAISE EXCEPTION 'سعر صرف الدولار غير مضبوط'; END IF;
 ELSE v_rate:=1; END IF;
 v_amount_syp:=ROUND(p_amount*v_rate,2);
 INSERT INTO public.supplier_refund_receipts(supplier_id,purchase_id,currency,amount,fx_rate,amount_syp,
   payment_method,notes,created_by)
 VALUES(inv.supplier_id,p_purchase_id,inv.currency,p_amount,v_rate,v_amount_syp,
   p_payment_method,NULLIF(trim(COALESCE(p_notes,'')),''),auth.uid()) RETURNING id INTO v_refund_id;
 IF p_payment_method='cash' THEN
  INSERT INTO public.cashbox_entries(entry_type,amount,description,purchase_id,created_by,currency,fx_rate,amount_syp)
  VALUES('income',p_amount,'استرداد نقدي من المورد: '||v_supplier_name||' — إشعار دائن فاتورة '||
    COALESCE(inv.invoice_number,'—'),p_purchase_id,auth.uid(),inv.currency,v_rate,v_amount_syp)
  RETURNING id INTO v_cash_id;
  UPDATE public.supplier_refund_receipts SET cashbox_entry_id=v_cash_id WHERE id=v_refund_id;
 END IF;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'supplier_refund_receipt','purchase',p_purchase_id,
   jsonb_build_object('id',v_refund_id,'amount',p_amount,'currency',inv.currency,'fx_rate',v_rate,
   'amount_syp',v_amount_syp,'payment_method',p_payment_method,'cashbox_entry_id',v_cash_id,'notes',p_notes));
 RETURN jsonb_build_object('id',v_refund_id,'purchase_id',p_purchase_id,'supplier_id',inv.supplier_id,
    'currency',inv.currency,'amount',p_amount,'fx_rate',v_rate,'amount_syp',v_amount_syp,
    'cashbox_entry_id',v_cash_id,'refund_due',v_available-p_amount);
END;
$fn$;

-- The standalone supplier refund table has no direct access for ordinary API users.
REVOKE ALL ON FUNCTION public.admin_currency_supplier_refund_receipt_v1(uuid,numeric,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_refund_receipt_v1(uuid,numeric,text,text) TO authenticated;


-- PHASE 17_CURRENCY_READ_MODELS.sql
-- V6.4.33: Currency-aware purchasing, debt, return and refund read models.
-- Existing SYP totals unchanged; all supplier currencies remain separate.

CREATE OR REPLACE FUNCTION public.admin_currency_purchase_list_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth' AS $fn$
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
 'id',p.id,'supplier_id',p.supplier_id,'supplier_name',s.name,'invoice_number',p.invoice_number,
 'invoice_date',p.invoice_date,'created_at',p.created_at,'status',p.status,'notes',p.notes,
 'subtotal',p.subtotal,'discount_type',p.discount_type,'discount_value',p.discount_value,
 'discount_amount',p.discount_amount,'total',p.total,'paid_amount',p.paid_amount,'credit_amount',p.credit_amount,
 'due_amount',p.due_amount,'payment_status',p.payment_status,'item_count',
 (SELECT COUNT(*) FROM public.purchase_items pi WHERE pi.purchase_id=p.id),
 'bonus_quantity',(SELECT COALESCE(SUM(bonus_quantity),0) FROM public.purchase_items pi WHERE pi.purchase_id=p.id),
 'currency',p.currency,'fx_rate',p.fx_rate,'total_syp',CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END,
 'refunded_amount',(SELECT COALESCE(SUM(sr.amount),0) FROM public.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),
 'refund_due',GREATEST(p.paid_amount+p.credit_amount-p.total-
    (SELECT COALESCE(SUM(sr.amount),0) FROM public.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0)
 ) ORDER BY p.created_at DESC),'[]'::jsonb)
 FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id
 WHERE public.is_admin();
$fn$;

CREATE OR REPLACE FUNCTION public.admin_currency_supplier_debt_list_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth' AS $fn$
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
 'id',x.id,'name',x.name,'phone',x.phone,'address',x.address,'currency',x.currency,
 'invoice_total',x.invoice_total,'paid_total',x.paid_total,'credit_total',x.credit_total,
 'balance',x.balance,'refund_due',x.refund_due,'invoice_count',x.invoice_count,
 'payment_count',x.payment_count,'last_payment',x.last_payment,'last_invoice',x.last_invoice
 ) ORDER BY x.name,x.currency),'[]'::jsonb)
 FROM (
 SELECT s.id,s.name,s.phone,s.address,p.currency,
 SUM(p.total) invoice_total,SUM(p.paid_amount) paid_total,SUM(p.credit_amount) credit_total,
 SUM(p.due_amount) balance,
 SUM(GREATEST(p.paid_amount+p.credit_amount-p.total-
  (SELECT COALESCE(SUM(sr.amount),0) FROM public.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0)) refund_due,
 COUNT(*) invoice_count,
 (SELECT COUNT(*) FROM public.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=p.currency) payment_count,
 (SELECT MAX(sp.created_at) FROM public.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=p.currency) last_payment,
 MAX(p.created_at) last_invoice
 FROM public.suppliers s JOIN public.purchases p ON p.supplier_id=s.id
 WHERE public.is_admin() GROUP BY s.id,p.currency
 ) x;
$fn$;

CREATE OR REPLACE FUNCTION public.admin_currency_supplier_ledger_v1(p_supplier_id uuid,p_currency text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth' AS $fn$
DECLARE v_currency text:=upper(COALESCE(p_currency,''));v jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF v_currency NOT IN ('USD','SYP') THEN RAISE EXCEPTION 'عملة المورد غير صالحة'; END IF;
 SELECT jsonb_build_object(
  'supplier',to_jsonb(s)||jsonb_build_object('currency',v_currency),
  'summary',jsonb_build_object(
   'invoice_total',COALESCE((SELECT SUM(total) FROM public.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'paid_total',COALESCE((SELECT SUM(paid_amount) FROM public.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'credit_total',COALESCE((SELECT SUM(credit_amount) FROM public.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'balance',COALESCE((SELECT SUM(due_amount) FROM public.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'refund_due',COALESCE((SELECT SUM(GREATEST(p.paid_amount+p.credit_amount-p.total-
     (SELECT COALESCE(SUM(sr.amount),0) FROM public.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0))
     FROM public.purchases p WHERE p.supplier_id=s.id AND p.currency=v_currency),0)),
  'invoices',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',p.id,'invoice_number',p.invoice_number,'invoice_date',p.invoice_date,
   'created_at',p.created_at,'total',p.total,'paid_amount',p.paid_amount,
   'credit_amount',p.credit_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,
   'currency',p.currency,'fx_rate',p.fx_rate,'notes',p.notes,'total_syp',CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END,
   'refunded_amount',(SELECT COALESCE(SUM(sr.amount),0) FROM public.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),
   'refund_due',GREATEST(p.paid_amount+p.credit_amount-p.total-
    (SELECT COALESCE(SUM(sr.amount),0) FROM public.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0),
   'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'product_name',pr.name,'barcode',pr.barcode,'quantity',pi.quantity,'bonus_quantity',pi.bonus_quantity,
    'purchase_price',pi.purchase_price,'purchase_price_syp',pi.purchase_price_syp,
    'sale_price',pi.sale_price,'sale_currency',pi.sale_price_currency,
    'expiry_date',pi.expiry_date,'batch_id',pi.batch_id))
    FROM public.purchase_items pi JOIN public.products pr ON pr.id=pi.product_id
    WHERE pi.purchase_id=p.id),'[]'::jsonb)) ORDER BY p.created_at DESC)
    FROM public.purchases p WHERE p.supplier_id=s.id AND p.currency=v_currency),'[]'::jsonb),
  'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',sp.id,'amount',sp.amount,'currency',sp.currency,'fx_rate',sp.fx_rate,'amount_syp',sp.amount_syp,
   'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
   'allocations',COALESCE((SELECT jsonb_agg(jsonb_build_object('purchase_id',a.purchase_id,'amount',a.amount,
    'invoice_number',p2.invoice_number)) FROM public.supplier_payment_allocations a
    JOIN public.purchases p2 ON p2.id=a.purchase_id WHERE a.payment_id=sp.id),'[]'::jsonb))
    ORDER BY sp.created_at DESC) FROM public.supplier_payments sp
    WHERE sp.supplier_id=s.id AND sp.currency=v_currency),'[]'::jsonb),
  'credit_notes',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',r.id,'purchase_id',r.purchase_id,'invoice_number',p.invoice_number,'quantity',r.quantity,
   'amount',r.amount,'amount_syp',r.amount_syp,'currency',r.currency,'created_at',r.created_at,'reason',r.reason)
   ORDER BY r.created_at DESC) FROM public.returns r JOIN public.purchases p ON p.id=r.purchase_id
   WHERE r.return_type='supplier' AND p.supplier_id=s.id AND p.currency=v_currency),'[]'::jsonb),
  'refunds',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',sr.id,'purchase_id',sr.purchase_id,'amount',sr.amount,'amount_syp',sr.amount_syp,
   'currency',sr.currency,'fx_rate',sr.fx_rate,'created_at',sr.created_at,
   'payment_method',sr.payment_method,'notes',sr.notes)
   ORDER BY sr.created_at DESC) FROM public.supplier_refund_receipts sr
   WHERE sr.supplier_id=s.id AND sr.currency=v_currency),'[]'::jsonb))
 INTO v FROM public.suppliers s WHERE s.id=p_supplier_id;
 IF v IS NULL THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 RETURN v;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.admin_currency_purchase_detail_v1(p_purchase_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth' AS $fn$
DECLARE v jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object('id',p.id,'supplier_id',p.supplier_id,'supplier_name',s.name,
  'invoice_number',p.invoice_number,'invoice_date',p.invoice_date,'subtotal',p.subtotal,
  'discount_type',p.discount_type,'discount_value',p.discount_value,'discount_amount',p.discount_amount,
  'total',p.total,'paid_amount',p.paid_amount,'credit_amount',p.credit_amount,
  'due_amount',p.due_amount,'payment_status',p.payment_status,
  'status',p.status,'notes',p.notes,'created_at',p.created_at,'currency',p.currency,'fx_rate',p.fx_rate,
  'total_syp',CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END,
  'refunded_amount',(SELECT COALESCE(SUM(sr.amount),0) FROM public.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),
  'refund_due',GREATEST(p.paid_amount+p.credit_amount-p.total-
    (SELECT COALESCE(SUM(sr.amount),0) FROM public.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0),
  'bonus_quantity',(SELECT COALESCE(SUM(pi.bonus_quantity),0) FROM public.purchase_items pi WHERE pi.purchase_id=p.id),
  'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',pi.id,'product_id',pi.product_id,'product_name',pr.name,'barcode',pr.barcode,
   'active_ingredient',pr.active_ingredient,'quantity',pi.quantity,'bonus_quantity',pi.bonus_quantity,
   'purchase_price',pi.purchase_price,'purchase_price_syp',pi.purchase_price_syp,'sale_price',pi.sale_price,
   'sale_currency',pi.sale_price_currency,'expiry_date',pi.expiry_date,'batch_id',pi.batch_id))
   FROM public.purchase_items pi JOIN public.products pr ON pr.id=pi.product_id
   WHERE pi.purchase_id=p.id),'[]'::jsonb),
  'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',sp.id,'amount',a.amount,'currency',sp.currency,'fx_rate',sp.fx_rate,
   'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
   'cashbox_entry_id',sp.cashbox_entry_id))
   FROM public.supplier_payment_allocations a JOIN public.supplier_payments sp ON sp.id=a.payment_id
   WHERE a.purchase_id=p.id),'[]'::jsonb)) INTO v
 FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id WHERE p.id=p_purchase_id;
 RETURN v;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.admin_currency_return_list_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth' AS $fn$
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',r.id,'return_type',r.return_type,
  'product_name',p.name,'quantity',r.quantity,'amount',r.amount,'amount_syp',COALESCE(r.amount_syp,r.amount),
  'currency',r.currency,'fx_rate',r.fx_rate,'reason',r.reason,'created_at',r.created_at,
  'purchase_id',r.purchase_id,'sale_id',r.sale_id) ORDER BY r.created_at DESC),'[]'::jsonb)
 FROM (SELECT * FROM public.returns ORDER BY created_at DESC LIMIT 500) r
 LEFT JOIN public.products p ON p.id=r.product_id WHERE public.is_admin();
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_purchase_list_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_currency_supplier_debt_list_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_currency_supplier_ledger_v1(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_currency_purchase_detail_v1(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_currency_return_list_v1() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_purchase_list_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_debt_list_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_ledger_v1(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_currency_purchase_detail_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_currency_return_list_v1() TO authenticated;


-- PHASE 18_SYP_PURCHASE_COMPLETE.sql
-- V6.4.33 SYP purchase path: independently stored USD/SYP sale-price currency,
-- correct net batch cost after invoice discounts and zero-cost bonus batches.
-- Existing SYP purchasing RPC remains unchanged for old frontend compatibility.

CREATE OR REPLACE FUNCTION public.admin_create_purchase_syp_v1(
 p_supplier_id uuid,p_new_supplier jsonb,p_invoice_number text,p_invoice_date date,p_notes text,
 p_items jsonb,p_payment_amount numeric,p_payment_method text,p_payment_notes text,
 p_discount_type text,p_discount_value numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v_result jsonb;v_purchase_id uuid;v_factor numeric;v_item jsonb;v_pid uuid;
 v_currency text;v_fx numeric;v_sale_price numeric;v_used uuid[]:=ARRAY[]::uuid[];
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN
  RAISE EXCEPTION 'فاتورة الشراء فارغة'; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
  v_pid:=NULLIF(v_item->>'product_id','')::uuid;
  v_currency:=upper(COALESCE(NULLIF(v_item->>'sale_currency',''),'SYP'));
  v_sale_price:=NULLIF(v_item->>'sale_price','')::numeric;
  IF v_pid IS NULL OR v_pid=ANY(v_used) OR v_currency NOT IN ('USD','SYP') THEN
   RAISE EXCEPTION 'صنف مكرر أو عملة بيع غير صالحة'; END IF;
  IF v_sale_price IS NULL OR v_sale_price<=0 THEN RAISE EXCEPTION 'سعر البيع غير صالح'; END IF;
  v_used:=array_append(v_used,v_pid);
 END LOOP;
 SELECT usd_to_syp INTO v_fx FROM public.pharmacy_currency_settings WHERE id=1 FOR SHARE;
 IF v_fx IS NULL THEN RAISE EXCEPTION 'إعداد العملة غير موجود'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_items) x WHERE upper(COALESCE(NULLIF(x->>'sale_currency',''),'SYP'))='USD')
     AND v_fx<=1 THEN RAISE EXCEPTION 'سعر صرف الدولار غير مضبوط لتسعير البيع'; END IF;
 v_result:=public.admin_create_purchase_with_payment_discount(
  p_supplier_id,p_new_supplier,p_invoice_number,p_invoice_date,p_notes,p_items,
  p_payment_amount,p_payment_method,p_payment_notes,p_discount_type,p_discount_value);
 v_purchase_id:=(v_result->>'id')::uuid;
 IF v_purchase_id IS NULL THEN RAISE EXCEPTION 'لم يتم إرجاع رقم فاتورة الشراء'; END IF;
 SELECT CASE WHEN subtotal>0 THEN total/subtotal ELSE 1 END INTO v_factor
 FROM public.purchases WHERE id=v_purchase_id FOR UPDATE;
 IF v_factor<0 OR v_factor>1 THEN RAISE EXCEPTION 'نسبة خصم الفاتورة غير صالحة'; END IF;
 -- Only NEW invoice lines are updated, never existing stock batches.
 UPDATE public.batches b
 SET original_purchase_price=b.purchase_price,
     purchase_price=ROUND(b.purchase_price*v_factor,6),
     purchase_currency='SYP',purchase_fx_rate=1
 WHERE b.purchase_id=v_purchase_id AND b.purchase_price>0;
 UPDATE public.purchase_items pi
 SET purchase_price_syp=ROUND(pi.purchase_price*v_factor,6),
     purchase_currency='SYP',purchase_fx_rate=1,
     sale_price_currency=upper(COALESCE(NULLIF(x.item->>'sale_currency',''),'SYP'))
 FROM (SELECT value item FROM jsonb_array_elements(p_items)) x
 WHERE pi.purchase_id=v_purchase_id AND pi.product_id=(x.item->>'product_id')::uuid;
 UPDATE public.products pr SET
  purchase_price=ROUND(pi.purchase_price*v_factor,6),
  sale_price=pi.sale_price,sale_currency=pi.sale_price_currency,
  updated_at=now()
 FROM public.purchase_items pi WHERE pi.purchase_id=v_purchase_id AND pi.product_id=pr.id;
 UPDATE public.purchases SET currency='SYP',fx_rate=1,total_syp=total WHERE id=v_purchase_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'purchase_syp_currency_aware','purchase',v_purchase_id,
    jsonb_build_object('cost_discount_factor',v_factor,'sale_currency_independent',true));
 RETURN v_result||jsonb_build_object('currency','SYP','fx_rate',1);
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_create_purchase_syp_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_purchase_syp_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric) TO authenticated;


-- PHASE 19_FINAL_CURRENCY_CONTRACT.sql
-- V6.4.33 Backend contract. TRUE only when every purchase, debt, return/refund component exists.
-- The front end uses this as a fail-closed feature gate; no direct writes.

CREATE OR REPLACE FUNCTION public.admin_currency_backend_contract_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v_rate numeric;v_writes boolean;v_reads boolean;v_columns boolean;
 v_triggers boolean;v_balances boolean;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT usd_to_syp INTO v_rate FROM public.pharmacy_currency_settings WHERE id=1;
 v_writes:=
  to_regprocedure('public.admin_create_purchase_usd_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric)') IS NOT NULL AND
  to_regprocedure('public.admin_create_purchase_syp_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric)') IS NOT NULL AND
  to_regprocedure('public.admin_record_supplier_payment_usd_v1(uuid,numeric,uuid,text,text)') IS NOT NULL AND
  to_regprocedure('public.admin_currency_supplier_return_v2(uuid,text,jsonb,text)') IS NOT NULL AND
  to_regprocedure('public.admin_currency_supplier_refund_receipt_v1(uuid,numeric,text,text)') IS NOT NULL;
 v_reads:=
  to_regprocedure('public.admin_currency_purchase_list_v1()') IS NOT NULL AND
  to_regprocedure('public.admin_currency_supplier_debt_list_v1()') IS NOT NULL AND
  to_regprocedure('public.admin_currency_supplier_ledger_v1(uuid,text)') IS NOT NULL AND
  to_regprocedure('public.admin_currency_purchase_detail_v1(uuid)') IS NOT NULL AND
  to_regprocedure('public.admin_currency_return_list_v1()') IS NOT NULL AND
  to_regprocedure('public.admin_currency_supplier_return_options_v1()') IS NOT NULL AND
  to_regprocedure('public.admin_currency_supplier_purchase_history_v1(uuid)') IS NOT NULL AND
  to_regprocedure('public.admin_currency_accounting_report_v1(timestamptz,timestamptz,timestamptz,timestamptz)') IS NOT NULL;
 v_columns:=
  (SELECT COUNT(*)=4 FROM information_schema.columns WHERE table_schema='public' AND table_name='purchases' AND column_name IN ('currency','fx_rate','total_syp','credit_amount'))
  AND (SELECT COUNT(*)=3 FROM information_schema.columns WHERE table_schema='public' AND table_name='supplier_payments' AND column_name IN ('currency','fx_rate','amount_syp'))
  AND to_regclass('public.supplier_refund_receipts') IS NOT NULL;
 v_triggers:=
  EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.supplier_payment_allocations'::regclass
    AND tgname='trg_ab_allocation_metadata_guard_v1' AND tgenabled IN ('O','A'))
  AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.returns'::regclass
    AND tgname='trg_ab_validate_supplier_return_v1' AND tgenabled IN ('O','A'))
  AND EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.returns'::regclass
    AND tgname='trg_ab_apply_supplier_return_credit_v1' AND tgenabled IN ('O','A'));
 v_balances:=
  NOT EXISTS(SELECT 1 FROM public.purchases p WHERE ABS(
   COALESCE(p.due_amount,0)-GREATEST(p.total-p.paid_amount-p.credit_amount,0))>0.01)
  AND NOT EXISTS(SELECT 1 FROM public.supplier_payment_allocations a
    JOIN public.supplier_payments sp ON sp.id=a.payment_id JOIN public.purchases p ON p.id=a.purchase_id
    WHERE sp.supplier_id IS DISTINCT FROM p.supplier_id OR sp.currency IS DISTINCT FROM p.currency OR a.currency IS DISTINCT FROM p.currency)
  AND NOT EXISTS(SELECT 1 FROM public.cashbox_entries WHERE currency='SYP' AND amount_syp IS DISTINCT FROM amount)
  AND NOT EXISTS(SELECT 1 FROM public.purchases WHERE currency='USD' AND (fx_rate<=1 OR total_syp IS NULL))
  AND NOT EXISTS(SELECT 1 FROM public.supplier_payments WHERE currency='USD' AND (fx_rate<=1 OR amount_syp IS NULL))
  AND NOT EXISTS(SELECT 1 FROM public.returns WHERE currency='USD' AND amount_syp IS NULL)
  AND NOT EXISTS(SELECT 1 FROM public.supplier_refund_receipts WHERE currency='USD' AND (fx_rate<=1 OR amount_syp IS NULL));
 RETURN jsonb_build_object('ready',v_writes AND v_reads AND v_columns AND v_triggers AND v_balances AND v_rate>1,
  'writes',v_writes,'reads',v_reads,'columns',v_columns,'guards',v_triggers,
  'balances',v_balances,'rate_valid',COALESCE(v_rate>1,false),
  'usd_supplier_returns_supported',v_writes AND v_triggers,
  'supplier_refunds_supported',v_writes AND v_columns);
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_backend_contract_v1() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_backend_contract_v1() TO authenticated;


-- PHASE 20_DASHBOARD_CASHBOX_COMPATIBILITY.sql
-- V6.4.34: daily drilldown and old cashbox calls normalized to Syrian pounds.
-- Use only after currency schema, 06 reports and 17 read models.
-- No existing business rows are modified by this file.

CREATE OR REPLACE FUNCTION public.admin_cashbox_summary(
 p_start timestamptz DEFAULT NULL,p_end timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
 SELECT public.admin_cashbox_summary_v2(p_start,p_end);
$fn$;

-- Never auto-create cashbook rows as a side-effect of visiting Cashbox with cached/old UI.
-- A separately reviewed, explicit historical reconciliation is required to backfill records.
CREATE OR REPLACE FUNCTION public.admin_cashbox_reconcile()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 RETURN jsonb_build_object('sales_added',0,'debt_payments_added',0,
  'customer_returns_added',0,'supplier_payments_added',0,
  'automatic_reconciliation_disabled',true);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.admin_dashboard_day_details(p_start timestamptz,p_end timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v jsonb;f jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid dashboard day range'; END IF;
 f:=public.admin_dashboard_financial_summary(p_start,p_end);
 SELECT jsonb_build_object(
  'period',jsonb_build_object('start',p_start,'end',p_end),'summary',f,
  'sales',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,
   'invoice_number',s.id::text,'total',COALESCE(s.total_syp,s.total),
   'currency',s.currency,'payment_method',s.payment_method,
   'paid_amount',CASE WHEN s.currency='USD' THEN s.paid_amount*s.fx_rate ELSE s.paid_amount END,
   'due_amount',CASE WHEN s.currency='USD' THEN s.due_amount*s.fx_rate ELSE s.due_amount END,
   'debtor_name',d.name,'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'product_name',p.name,'barcode',p.barcode,'quantity',si.quantity,
    'unit_price',si.unit_price,'base_unit_price',si.base_unit_price,
    'line_total',si.quantity*si.unit_price) ORDER BY p.name)
    FROM public.sale_items si LEFT JOIN public.products p ON p.id=si.product_id WHERE si.sale_id=s.id),'[]'::jsonb)
   ) ORDER BY s.created_at DESC) FROM public.sales s LEFT JOIN public.debtors d ON d.id=s.debtor_id
   WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),  'purchases',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,
   'invoice_number',p.invoice_number,'supplier_name',sp.name,
   'total',COALESCE(p.total_syp,p.total),'original_total',p.total,
   'paid_amount',CASE WHEN p.currency='USD' THEN ROUND(p.paid_amount*p.fx_rate,2) ELSE p.paid_amount END,
   'due_amount',CASE WHEN p.currency='USD' THEN ROUND(p.due_amount*p.fx_rate,2) ELSE p.due_amount END,
   'currency',p.currency,'fx_rate',p.fx_rate,'payment_status',p.payment_status,
   'item_count',(SELECT COUNT(*) FROM public.purchase_items pi WHERE pi.purchase_id=p.id),
   'bonus_quantity',(SELECT COALESCE(SUM(pi2.bonus_quantity),0) FROM public.purchase_items pi2 WHERE pi2.purchase_id=p.id))
   ORDER BY p.created_at DESC) FROM public.purchases p LEFT JOIN public.suppliers sp ON sp.id=p.supplier_id
   WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb),
  'cashbox',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,
    'type',c.entry_type,'amount',COALESCE(c.amount_syp,c.amount),'original_amount',c.amount,
    'currency',c.currency,'description',c.description) ORDER BY c.created_at DESC)
    FROM public.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb),
  'returns',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,
    'type',r.return_type,'product_name',pr.name,'quantity',r.quantity,
    'amount',COALESCE(r.amount_syp,r.amount),'original_amount',r.amount,'currency',r.currency,'reason',r.reason)
    ORDER BY r.created_at DESC) FROM public.returns r LEFT JOIN public.products pr ON pr.id=r.product_id
    WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb),
  'debtor_payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,
    'debtor_name',d.name,'amount',COALESCE(t.amount_syp,t.credit),
    'payment_method',t.payment_method,'notes',t.notes) ORDER BY t.created_at DESC)
    FROM public.debtor_transactions t JOIN public.debtors d ON d.id=t.debtor_id
    WHERE t.transaction_type='payment' AND t.created_at>=p_start AND t.created_at<p_end),'[]'::jsonb),
  'orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'created_at',o.created_at,
    'public_code',o.public_code,'customer_name',c.name,'customer_phone',c.phone,
    'status',o.status,'total',o.total) ORDER BY o.created_at DESC)
    FROM public.orders o LEFT JOIN public.customers c ON c.id=o.customer_id
    WHERE o.created_at>=p_start AND o.created_at<p_end),'[]'::jsonb),
  'prescriptions',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pr.id,'created_at',pr.created_at,
    'customer_name',pr.customer_name,'customer_phone',pr.customer_phone,'status',pr.status,
    'file_name',pr.file_name) ORDER BY pr.created_at DESC)
    FROM public.prescriptions pr WHERE pr.created_at>=p_start AND pr.created_at<p_end),'[]'::jsonb),
  'supplier_payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',sp.id,'created_at',sp.created_at,
    'supplier_name',s.name,'amount',COALESCE(sp.amount_syp,sp.amount),
    'original_amount',sp.amount,'currency',sp.currency,'payment_method',sp.payment_method,
    'notes',sp.notes) ORDER BY sp.created_at DESC)
    FROM public.supplier_payments sp JOIN public.suppliers s ON s.id=sp.supplier_id
    WHERE sp.created_at>=p_start AND sp.created_at<p_end),'[]'::jsonb)
 ) INTO v;
 RETURN v;
END;
$fn$;

-- FINAL NO-DATA-MUTATION CHECKS
DO $postcheck$
BEGIN
 IF EXISTS (SELECT 1 FROM public.purchases p WHERE abs(p.due_amount-GREATEST(p.total-p.paid_amount-p.credit_amount,0))>0.01) THEN
  RAISE EXCEPTION 'ABORT: purchase ledgers inconsistent after migration'; END IF;
 IF EXISTS (SELECT 1 FROM public.supplier_payment_allocations a JOIN public.purchases p ON p.id=a.purchase_id JOIN public.supplier_payments sp ON sp.id=a.payment_id
   WHERE a.currency IS DISTINCT FROM p.currency OR a.currency IS DISTINCT FROM sp.currency OR sp.supplier_id IS DISTINCT FROM p.supplier_id) THEN
  RAISE EXCEPTION 'ABORT: cross-currency/supplier allocations found'; END IF;
 IF EXISTS(SELECT 1 FROM public.cashbox_entries WHERE currency='SYP' AND amount_syp IS DISTINCT FROM amount) THEN
  RAISE EXCEPTION 'ABORT: historical SYP cashbox missing converted values'; END IF;
END;
$postcheck$;