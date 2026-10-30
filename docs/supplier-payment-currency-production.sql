SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90s';

CREATE TEMP TABLE ab_supplier_currency_guard(table_name text PRIMARY KEY,row_count bigint,fingerprint text) ON COMMIT DROP;
DO $guard$
DECLARE r record;v_count bigint;v_hash text;
BEGIN
 FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
  EXECUTE format('SELECT count(*),md5(COALESCE(string_agg(h,''''
   ORDER BY h),'''')) FROM (SELECT md5((to_jsonb(t)-ARRAY[''tender_currency'',''tender_amount'',''tender_fx_rate'',''payment_request_id''])::text) h FROM public.%I t)x',r.tablename) INTO v_count,v_hash;
  INSERT INTO ab_supplier_currency_guard VALUES(r.tablename,v_count,v_hash);
 END LOOP;
END $guard$;
-- Additive supplier settlement migration; preserves every historical record.
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


ALTER TABLE public.supplier_payments ADD CONSTRAINT supplier_payment_tender_snapshot_v2 CHECK (
 (payment_request_id IS NULL AND tender_currency IS NULL AND tender_amount IS NULL AND tender_fx_rate IS NULL) OR
 (payment_request_id IS NOT NULL AND tender_currency IS NOT NULL AND tender_currency IN ('USD','SYP') AND tender_amount IS NOT NULL AND tender_fx_rate IS NOT NULL
  AND tender_amount>0 AND tender_amount::text NOT IN ('NaN','Infinity','-Infinity') AND tender_amount=ROUND(tender_amount,2)
  AND tender_fx_rate>0 AND tender_fx_rate::text NOT IN ('NaN','Infinity','-Infinity'))
) NOT VALID;
ALTER TABLE public.supplier_payments VALIDATE CONSTRAINT supplier_payment_tender_snapshot_v2;

CREATE OR REPLACE FUNCTION public.admin_currency_supplier_ledger_v1(p_supplier_id uuid, p_currency text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
   'tender_currency',COALESCE(sp.tender_currency,sp.currency),'tender_amount',COALESCE(sp.tender_amount,sp.amount),'tender_fx_rate',COALESCE(sp.tender_fx_rate,sp.fx_rate),'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
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
$function$;
CREATE OR REPLACE FUNCTION public.admin_currency_purchase_detail_v1(p_purchase_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
   'tender_currency',COALESCE(sp.tender_currency,sp.currency),'tender_amount',COALESCE(sp.tender_amount,sp.amount),'tender_fx_rate',COALESCE(sp.tender_fx_rate,sp.fx_rate),'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
   'cashbox_entry_id',sp.cashbox_entry_id))
   FROM public.supplier_payment_allocations a JOIN public.supplier_payments sp ON sp.id=a.payment_id
   WHERE a.purchase_id=p.id),'[]'::jsonb)) INTO v
 FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id WHERE p.id=p_purchase_id;
 RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION public.admin_dashboard_day_details(p_start timestamp with time zone, p_end timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
   WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
  'purchases',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,
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
    'original_amount',sp.amount,'currency',sp.currency,'tender_amount',COALESCE(sp.tender_amount,sp.amount),'tender_currency',COALESCE(sp.tender_currency,sp.currency),'settled_amount',sp.amount,'payment_method',sp.payment_method,
    'notes',sp.notes) ORDER BY sp.created_at DESC)
    FROM public.supplier_payments sp JOIN public.suppliers s ON s.id=sp.supplier_id
    WHERE sp.created_at>=p_start AND sp.created_at<p_end),'[]'::jsonb)
 ) INTO v;
 RETURN v;
END;
$function$;
CREATE OR REPLACE FUNCTION public.admin_dashboard_financial_summary(p_start timestamp with time zone, p_end timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
  'supplier_payments',COALESCE((SELECT SUM(CASE WHEN tender_currency='SYP' THEN tender_amount WHEN tender_currency='USD' THEN ROUND(tender_amount*tender_fx_rate,2) ELSE COALESCE(amount_syp,amount) END)
     FROM public.supplier_payments WHERE created_at>=p_start AND created_at<p_end),0),
  'orders_count',(SELECT COUNT(*) FROM public.orders WHERE created_at>=p_start AND created_at<p_end),
  'prescriptions_count',(SELECT COUNT(*) FROM public.prescriptions WHERE created_at>=p_start AND created_at<p_end)
 );
END;
$function$;
CREATE OR REPLACE FUNCTION public.admin_accounting_report(p_start timestamp with time zone, p_end timestamp with time zone, p_compare_start timestamp with time zone DEFAULT NULL::timestamp with time zone, p_compare_end timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE v jsonb; f jsonb; cf jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 f:=public.admin_dashboard_financial_summary(p_start,p_end);
 cf:=CASE WHEN p_compare_start IS NULL OR p_compare_end IS NULL THEN NULL ELSE public.admin_dashboard_financial_summary(p_compare_start,p_compare_end) END;
 SELECT jsonb_build_object(
  'period',jsonb_build_object('start',p_start,'end',p_end),
  'summary',jsonb_build_object('sales',COALESCE((f->>'sales')::numeric,0),'cash_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0),'credit_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),'debt_collections',COALESCE((f->>'debtor_payments')::numeric,0),'new_debt',COALESCE((SELECT SUM(debit) FROM public.debtor_transactions WHERE transaction_type='sale' AND created_at>=p_start AND created_at<p_end),0),'purchases',COALESCE((f->>'purchases')::numeric,0),'gross_profit',COALESCE((f->>'profit')::numeric,0),'return_profit',COALESCE((f->>'customer_return_cost')::numeric,0),'supplier_returns',COALESCE((SELECT SUM(COALESCE(amount_syp,amount)) FROM public.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end),0),'net_purchases',COALESCE((f->>'purchases')::numeric,0)-COALESCE((SELECT SUM(COALESCE(amount_syp,amount)) FROM public.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end),0),'profit',COALESCE((f->>'profit')::numeric,0),'margin',COALESCE((f->>'margin')::numeric,0),'cash_in',COALESCE((f->>'cash_in')::numeric,0),'cash_out',COALESCE((f->>'cash_out')::numeric,0),'cash_net',COALESCE((f->>'cash_net')::numeric,0),'cash_balance',COALESCE((SELECT SUM(COALESCE(amount_syp,amount)) FROM public.cashbox_entries),0),'outstanding_debt',COALESCE((SELECT SUM(debit-credit) FROM public.debtor_transactions),0),'sales_count',COALESCE((f->>'invoice_count')::bigint,0),'purchase_count',COALESCE((f->>'purchase_count')::bigint,0),'customer_returns',COALESCE((f->>'customer_returns')::numeric,0),'net_sales',COALESCE((f->>'net_sales')::numeric,0),'cost_of_goods',COALESCE((f->>'cost_of_goods')::numeric,0)),
  'comparison',CASE WHEN cf IS NULL THEN NULL ELSE jsonb_build_object('sales',COALESCE((cf->>'sales')::numeric,0),'net_sales',COALESCE((cf->>'net_sales')::numeric,0),'purchases',COALESCE((cf->>'purchases')::numeric,0),'profit',COALESCE((cf->>'profit')::numeric,0),'new_debt',COALESCE((SELECT SUM(debit) FROM public.debtor_transactions WHERE transaction_type='sale' AND created_at>=p_compare_start AND created_at<p_compare_end),0),'debt_collections',COALESCE((cf->>'debtor_payments')::numeric,0)) END,
  'sales_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,'total',s.total,'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount,'debtor_id',s.debtor_id,'debtor_name',d.name) ORDER BY s.created_at DESC) FROM public.sales s LEFT JOIN public.debtors d ON d.id=s.debtor_id WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
  'purchase_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,'supplier_name',s.name,'total',COALESCE(p.total_syp,p.total),'original_total',p.total,'currency',p.currency,'fx_rate',p.fx_rate,'bonus_quantity',COALESCE((SELECT SUM(pi.bonus_quantity) FROM public.purchase_items pi WHERE pi.purchase_id=p.id),0)) ORDER BY p.created_at DESC) FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb),
  'debt_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,'type',t.transaction_type,'debtor_name',d.name,'amount',t.amount,'debit',t.debit,'credit',t.credit,'notes',t.notes) ORDER BY t.created_at DESC) FROM public.debtor_transactions t JOIN public.debtors d ON d.id=t.debtor_id WHERE t.created_at>=p_start AND t.created_at<p_end),'[]'::jsonb),
  'cash_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,'type',c.entry_type,'amount',COALESCE(c.amount_syp,c.amount),'original_amount',c.amount,'currency',c.currency,'fx_rate',c.fx_rate,'description',c.description) ORDER BY c.created_at DESC) FROM public.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb),
  'return_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',p.name,'quantity',r.quantity,'amount',r.amount,'reason',r.reason) ORDER BY r.created_at DESC) FROM public.returns r LEFT JOIN public.products p ON p.id=r.product_id WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb),
  'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_id',x.product_id,'product_name',x.product_name,'quantity',x.quantity,'sales',x.sales,'cost',x.cost,'gross_profit',x.gross_profit,'return_amount',x.return_amount,'return_profit',x.return_profit,'net_sales',x.sales-x.return_amount,'net_profit',x.gross_profit-x.return_profit) ORDER BY (x.sales-x.return_amount) DESC) FROM (SELECT p.id product_id,p.name product_name,SUM(si.quantity) quantity,SUM(si.quantity*si.unit_price) sales,SUM(si.quantity*si.unit_cost) cost,SUM(si.quantity*(si.unit_price-si.unit_cost)) gross_profit,COALESCE((SELECT SUM(r.amount) FROM public.returns r WHERE r.return_type='customer' AND r.product_id=p.id AND r.created_at>=p_start AND r.created_at<p_end),0) return_amount,COALESCE((SELECT SUM(r.quantity*(si2.unit_price-si2.unit_cost)) FROM public.returns r JOIN public.sale_items si2 ON si2.id=r.sale_item_id WHERE r.return_type='customer' AND r.product_id=p.id AND r.created_at>=p_start AND r.created_at<p_end),0) return_profit FROM public.sale_items si JOIN public.products p ON p.id=si.product_id JOIN public.sales s ON s.id=si.sale_id WHERE s.created_at>=p_start AND s.created_at<p_end GROUP BY p.id,p.name) x),'[]'::jsonb),
  'checks',jsonb_build_object('sales_split_delta',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),'sales_item_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end AND ABS(COALESCE((SELECT SUM(si.quantity*si.unit_price) FROM public.sale_items si WHERE si.sale_id=s.id),0)-(COALESCE(s.total,0)+COALESCE(s.discount,0)))>0.01),0),'customer_return_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end AND r.quantity>(si.quantity+0.000001)),0),'supplier_return_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.returns r JOIN public.purchase_items pi ON pi.id=(SELECT b2.purchase_item_id FROM public.batches b2 WHERE b2.id=r.batch_id) WHERE r.return_type='supplier' AND r.created_at>=p_start AND r.created_at<p_end AND r.quantity>(pi.quantity+pi.bonus_quantity+0.000001)),0),'cash_delta',0)
 ) INTO v;
 RETURN v;
END; $function$;
CREATE OR REPLACE FUNCTION public.admin_financial_integrity_check()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE v jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT jsonb_build_object(
    'missing_cash_sales',COALESCE((SELECT COUNT(*) FROM public.sales s WHERE s.payment_method='cash' AND COALESCE(s.total,0)>0 AND NOT EXISTS(SELECT 1 FROM public.cashbox_entries c WHERE c.sale_id=s.id AND c.entry_type='sale_cash')),0),
    'missing_cash_debtor_payments',COALESCE((SELECT COUNT(*) FROM public.debtor_transactions t WHERE t.transaction_type='payment' AND t.payment_method='cash' AND t.credit>0 AND NOT EXISTS(SELECT 1 FROM public.cashbox_entries c WHERE c.debtor_transaction_id=t.id AND c.entry_type='debtor_payment')),0),
    'missing_cash_supplier_payments',COALESCE((SELECT COUNT(*) FROM public.supplier_payments sp WHERE sp.payment_method='cash' AND sp.amount>0 AND NOT EXISTS(SELECT 1 FROM public.cashbox_entries c WHERE c.supplier_payment_id=sp.id AND c.entry_type='purchase_payment')),0),
    'missing_customer_refunds',COALESCE((SELECT COUNT(*) FROM public.returns r JOIN public.sales s ON s.id=r.sale_id WHERE r.return_type='customer' AND s.payment_method='cash' AND r.amount>0 AND NOT EXISTS(SELECT 1 FROM public.cashbox_entries c WHERE c.sale_id=r.sale_id AND c.entry_type='customer_return_refund' AND c.created_at BETWEEN r.created_at-interval '2 seconds' AND r.created_at+interval '2 seconds')),0),
    'sales_without_items',COALESCE((SELECT COUNT(*) FROM public.sales s WHERE NOT EXISTS(SELECT 1 FROM public.sale_items si WHERE si.sale_id=s.id)),0),
    'purchases_without_items',COALESCE((SELECT COUNT(*) FROM public.purchases p WHERE NOT EXISTS(SELECT 1 FROM public.purchase_items pi WHERE pi.purchase_id=p.id)),0),
    'supplier_payment_cash_mismatches',COALESCE((SELECT COUNT(*) FROM public.supplier_payments sp WHERE sp.payment_request_id IS NOT NULL AND ((sp.payment_method='cash' AND NOT EXISTS(SELECT 1 FROM public.cashbox_entries c WHERE c.id=sp.cashbox_entry_id AND c.supplier_payment_id=sp.id AND c.entry_type='purchase_payment' AND c.currency=sp.tender_currency AND c.amount=-sp.tender_amount AND c.amount_syp=-CASE WHEN sp.tender_currency='SYP' THEN sp.tender_amount ELSE ROUND(sp.tender_amount*sp.tender_fx_rate,2) END)) OR (sp.payment_method<>'cash' AND sp.cashbox_entry_id IS NOT NULL))),0),
    'supplier_payment_allocation_mismatches',COALESCE((SELECT COUNT(*) FROM public.supplier_payments sp WHERE sp.payment_request_id IS NOT NULL AND (sp.amount IS DISTINCT FROM (SELECT SUM(a.amount) FROM public.supplier_payment_allocations a WHERE a.payment_id=sp.id) OR EXISTS(SELECT 1 FROM public.supplier_payment_allocations a JOIN public.purchases p ON p.id=a.purchase_id WHERE a.payment_id=sp.id AND (p.supplier_id IS DISTINCT FROM sp.supplier_id OR p.currency IS DISTINCT FROM sp.currency)))),0),
    'supplier_payments_without_allocations',COALESCE((SELECT COUNT(*) FROM public.supplier_payments sp WHERE NOT EXISTS(SELECT 1 FROM public.supplier_payment_allocations spa WHERE spa.payment_id=sp.id)),0),
    'returns_without_stock_movement',COALESCE((SELECT COUNT(*) FROM public.returns r WHERE NOT EXISTS(SELECT 1 FROM public.stock_movements sm WHERE sm.product_id=r.product_id AND sm.movement_type=CASE WHEN r.return_type='customer' THEN 'customer_return' ELSE 'supplier_return' END AND sm.created_at BETWEEN r.created_at-interval '3 seconds' AND r.created_at+interval '3 seconds')),0),
    'purchase_balance_mismatches',COALESCE((SELECT COUNT(*) FROM public.purchases p WHERE ABS(COALESCE(p.paid_amount,0)-LEAST(COALESCE(p.total,0),COALESCE((SELECT SUM(spa.amount) FROM public.supplier_payment_allocations spa WHERE spa.purchase_id=p.id),0)))>0.01 OR ABS(COALESCE(p.due_amount,0)-GREATEST(COALESCE(p.total,0)-COALESCE(p.paid_amount,0)-COALESCE(p.credit_amount,0),0))>0.01),0),
    'cashbox_balance',COALESCE((SELECT SUM(COALESCE(amount_syp,amount)) FROM public.cashbox_entries),0),
    'supplier_debt',COALESCE((SELECT SUM(GREATEST(COALESCE(p.total,0)-COALESCE(p.paid_amount,0),0)) FROM public.purchases p),0),
    'debtor_debt',COALESCE((SELECT SUM(debit-credit) FROM public.debtor_transactions),0)
  ) INTO v;
  RETURN v;
END;
$function$;
DO $guard$
DECLARE r record;v_count bigint;v_hash text;
BEGIN
 FOR r IN SELECT * FROM ab_supplier_currency_guard LOOP
  EXECUTE format('SELECT count(*),md5(COALESCE(string_agg(h,''''
   ORDER BY h),'''')) FROM (SELECT md5((to_jsonb(t)-ARRAY[''tender_currency'',''tender_amount'',''tender_fx_rate'',''payment_request_id''])::text) h FROM public.%I t)x',r.table_name) INTO v_count,v_hash;
  IF v_count IS DISTINCT FROM r.row_count OR v_hash IS DISTINCT FROM r.fingerprint THEN RAISE EXCEPTION 'Data preservation guard failed for %; migration aborted',r.table_name; END IF;
 END LOOP;
END $guard$;

NOTIFY pgrst,'reload schema';

