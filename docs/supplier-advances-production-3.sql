SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90s';

CREATE TEMP TABLE ab_supplier_advance_guard(table_name text PRIMARY KEY,row_count bigint,fingerprint text) ON COMMIT DROP;
DO $guard$
DECLARE r record;v_count bigint;v_hash text;
BEGIN
 FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
  EXECUTE format('SELECT count(*),md5(COALESCE(string_agg(h,''''
   ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(t)::text) h FROM public.%I t)x',r.tablename) INTO v_count,v_hash;
  INSERT INTO ab_supplier_advance_guard VALUES(r.tablename,v_count,v_hash);
 END LOOP;
END $guard$;

CREATE FUNCTION public.admin_supplier_advance_totals_v1(p_start timestamptz DEFAULT NULL,p_end timestamptz DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.is_admin(),false) THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_start IS NOT NULL AND p_end IS NOT NULL AND p_end<=p_start THEN RAISE EXCEPTION 'فترة غير صالحة'; END IF;
 SELECT jsonb_object_agg(c.currency,jsonb_build_object(
  'balance',coalesce((SELECT sum(public.supplier_advance_remaining_v1(l.id)) FROM public.supplier_advance_lots l WHERE l.currency=c.currency),0),
  'created',coalesce((SELECT sum(l.amount) FROM public.supplier_advance_lots l WHERE l.currency=c.currency AND (p_start IS NULL OR l.created_at>=p_start) AND (p_end IS NULL OR l.created_at<p_end)),0),
  'used',coalesce((SELECT sum(a.amount) FROM public.supplier_advance_applications a JOIN public.supplier_advance_lots l ON l.id=a.lot_id WHERE l.currency=c.currency AND (p_start IS NULL OR a.created_at>=p_start) AND (p_end IS NULL OR a.created_at<p_end)),0)))
 INTO v FROM (VALUES('USD'),('SYP')) c(currency);
 RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.admin_supplier_advance_totals_v1(timestamptz,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_supplier_advance_totals_v1(timestamptz,timestamptz) TO authenticated;


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
 v:=v||jsonb_build_object('summary',(v->'summary')||jsonb_build_object('advance_credit',(public.admin_supplier_advance_summary_v1(p_supplier_id,v_currency)->>'advance_credit')::numeric,'net_balance',(v->'summary'->>'balance')::numeric-(public.admin_supplier_advance_summary_v1(p_supplier_id,v_currency)->>'advance_credit')::numeric),
 'advances',coalesce((SELECT jsonb_agg(jsonb_build_object('id',l.id,'payment_id',l.payment_id,'amount',l.amount,'remaining',public.supplier_advance_remaining_v1(l.id),'currency',l.currency,'created_at',l.created_at,'notes',sp.notes,'applications',coalesce((SELECT jsonb_agg(jsonb_build_object('purchase_id',a.purchase_id,'invoice_number',p.invoice_number,'amount',a.amount,'created_at',a.created_at)) FROM public.supplier_advance_applications a JOIN public.purchases p ON p.id=a.purchase_id WHERE a.lot_id=l.id),'[]'::jsonb)) ORDER BY l.created_at DESC) FROM public.supplier_advance_lots l JOIN public.supplier_payments sp ON sp.id=l.payment_id WHERE l.supplier_id=p_supplier_id AND l.currency=v_currency),'[]'::jsonb));
 v:=jsonb_set(v,'{payments}',coalesce((SELECT jsonb_agg(j||jsonb_build_object('settled_amount',coalesce((SELECT sum(a.amount) FROM public.supplier_payment_allocations a WHERE a.payment_id=(j->>'id')::uuid),0),'origin_purchase_id',(SELECT l.origin_purchase_id FROM public.supplier_advance_lots l WHERE l.payment_id=(j->>'id')::uuid),'advance_initial',coalesce((SELECT l.amount FROM public.supplier_advance_lots l WHERE l.payment_id=(j->>'id')::uuid),0),'advance_remaining',coalesce((SELECT public.supplier_advance_remaining_v1(l.id) FROM public.supplier_advance_lots l WHERE l.payment_id=(j->>'id')::uuid),0))) FROM jsonb_array_elements(v->'payments') j),'[]'::jsonb));
 RETURN v;
END;
$function$;
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
    'supplier_payment_allocation_mismatches',COALESCE((SELECT COUNT(*) FROM public.supplier_payments sp WHERE sp.payment_request_id IS NOT NULL AND (sp.amount IS DISTINCT FROM (coalesce((SELECT SUM(a.amount) FROM public.supplier_payment_allocations a WHERE a.payment_id=sp.id),0)+coalesce((SELECT public.supplier_advance_remaining_v1(l.id) FROM public.supplier_advance_lots l WHERE l.payment_id=sp.id),0)) OR EXISTS(SELECT 1 FROM public.supplier_payment_allocations a JOIN public.purchases p ON p.id=a.purchase_id WHERE a.payment_id=sp.id AND (p.supplier_id IS DISTINCT FROM sp.supplier_id OR p.currency IS DISTINCT FROM sp.currency)))),0),
    'supplier_advance_invalid_balances',coalesce((SELECT count(*) FROM public.supplier_advance_lots l JOIN public.supplier_payments sp ON sp.id=l.payment_id WHERE public.supplier_advance_remaining_v1(l.id)<0 OR sp.supplier_id IS DISTINCT FROM l.supplier_id OR sp.currency IS DISTINCT FROM l.currency OR EXISTS(SELECT 1 FROM public.supplier_advance_applications a JOIN public.purchases p ON p.id=a.purchase_id WHERE a.lot_id=l.id AND (p.supplier_id IS DISTINCT FROM l.supplier_id OR p.currency IS DISTINCT FROM l.currency))),0),
 'supplier_payments_without_allocations',COALESCE((SELECT COUNT(*) FROM public.supplier_payments sp WHERE NOT EXISTS(SELECT 1 FROM public.supplier_payment_allocations spa WHERE spa.payment_id=sp.id) AND NOT EXISTS(SELECT 1 FROM public.supplier_advance_lots l WHERE l.payment_id=sp.id)),0),
    'returns_without_stock_movement',COALESCE((SELECT COUNT(*) FROM public.returns r WHERE NOT EXISTS(SELECT 1 FROM public.stock_movements sm WHERE sm.product_id=r.product_id AND sm.movement_type=CASE WHEN r.return_type='customer' THEN 'customer_return' ELSE 'supplier_return' END AND sm.created_at BETWEEN r.created_at-interval '3 seconds' AND r.created_at+interval '3 seconds')),0),
    'purchase_balance_mismatches',COALESCE((SELECT COUNT(*) FROM public.purchases p WHERE ABS(COALESCE(p.paid_amount,0)-LEAST(COALESCE(p.total,0),COALESCE((SELECT SUM(spa.amount) FROM public.supplier_payment_allocations spa WHERE spa.purchase_id=p.id),0)))>0.01 OR ABS(COALESCE(p.due_amount,0)-GREATEST(COALESCE(p.total,0)-COALESCE(p.paid_amount,0)-COALESCE(p.credit_amount,0),0))>0.01),0),
    'cashbox_balance',COALESCE((SELECT SUM(COALESCE(amount_syp,amount)) FROM public.cashbox_entries),0),
    'supplier_debt',COALESCE((SELECT SUM(GREATEST(COALESCE(p.total,0)-COALESCE(p.paid_amount,0),0)) FROM public.purchases p),0),
    'debtor_debt',COALESCE((SELECT SUM(debit-credit) FROM public.debtor_transactions),0)
  ) INTO v;
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
   'id',sp.id,'amount',coalesce(a.amount,0),'advance_created',CASE WHEN ll.origin_purchase_id=p.id THEN ll.amount ELSE 0 END,'currency',sp.currency,'fx_rate',sp.fx_rate,
   'tender_currency',COALESCE(sp.tender_currency,sp.currency),'tender_amount',COALESCE(sp.tender_amount,sp.amount),'tender_fx_rate',COALESCE(sp.tender_fx_rate,sp.fx_rate),'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
   'from_advance',EXISTS(SELECT 1 FROM public.supplier_advance_applications aa JOIN public.supplier_advance_lots ll ON ll.id=aa.lot_id WHERE ll.payment_id=sp.id AND aa.purchase_id=p.id),'cashbox_entry_id',sp.cashbox_entry_id))
   FROM public.supplier_payments sp LEFT JOIN public.supplier_payment_allocations a ON a.payment_id=sp.id AND a.purchase_id=p.id LEFT JOIN public.supplier_advance_lots ll ON ll.payment_id=sp.id
   WHERE a.purchase_id=p.id OR ll.origin_purchase_id=p.id),'[]'::jsonb)) INTO v
 FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id WHERE p.id=p_purchase_id;
 RETURN v||jsonb_build_object('applied_advance',coalesce((SELECT sum(a.amount) FROM public.supplier_advance_applications a WHERE a.purchase_id=p_purchase_id),0),'advance_created',coalesce((SELECT sum(l.amount) FROM public.supplier_advance_lots l WHERE l.origin_purchase_id=p_purchase_id),0));
END;
$function$;


CREATE OR REPLACE FUNCTION public.admin_currency_supplier_debt_list_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.is_admin(),false) THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 WITH accounts AS (SELECT supplier_id,currency FROM public.purchases WHERE supplier_id IS NOT NULL UNION SELECT supplier_id,currency FROM public.supplier_advance_lots),
 rows AS (SELECT s.id,s.name,s.phone,s.address,a.currency,
  coalesce((SELECT sum(total) FROM public.purchases p WHERE p.supplier_id=s.id AND p.currency=a.currency),0) invoice_total,
  coalesce((SELECT sum(paid_amount) FROM public.purchases p WHERE p.supplier_id=s.id AND p.currency=a.currency),0) paid_total,
  coalesce((SELECT sum(credit_amount) FROM public.purchases p WHERE p.supplier_id=s.id AND p.currency=a.currency),0) credit_total,
  coalesce((SELECT sum(due_amount) FROM public.purchases p WHERE p.supplier_id=s.id AND p.currency=a.currency),0) balance,
  coalesce((SELECT sum(public.supplier_advance_remaining_v1(l.id)) FROM public.supplier_advance_lots l WHERE l.supplier_id=s.id AND l.currency=a.currency),0) advance_credit,
  coalesce((SELECT sum(greatest(p.paid_amount+p.credit_amount-p.total-(SELECT coalesce(sum(sr.amount),0) FROM public.supplier_refund_receipts sr WHERE sr.purchase_id=p.id),0)) FROM public.purchases p WHERE p.supplier_id=s.id AND p.currency=a.currency),0) refund_due,
  (SELECT count(*) FROM public.purchases p WHERE p.supplier_id=s.id AND p.currency=a.currency) invoice_count,
  (SELECT count(*) FROM public.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=a.currency) payment_count,
  (SELECT max(created_at) FROM public.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=a.currency) last_payment,
  (SELECT max(created_at) FROM public.purchases p WHERE p.supplier_id=s.id AND p.currency=a.currency) last_invoice
 FROM accounts a JOIN public.suppliers s ON s.id=a.supplier_id)
 SELECT coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('net_balance',r.balance-r.advance_credit) ORDER BY r.name,r.currency),'[]'::jsonb) INTO v FROM rows r;
 RETURN v;
END $$;


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
 )||jsonb_build_object('supplier_advances',public.admin_supplier_advance_totals_v1(p_start,p_end));
END;
$function$
;
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
  'supplier_advances',public.admin_supplier_advance_totals_v1(p_start,p_end),'period',jsonb_build_object('start',p_start,'end',p_end),
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
END; $function$
;

DO $guard$
DECLARE r record;v_count bigint;v_hash text;
BEGIN
 FOR r IN SELECT * FROM ab_supplier_advance_guard LOOP
  EXECUTE format('SELECT count(*),md5(COALESCE(string_agg(h,''''
   ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(t)::text) h FROM public.%I t)x',r.table_name) INTO v_count,v_hash;
  IF v_count IS DISTINCT FROM r.row_count OR v_hash IS DISTINCT FROM r.fingerprint THEN RAISE EXCEPTION 'Data preservation guard failed for %; migration aborted',r.table_name; END IF;
 END LOOP;
END $guard$;

NOTIFY pgrst,'reload schema';

