-- Staging only. USD-only supplier settlement; existing SYP legacy function kept intact.
-- Invoice/payment balances are in USD; cashbox keeps USD native and amount_syp snapshot.
BEGIN;
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
 SELECT COALESCE(SUM(GREATEST(total-paid_amount,0)),0) INTO v_before
   FROM public.purchases WHERE supplier_id=p_supplier_id AND currency='USD';
 IF p_amount>v_before+0.0000001 THEN RAISE EXCEPTION 'الدفعة تتجاوز رصيد الدولار المستحق على المورد'; END IF;
 IF p_purchase_id IS NOT NULL THEN
   SELECT COALESCE(total-paid_amount,0) INTO v_debt FROM public.purchases
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
   FOR r IN SELECT id,GREATEST(total-paid_amount,0) AS due FROM public.purchases
    WHERE supplier_id=p_supplier_id AND currency='USD' AND GREATEST(total-paid_amount,0)>0
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
 SELECT COALESCE(SUM(GREATEST(total-paid_amount,0)),0) INTO v_after
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
COMMIT;
