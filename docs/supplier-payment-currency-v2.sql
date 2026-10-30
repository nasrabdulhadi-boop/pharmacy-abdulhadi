-- Additive migration. Prepared for review; never applied to production in this task.
-- amount/currency remain the debt settlement. tender_* describe actual money paid.
ALTER TABLE public.supplier_payments
 ADD COLUMN IF NOT EXISTS tender_currency text,
 ADD COLUMN IF NOT EXISTS tender_amount numeric,
 ADD COLUMN IF NOT EXISTS tender_fx_rate numeric,
 ADD COLUMN IF NOT EXISTS payment_request_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS supplier_payment_request_unique
 ON public.supplier_payments(payment_request_id) WHERE payment_request_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.admin_record_supplier_payment_currency_v2(
 p_supplier_id uuid, p_amount numeric, p_debt_currency text, p_tender_currency text,
 p_fx_rate numeric, p_request_id uuid, p_purchase_id uuid DEFAULT NULL,
 p_payment_method text DEFAULT 'cash', p_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
 v_settled numeric; v_before numeric; v_after numeric; v_left numeric; v_part numeric;
 v_id uuid:=gen_random_uuid(); v_cash uuid; v_name text; v_rate numeric;
 v_syp numeric; v_existing public.supplier_payments; r record;
BEGIN
 IF auth.uid() IS NULL OR NOT COALESCE(public.is_admin(),false) THEN
  RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_debt_currency IS NULL OR p_tender_currency IS NULL OR
    p_debt_currency NOT IN ('USD','SYP') OR p_tender_currency NOT IN ('USD','SYP') THEN
  RAISE EXCEPTION 'عملة الدين أو الدفع غير صالحة'; END IF;
 IF p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<=0 OR p_amount<>round(p_amount,2) THEN
  RAISE EXCEPTION 'أدخل مبلغاً موجباً بمنزلتين عشريتين كحد أقصى'; END IF;
 IF p_fx_rate IS NULL OR p_fx_rate::text IN ('NaN','Infinity','-Infinity') OR p_fx_rate<=0 THEN
  RAISE EXCEPTION 'سعر الصرف غير صالح'; END IF;
 IF p_request_id IS NULL OR p_payment_method IS NULL OR p_payment_method NOT IN ('cash','other') THEN
  RAISE EXCEPTION 'بيانات الدفعة غير مكتملة'; END IF;
 IF p_notes IS NULL OR p_notes !~ E'(^|\n)رقم وصل الاستلام: [^[:space:]]' THEN
  RAISE EXCEPTION 'رقم وصل الاستلام إجباري'; END IF;
 -- Serialize retries even when the supplier changes; then serialize supplier settlements.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text,0));
 SELECT * INTO v_existing FROM public.supplier_payments WHERE payment_request_id=p_request_id;
 IF FOUND THEN
  IF v_existing.created_by IS DISTINCT FROM auth.uid() OR v_existing.supplier_id IS DISTINCT FROM p_supplier_id
   OR v_existing.tender_amount IS DISTINCT FROM p_amount OR v_existing.currency IS DISTINCT FROM p_debt_currency
   OR v_existing.tender_currency IS DISTINCT FROM p_tender_currency OR v_existing.tender_fx_rate IS DISTINCT FROM p_fx_rate
   OR v_existing.payment_method IS DISTINCT FROM p_payment_method OR v_existing.notes IS DISTINCT FROM p_notes
   OR (SELECT details->>'purchase_id' FROM public.audit_logs WHERE entity_id=v_existing.id
       AND action='supplier_payment_currency_v2' LIMIT 1) IS DISTINCT FROM p_purchase_id::text THEN
   RAISE EXCEPTION 'معرّف الدفعة مستخدم لعملية أخرى'; END IF;
  RETURN jsonb_build_object('payment_id',v_existing.id,'duplicate',true,'cashbox_entry_id',v_existing.cashbox_entry_id);
 END IF;
 SELECT name INTO v_name FROM public.suppliers WHERE id=p_supplier_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 -- The selected exchange rate is a snapshot; changing settings never revalues this payment.
 v_rate:=CASE WHEN p_debt_currency='USD' THEN p_fx_rate ELSE 1 END;
 v_settled:=CASE WHEN p_debt_currency=p_tender_currency THEN p_amount
  WHEN p_debt_currency='USD' THEN round(p_amount/p_fx_rate,6)
  ELSE round(p_amount*p_fx_rate,6) END;
 IF v_settled<=0 THEN RAISE EXCEPTION 'الدفعة أصغر من دقة التسوية'; END IF;
 v_syp:=CASE WHEN p_tender_currency='SYP' THEN p_amount ELSE round(p_amount*p_fx_rate,2) END;
 SELECT COALESCE(sum(due_amount),0) INTO v_before FROM public.purchases
  WHERE supplier_id=p_supplier_id AND currency=p_debt_currency;
 IF v_settled>v_before THEN RAISE EXCEPTION 'الدفعة تتجاوز الدين المستحق'; END IF;
 IF p_purchase_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.purchases
  WHERE id=p_purchase_id AND supplier_id=p_supplier_id AND currency=p_debt_currency AND due_amount>=v_settled) THEN
  RAISE EXCEPTION 'الفاتورة لا تطابق المورد أو العملة أو المتبقي'; END IF;
 INSERT INTO public.supplier_payments(id,supplier_id,amount,currency,fx_rate,amount_syp,
  payment_method,notes,created_by,tender_currency,tender_amount,tender_fx_rate,payment_request_id)
 VALUES(v_id,p_supplier_id,v_settled,p_debt_currency,v_rate,
  CASE WHEN p_debt_currency='USD' THEN round(v_settled*v_rate,2) ELSE v_settled END,
  p_payment_method,p_notes,auth.uid(),p_tender_currency,p_amount,p_fx_rate,p_request_id);
 v_left:=v_settled;
 FOR r IN SELECT id,due_amount FROM public.purchases
  WHERE supplier_id=p_supplier_id AND currency=p_debt_currency AND due_amount>0
   AND (p_purchase_id IS NULL OR id=p_purchase_id)
  ORDER BY COALESCE(invoice_date,created_at::date),created_at,id FOR UPDATE
 LOOP
  EXIT WHEN v_left=0;
  v_part:=least(v_left,r.due_amount);
  INSERT INTO public.supplier_payment_allocations(payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
   VALUES(v_id,r.id,v_part,p_debt_currency,v_rate,
    CASE WHEN p_debt_currency='USD' THEN round(v_part*v_rate,2) ELSE v_part END);
  PERFORM public.admin_refresh_purchase_balance(r.id);
  v_left:=v_left-v_part;
 END LOOP;
 IF v_left<>0 THEN RAISE EXCEPTION 'تعذر توزيع كامل الدفعة'; END IF;
 IF p_payment_method='cash' THEN
  INSERT INTO public.cashbox_entries(entry_type,amount,currency,fx_rate,amount_syp,description,
   purchase_id,supplier_payment_id,created_by)
  VALUES('purchase_payment',-p_amount,p_tender_currency,
   CASE WHEN p_tender_currency='USD' THEN p_fx_rate ELSE 1 END,-v_syp,
   'دفعة للمورد: '||v_name||' — دفع '||p_amount||' '||p_tender_currency||
    ' — تسوية '||v_settled||' '||p_debt_currency||' — '||p_notes,
   p_purchase_id,v_id,auth.uid()) RETURNING id INTO v_cash;
  UPDATE public.supplier_payments SET cashbox_entry_id=v_cash WHERE id=v_id;
 END IF;
 SELECT COALESCE(sum(due_amount),0) INTO v_after FROM public.purchases
  WHERE supplier_id=p_supplier_id AND currency=p_debt_currency;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'supplier_payment_currency_v2','supplier_payment',v_id,
  jsonb_build_object('supplier_id',p_supplier_id,'purchase_id',p_purchase_id,'debt_currency',p_debt_currency,
   'settled_amount',v_settled,'tender_currency',p_tender_currency,'tender_amount',p_amount,
   'fx_rate',p_fx_rate,'actual_amount_syp',v_syp,'previous_debt',v_before,'new_debt',v_after,
   'cashbox_entry_id',v_cash,'request_id',p_request_id));
 RETURN jsonb_build_object('payment_id',v_id,'cashbox_entry_id',v_cash,'settled_amount',v_settled,
  'tender_amount',p_amount,'tender_currency',p_tender_currency,'previous_debt',v_before,'new_debt',v_after);
END $$;
REVOKE ALL ON FUNCTION public.admin_record_supplier_payment_currency_v2(uuid,numeric,text,text,numeric,uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_record_supplier_payment_currency_v2(uuid,numeric,text,text,numeric,uuid,uuid,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
