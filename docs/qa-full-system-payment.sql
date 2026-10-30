-- Additive migration. Prepared for review; never applied to production in this task.
-- amount/currency remain the debt settlement. tender_* describe actual money paid.
ALTER TABLE pharmacy_supplier_stage.supplier_payments
 ADD COLUMN IF NOT EXISTS tender_currency text,
 ADD COLUMN IF NOT EXISTS tender_amount numeric,
 ADD COLUMN IF NOT EXISTS tender_fx_rate numeric,
 ADD COLUMN IF NOT EXISTS payment_request_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS supplier_payment_request_unique
 ON pharmacy_supplier_stage.supplier_payments(payment_request_id) WHERE payment_request_id IS NOT NULL;

CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_record_supplier_payment_currency_v2(
 p_supplier_id uuid, p_amount numeric, p_debt_currency text, p_tender_currency text,
 p_fx_rate numeric, p_request_id uuid, p_purchase_id uuid DEFAULT NULL,
 p_payment_method text DEFAULT 'cash', p_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
 v_settled numeric; v_before numeric; v_after numeric; v_left numeric; v_part numeric;
 v_id uuid:=gen_random_uuid(); v_cash uuid; v_name text; v_rate numeric;
 v_syp numeric; v_existing pharmacy_supplier_stage.supplier_payments; r record;
BEGIN
 IF auth.uid() IS NULL OR NOT COALESCE(pharmacy_supplier_stage.is_admin(),false) THEN
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
 SELECT * INTO v_existing FROM pharmacy_supplier_stage.supplier_payments WHERE payment_request_id=p_request_id;
 IF FOUND THEN
  IF v_existing.created_by IS DISTINCT FROM auth.uid() OR v_existing.supplier_id IS DISTINCT FROM p_supplier_id
   OR v_existing.tender_amount IS DISTINCT FROM p_amount OR v_existing.currency IS DISTINCT FROM p_debt_currency
   OR v_existing.tender_currency IS DISTINCT FROM p_tender_currency OR v_existing.tender_fx_rate IS DISTINCT FROM p_fx_rate
   OR v_existing.payment_method IS DISTINCT FROM p_payment_method OR v_existing.notes IS DISTINCT FROM p_notes
   OR (SELECT details->>'purchase_id' FROM pharmacy_supplier_stage.audit_logs WHERE entity_id=v_existing.id
       AND action='supplier_payment_currency_v2' LIMIT 1) IS DISTINCT FROM p_purchase_id::text THEN
   RAISE EXCEPTION 'معرّف الدفعة مستخدم لعملية أخرى'; END IF;
  RETURN jsonb_build_object('payment_id',v_existing.id,'duplicate',true,'cashbox_entry_id',v_existing.cashbox_entry_id);
 END IF;
 SELECT name INTO v_name FROM pharmacy_supplier_stage.suppliers WHERE id=p_supplier_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 -- The selected exchange rate is a snapshot; changing settings never revalues this payment.
 v_rate:=CASE WHEN p_debt_currency='USD' THEN p_fx_rate ELSE 1 END;
 v_settled:=CASE WHEN p_debt_currency=p_tender_currency THEN p_amount
  WHEN p_debt_currency='USD' THEN round(p_amount/p_fx_rate,6)
  ELSE round(p_amount*p_fx_rate,6) END;
 IF v_settled<=0 THEN RAISE EXCEPTION 'الدفعة أصغر من دقة التسوية'; END IF;
 v_syp:=CASE WHEN p_tender_currency='SYP' THEN p_amount ELSE round(p_amount*p_fx_rate,2) END;
 SELECT COALESCE(sum(due_amount),0) INTO v_before FROM pharmacy_supplier_stage.purchases
  WHERE supplier_id=p_supplier_id AND currency=p_debt_currency;
 IF v_settled>v_before THEN RAISE EXCEPTION 'الدفعة تتجاوز الدين المستحق'; END IF;
 IF p_purchase_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pharmacy_supplier_stage.purchases
  WHERE id=p_purchase_id AND supplier_id=p_supplier_id AND currency=p_debt_currency AND due_amount>=v_settled) THEN
  RAISE EXCEPTION 'الفاتورة لا تطابق المورد أو العملة أو المتبقي'; END IF;
 INSERT INTO pharmacy_supplier_stage.supplier_payments(id,supplier_id,amount,currency,fx_rate,amount_syp,
  payment_method,notes,created_by,tender_currency,tender_amount,tender_fx_rate,payment_request_id)
 VALUES(v_id,p_supplier_id,v_settled,p_debt_currency,v_rate,
  CASE WHEN p_debt_currency='USD' THEN round(v_settled*v_rate,2) ELSE v_settled END,
  p_payment_method,p_notes,auth.uid(),p_tender_currency,p_amount,p_fx_rate,p_request_id);
 v_left:=v_settled;
 FOR r IN SELECT id,due_amount FROM pharmacy_supplier_stage.purchases
  WHERE supplier_id=p_supplier_id AND currency=p_debt_currency AND due_amount>0
   AND (p_purchase_id IS NULL OR id=p_purchase_id)
  ORDER BY COALESCE(invoice_date,created_at::date),created_at,id FOR UPDATE
 LOOP
  EXIT WHEN v_left=0;
  v_part:=least(v_left,r.due_amount);
  INSERT INTO pharmacy_supplier_stage.supplier_payment_allocations(payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
   VALUES(v_id,r.id,v_part,p_debt_currency,v_rate,
    CASE WHEN p_debt_currency='USD' THEN round(v_part*v_rate,2) ELSE v_part END);
  PERFORM pharmacy_supplier_stage.admin_refresh_purchase_balance(r.id);
  v_left:=v_left-v_part;
 END LOOP;
 IF v_left<>0 THEN RAISE EXCEPTION 'تعذر توزيع كامل الدفعة'; END IF;
 IF p_payment_method='cash' THEN
  INSERT INTO pharmacy_supplier_stage.cashbox_entries(entry_type,amount,currency,fx_rate,amount_syp,description,
   purchase_id,supplier_payment_id,created_by)
  VALUES('purchase_payment',-p_amount,p_tender_currency,
   CASE WHEN p_tender_currency='USD' THEN p_fx_rate ELSE 1 END,-v_syp,
   'دفعة للمورد: '||v_name||' — دفع '||p_amount||' '||p_tender_currency||
    ' — تسوية '||v_settled||' '||p_debt_currency||' — '||p_notes,
   p_purchase_id,v_id,auth.uid()) RETURNING id INTO v_cash;
  UPDATE pharmacy_supplier_stage.supplier_payments SET cashbox_entry_id=v_cash WHERE id=v_id;
 END IF;
 SELECT COALESCE(sum(due_amount),0) INTO v_after FROM pharmacy_supplier_stage.purchases
  WHERE supplier_id=p_supplier_id AND currency=p_debt_currency;
 INSERT INTO pharmacy_supplier_stage.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'supplier_payment_currency_v2','supplier_payment',v_id,
  jsonb_build_object('supplier_id',p_supplier_id,'purchase_id',p_purchase_id,'debt_currency',p_debt_currency,
   'settled_amount',v_settled,'tender_currency',p_tender_currency,'tender_amount',p_amount,
   'fx_rate',p_fx_rate,'actual_amount_syp',v_syp,'previous_debt',v_before,'new_debt',v_after,
   'cashbox_entry_id',v_cash,'request_id',p_request_id));
 RETURN jsonb_build_object('payment_id',v_id,'cashbox_entry_id',v_cash,'settled_amount',v_settled,
  'tender_amount',p_amount,'tender_currency',p_tender_currency,'previous_debt',v_before,'new_debt',v_after);
END $$;
REVOKE ALL ON FUNCTION pharmacy_supplier_stage.admin_record_supplier_payment_currency_v2(uuid,numeric,text,text,numeric,uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION pharmacy_supplier_stage.admin_record_supplier_payment_currency_v2(uuid,numeric,text,text,numeric,uuid,uuid,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_currency_supplier_ledger_v1(p_supplier_id uuid, p_currency text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE v_currency text:=upper(COALESCE(p_currency,''));v jsonb;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF v_currency NOT IN ('USD','SYP') THEN RAISE EXCEPTION 'عملة المورد غير صالحة'; END IF;
 SELECT jsonb_build_object(
  'supplier',to_jsonb(s)||jsonb_build_object('currency',v_currency),
  'summary',jsonb_build_object(
   'invoice_total',COALESCE((SELECT SUM(total) FROM pharmacy_supplier_stage.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'paid_total',COALESCE((SELECT SUM(paid_amount) FROM pharmacy_supplier_stage.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'credit_total',COALESCE((SELECT SUM(credit_amount) FROM pharmacy_supplier_stage.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'balance',COALESCE((SELECT SUM(due_amount) FROM pharmacy_supplier_stage.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
   'refund_due',COALESCE((SELECT SUM(GREATEST(p.paid_amount+p.credit_amount-p.total-
     (SELECT COALESCE(SUM(sr.amount),0) FROM pharmacy_supplier_stage.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0))
     FROM pharmacy_supplier_stage.purchases p WHERE p.supplier_id=s.id AND p.currency=v_currency),0)),
  'invoices',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',p.id,'invoice_number',p.invoice_number,'invoice_date',p.invoice_date,
   'created_at',p.created_at,'total',p.total,'paid_amount',p.paid_amount,
   'credit_amount',p.credit_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,
   'currency',p.currency,'fx_rate',p.fx_rate,'notes',p.notes,'total_syp',CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END,
   'refunded_amount',(SELECT COALESCE(SUM(sr.amount),0) FROM pharmacy_supplier_stage.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),
   'refund_due',GREATEST(p.paid_amount+p.credit_amount-p.total-
    (SELECT COALESCE(SUM(sr.amount),0) FROM pharmacy_supplier_stage.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0),
   'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'product_name',pr.name,'barcode',pr.barcode,'quantity',pi.quantity,'bonus_quantity',pi.bonus_quantity,
    'purchase_price',pi.purchase_price,'purchase_price_syp',pi.purchase_price_syp,
    'sale_price',pi.sale_price,'sale_currency',pi.sale_price_currency,
    'expiry_date',pi.expiry_date,'batch_id',pi.batch_id))
    FROM pharmacy_supplier_stage.purchase_items pi JOIN pharmacy_supplier_stage.products pr ON pr.id=pi.product_id
    WHERE pi.purchase_id=p.id),'[]'::jsonb)) ORDER BY p.created_at DESC)
    FROM pharmacy_supplier_stage.purchases p WHERE p.supplier_id=s.id AND p.currency=v_currency),'[]'::jsonb),
  'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',sp.id,'amount',sp.amount,'currency',sp.currency,'fx_rate',sp.fx_rate,'amount_syp',sp.amount_syp,
   'tender_currency',COALESCE(sp.tender_currency,sp.currency),'tender_amount',COALESCE(sp.tender_amount,sp.amount),'tender_fx_rate',COALESCE(sp.tender_fx_rate,sp.fx_rate),'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
   'allocations',COALESCE((SELECT jsonb_agg(jsonb_build_object('purchase_id',a.purchase_id,'amount',a.amount,
    'invoice_number',p2.invoice_number)) FROM pharmacy_supplier_stage.supplier_payment_allocations a
    JOIN pharmacy_supplier_stage.purchases p2 ON p2.id=a.purchase_id WHERE a.payment_id=sp.id),'[]'::jsonb))
    ORDER BY sp.created_at DESC) FROM pharmacy_supplier_stage.supplier_payments sp
    WHERE sp.supplier_id=s.id AND sp.currency=v_currency),'[]'::jsonb),
  'credit_notes',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',r.id,'purchase_id',r.purchase_id,'invoice_number',p.invoice_number,'quantity',r.quantity,
   'amount',r.amount,'amount_syp',r.amount_syp,'currency',r.currency,'created_at',r.created_at,'reason',r.reason)
   ORDER BY r.created_at DESC) FROM pharmacy_supplier_stage.returns r JOIN pharmacy_supplier_stage.purchases p ON p.id=r.purchase_id
   WHERE r.return_type='supplier' AND p.supplier_id=s.id AND p.currency=v_currency),'[]'::jsonb),
  'refunds',COALESCE((SELECT jsonb_agg(jsonb_build_object(
   'id',sr.id,'purchase_id',sr.purchase_id,'amount',sr.amount,'amount_syp',sr.amount_syp,
   'currency',sr.currency,'fx_rate',sr.fx_rate,'created_at',sr.created_at,
   'payment_method',sr.payment_method,'notes',sr.notes)
   ORDER BY sr.created_at DESC) FROM pharmacy_supplier_stage.supplier_refund_receipts sr
   WHERE sr.supplier_id=s.id AND sr.currency=v_currency),'[]'::jsonb))
 INTO v FROM pharmacy_supplier_stage.suppliers s WHERE s.id=p_supplier_id;
 IF v IS NULL THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 RETURN v;
END;
$function$;

