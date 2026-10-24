-- Staging-only guard. Apply AFTER 01_SCHEMA_REVIEW_ONLY.sql and 02_GUARD_SUPPLIER_ALLOCATIONS_STAGING_ONLY.sql.
-- Preserves legacy RPC signature and SYP behavior, while preventing it from consuming USD invoices.
-- Do NOT run on production before isolated PostgreSQL integration tests and backup restoration validation.
BEGIN;
CREATE OR REPLACE FUNCTION public.admin_record_supplier_payment(
 p_supplier_id uuid, p_amount numeric, p_purchase_id uuid DEFAULT NULL,
 p_payment_method text DEFAULT 'cash', p_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE
 v_payment_id uuid:=gen_random_uuid(); v_cash_id uuid; v_left numeric:=p_amount;
 v_due numeric; v_alloc numeric; v_before numeric; v_after numeric; v_name text; r record;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'مبلغ الدفعة يجب أن يكون موجباً'; END IF;
 IF p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الدفع غير صالحة'; END IF;
 SELECT name INTO v_name FROM public.suppliers WHERE id=p_supplier_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 SELECT COALESCE(SUM(GREATEST(total-COALESCE(paid_amount,0),0)),0) INTO v_before
 FROM public.purchases WHERE supplier_id=p_supplier_id AND currency='SYP';
 IF p_amount>v_before+0.0000001 THEN RAISE EXCEPTION 'دفعة الليرة تتجاوز دين المورد بالليرة'; END IF;
 IF p_purchase_id IS NOT NULL THEN
  SELECT GREATEST(total-COALESCE(paid_amount,0),0) INTO v_due
  FROM public.purchases
  WHERE id=p_purchase_id AND supplier_id=p_supplier_id AND currency='SYP' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الفاتورة غير موجودة أو ليست بالليرة السورية لهذا المورد'; END IF;
  IF v_due<=0 THEN RAISE EXCEPTION 'الفاتورة مسددة'; END IF;
  IF p_amount>v_due+0.0000001 THEN RAISE EXCEPTION 'دفعة الليرة تتجاوز رصيد الفاتورة'; END IF;
 END IF;
 INSERT INTO public.supplier_payments(id,supplier_id,amount,payment_method,notes,created_by,currency,fx_rate,amount_syp)
 VALUES(v_payment_id,p_supplier_id,p_amount,p_payment_method,NULLIF(trim(COALESCE(p_notes,'')),''),auth.uid(),'SYP',1,p_amount);
 IF p_purchase_id IS NOT NULL THEN
  INSERT INTO public.supplier_payment_allocations(payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
  VALUES(v_payment_id,p_purchase_id,p_amount,'SYP',1,p_amount);
  v_left:=0;
 ELSE
  FOR r IN SELECT id,GREATEST(total-COALESCE(paid_amount,0),0) due FROM public.purchases
   WHERE supplier_id=p_supplier_id AND currency='SYP'
    AND GREATEST(total-COALESCE(paid_amount,0),0)>0
   ORDER BY COALESCE(invoice_date,created_at::date),created_at,id FOR UPDATE
  LOOP
   EXIT WHEN v_left<=0;
   v_alloc:=LEAST(v_left,r.due);
   INSERT INTO public.supplier_payment_allocations(payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
   VALUES(v_payment_id,r.id,v_alloc,'SYP',1,v_alloc);
   v_left:=v_left-v_alloc;
  END LOOP;
  IF v_left>0.0000001 THEN RAISE EXCEPTION 'دفعة الليرة تتجاوز الرصيد المستحق'; END IF;
 END IF;
 FOR r IN SELECT DISTINCT purchase_id FROM public.supplier_payment_allocations WHERE payment_id=v_payment_id LOOP
  PERFORM public.admin_refresh_purchase_balance(r.purchase_id);
 END LOOP;
 IF p_payment_method='cash' THEN
  INSERT INTO public.cashbox_entries(entry_type,amount,description,purchase_id,supplier_payment_id,created_by,currency,fx_rate,amount_syp)
  VALUES('purchase_payment',-p_amount,'دفع للمورد بالليرة: '||v_name,p_purchase_id,v_payment_id,auth.uid(),'SYP',1,-p_amount)
  RETURNING id INTO v_cash_id;
  UPDATE public.supplier_payments SET cashbox_entry_id=v_cash_id WHERE id=v_payment_id;
 END IF;
 SELECT COALESCE(SUM(GREATEST(total-COALESCE(paid_amount,0),0)),0) INTO v_after
 FROM public.purchases WHERE supplier_id=p_supplier_id AND currency='SYP';
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'supplier_payment','supplier',p_supplier_id,
  jsonb_build_object('supplier_name',v_name,'amount',p_amount,'currency','SYP',
   'payment_method',p_payment_method,'purchase_id',p_purchase_id,
   'previous_debt',v_before,'new_debt',v_after,
   'cashbox_entry_id',v_cash_id,'notes',p_notes));
 RETURN jsonb_build_object('payment_id',v_payment_id,'amount',p_amount,'currency','SYP',
  'previous_debt',v_before,'new_debt',v_after,'cashbox_entry_id',v_cash_id);
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_record_supplier_payment(uuid,numeric,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_record_supplier_payment(uuid,numeric,uuid,text,text) TO authenticated;
COMMIT;
