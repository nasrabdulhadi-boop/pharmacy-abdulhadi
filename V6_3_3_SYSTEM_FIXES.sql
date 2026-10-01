-- Pharmacy Abdelhadi V6.3.3 — focused backend fixes for cashbox, dashboard day details,
-- and smart-inventory product sales snapshot.
-- This patch does NOT drop or delete existing application functions.
-- Run once in Supabase SQL Editor.
BEGIN;

-- 1) Make sure all cashbox entry types used by the application are accepted.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.conname
    FROM pg_constraint c
    WHERE c.conrelid='public.cashbox_entries'::regclass
      AND c.contype='c'
      AND pg_get_constraintdef(c.oid) ILIKE '%entry_type%'
  LOOP
    EXECUTE format('ALTER TABLE public.cashbox_entries DROP CONSTRAINT IF EXISTS %I',r.conname);
  END LOOP;
END $$;

ALTER TABLE public.cashbox_entries
  ADD CONSTRAINT cashbox_entries_entry_type_check
  CHECK (entry_type IN (
    'sale_cash','debtor_payment','expense','income','purchase_payment',
    'withdrawal','deposit','adjustment','customer_return_refund'
  ));

-- 2) A dedicated manual-cashbox RPC. Keeps the old function intact while giving
-- the current UI a single, explicit endpoint for manual movements.
CREATE OR REPLACE FUNCTION public.admin_cashbox_manual_entry(
  p_type text,
  p_amount numeric,
  p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE v_id uuid; v_amount numeric;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_type NOT IN ('expense','income','withdrawal','deposit','adjustment') THEN
    RAISE EXCEPTION 'نوع حركة صندوق غير صالح';
  END IF;
  IF COALESCE(p_amount,0)<=0 THEN RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر'; END IF;

  v_amount:=CASE WHEN p_type IN ('expense','withdrawal') THEN -abs(p_amount) ELSE abs(p_amount) END;

  INSERT INTO public.cashbox_entries(entry_type,amount,description,created_by)
  VALUES(p_type,v_amount,NULLIF(trim(COALESCE(p_description,'')),''),auth.uid())
  RETURNING id INTO v_id;

  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'cashbox_entry','cashbox',v_id,
    jsonb_build_object('type',p_type,'amount',abs(p_amount),'signed_amount',v_amount,'description',p_description));

  RETURN jsonb_build_object('id',v_id,'type',p_type,'amount',v_amount);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_cashbox_manual_entry(text,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cashbox_manual_entry(text,numeric,text) TO authenticated;

-- 3) Full daily activity endpoint for the dashboard.
CREATE OR REPLACE FUNCTION public.admin_dashboard_day_details(
  p_start timestamptz,
  p_end timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE v jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN
    RAISE EXCEPTION 'Invalid dashboard day range';
  END IF;

  SELECT jsonb_build_object(
    'period',jsonb_build_object('start',p_start,'end',p_end),
    'summary',jsonb_build_object(
      'sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0),
      'invoice_count',COALESCE((SELECT COUNT(*) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0),
      'cash_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0),
      'credit_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),
      'profit',COALESCE((SELECT SUM((unit_price-unit_cost)*quantity) FROM public.sale_items WHERE created_at>=p_start AND created_at<p_end),0),
      'purchases',COALESCE((SELECT SUM(total) FROM public.purchases WHERE created_at>=p_start AND created_at<p_end),0),
      'purchase_count',COALESCE((SELECT COUNT(*) FROM public.purchases WHERE created_at>=p_start AND created_at<p_end),0),
      'customer_returns',COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='customer' AND created_at>=p_start AND created_at<p_end),0),
      'supplier_returns',COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end),0),
      'cash_in',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE amount>0 AND created_at>=p_start AND created_at<p_end),0),
      'cash_out',COALESCE((SELECT SUM(-amount) FROM public.cashbox_entries WHERE amount<0 AND created_at>=p_start AND created_at<p_end),0),
      'cash_net',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE created_at>=p_start AND created_at<p_end),0),
      'debtor_payments',COALESCE((SELECT SUM(credit) FROM public.debtor_transactions WHERE transaction_type='payment' AND created_at>=p_start AND created_at<p_end),0),
      'supplier_payments',COALESCE((SELECT SUM(amount) FROM public.supplier_payments WHERE created_at>=p_start AND created_at<p_end),0),
      'orders_count',COALESCE((SELECT COUNT(*) FROM public.orders WHERE created_at>=p_start AND created_at<p_end),0),
      'prescriptions_count',COALESCE((SELECT COUNT(*) FROM public.prescriptions WHERE created_at>=p_start AND created_at<p_end),0)
    ),
    'sales',COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',s.id,'created_at',s.created_at,'invoice_number',s.id::text,
        'total',s.total,'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount,
        'debtor_name',d.name,
        'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'product_name',p.name,'barcode',p.barcode,'quantity',si.quantity,
          'unit_price',si.unit_price,'line_total',si.quantity*si.unit_price
        ) ORDER BY p.name) FROM public.sale_items si LEFT JOIN public.products p ON p.id=si.product_id WHERE si.sale_id=s.id),'[]'::jsonb)
      ) ORDER BY s.created_at DESC)
      FROM public.sales s LEFT JOIN public.debtors d ON d.id=s.debtor_id
      WHERE s.created_at>=p_start AND s.created_at<p_end
    ),'[]'::jsonb),
    'purchases',COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,
        'supplier_name',sp.name,'total',p.total,'paid_amount',p.paid_amount,'due_amount',p.due_amount,
        'payment_status',p.payment_status,'item_count',(SELECT COUNT(*) FROM public.purchase_items pi WHERE pi.purchase_id=p.id)
      ) ORDER BY p.created_at DESC)
      FROM public.purchases p LEFT JOIN public.suppliers sp ON sp.id=p.supplier_id
      WHERE p.created_at>=p_start AND p.created_at<p_end
    ),'[]'::jsonb),
    'cashbox',COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,'type',c.entry_type,'amount',c.amount,'description',c.description) ORDER BY c.created_at DESC)
      FROM public.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end
    ),'[]'::jsonb),
    'returns',COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',pr.name,'quantity',r.quantity,'amount',r.amount,'reason',r.reason) ORDER BY r.created_at DESC)
      FROM public.returns r LEFT JOIN public.products pr ON pr.id=r.product_id
      WHERE r.created_at>=p_start AND r.created_at<p_end
    ),'[]'::jsonb),
    'debtor_payments',COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,'debtor_name',d.name,'amount',t.credit,'payment_method',t.payment_method,'notes',t.notes) ORDER BY t.created_at DESC)
      FROM public.debtor_transactions t JOIN public.debtors d ON d.id=t.debtor_id
      WHERE t.transaction_type='payment' AND t.created_at>=p_start AND t.created_at<p_end
    ),'[]'::jsonb),
    'orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'created_at',o.created_at,'public_code',o.public_code,'customer_name',o.customer_name,'customer_phone',o.customer_phone,'status',o.status,'total',o.total) ORDER BY o.created_at DESC) FROM public.orders o WHERE o.created_at>=p_start AND o.created_at<p_end),'[]'::jsonb),
    'prescriptions',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pr.id,'created_at',pr.created_at,'customer_name',pr.customer_name,'customer_phone',pr.customer_phone,'status',pr.status,'file_name',pr.file_name) ORDER BY pr.created_at DESC) FROM public.prescriptions pr WHERE pr.created_at>=p_start AND pr.created_at<p_end),'[]'::jsonb),
    'supplier_payments',COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id',sp.id,'created_at',sp.created_at,'supplier_name',s.name,'amount',sp.amount,'payment_method',sp.payment_method,'notes',sp.notes) ORDER BY sp.created_at DESC)
      FROM public.supplier_payments sp JOIN public.suppliers s ON s.id=sp.supplier_id
      WHERE sp.created_at>=p_start AND sp.created_at<p_end
    ),'[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_dashboard_day_details(timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_day_details(timestamptz,timestamptz) TO authenticated;

-- 4) Product-specific sales snapshot for a smart-inventory count.
CREATE OR REPLACE FUNCTION public.admin_inventory_count_sales_summary(p_count_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE v_start timestamptz; v_end timestamptz; v jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT started_at,COALESCE(completed_at,now()) INTO v_start,v_end FROM public.inventory_counts WHERE id=p_count_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'جرد المخزون غير موجود'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'product_id',x.product_id,
    'product_name',x.product_name,
    'sold_quantity',x.sold_quantity,
    'sales_value',x.sales_value,
    'invoice_count',x.invoice_count
  ) ORDER BY x.product_name),'[]'::jsonb)
  INTO v
  FROM (
    SELECT si.product_id,p.name AS product_name,
      COALESCE(SUM(si.quantity),0) AS sold_quantity,
      COALESCE(SUM(si.quantity*si.unit_price),0) AS sales_value,
      COUNT(DISTINCT si.sale_id)::integer AS invoice_count
    FROM public.sale_items si
    JOIN public.products p ON p.id=si.product_id
    WHERE si.created_at>=v_start AND si.created_at<=v_end
    GROUP BY si.product_id,p.name
  ) x;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_inventory_count_sales_summary(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_inventory_count_sales_summary(uuid) TO authenticated;


-- 5) Idempotent cashbox reconciliation for historical linked operations.
CREATE OR REPLACE FUNCTION public.admin_cashbox_reconcile()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE v_sales integer:=0; v_debt integer:=0; v_returns integer:=0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;

  INSERT INTO public.cashbox_entries(entry_type,amount,description,sale_id,created_by,created_at)
  SELECT 'sale_cash',COALESCE(s.total,0),'بيع نقدي — مزامنة الصندوق',s.id,s.created_by,s.created_at
  FROM public.sales s
  WHERE s.payment_method='cash' AND COALESCE(s.total,0)>0
    AND NOT EXISTS(SELECT 1 FROM public.cashbox_entries c WHERE c.sale_id=s.id AND c.entry_type='sale_cash');
  GET DIAGNOSTICS v_sales=ROW_COUNT;

  INSERT INTO public.cashbox_entries(entry_type,amount,description,debtor_transaction_id,created_by,created_at)
  SELECT 'debtor_payment',t.credit,'تحصيل دين — مزامنة الصندوق',t.id,t.created_by,t.created_at
  FROM public.debtor_transactions t
  WHERE t.transaction_type='payment' AND t.payment_method='cash' AND t.credit>0
    AND NOT EXISTS(SELECT 1 FROM public.cashbox_entries c WHERE c.debtor_transaction_id=t.id AND c.entry_type='debtor_payment');
  GET DIAGNOSTICS v_debt=ROW_COUNT;

  INSERT INTO public.cashbox_entries(entry_type,amount,description,sale_id,created_by,created_at)
  SELECT 'customer_return_refund',-abs(r.amount),'استرداد مرتجع زبون — مزامنة الصندوق',r.sale_id,r.created_by,r.created_at
  FROM public.returns r
  JOIN public.sales s ON s.id=r.sale_id
  WHERE r.return_type='customer' AND s.payment_method='cash' AND r.amount>0
    AND NOT EXISTS(SELECT 1 FROM public.cashbox_entries c WHERE c.sale_id=r.sale_id AND c.entry_type='customer_return_refund' AND c.created_at BETWEEN r.created_at-interval '2 seconds' AND r.created_at+interval '2 seconds');
  GET DIAGNOSTICS v_returns=ROW_COUNT;

  RETURN jsonb_build_object('sales_added',v_sales,'debt_payments_added',v_debt,'customer_returns_added',v_returns);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_cashbox_reconcile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cashbox_reconcile() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_cashbox_summary_v2(p_start timestamptz DEFAULT NULL,p_end timestamptz DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE s timestamptz:=COALESCE(p_start,'1900-01-01'::timestamptz); e timestamptz:=COALESCE(p_end,'2999-12-31'::timestamptz); v jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT jsonb_build_object(
    'cash_in',COALESCE(SUM(CASE WHEN amount>0 THEN amount ELSE 0 END),0),
    'cash_out',COALESCE(SUM(CASE WHEN amount<0 THEN -amount ELSE 0 END),0),
    'net',COALESCE(SUM(amount),0),
    'balance',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries),0),
    'entries',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'type',c.entry_type,'amount',c.amount,'description',c.description,'created_at',c.created_at) ORDER BY c.created_at DESC) FROM public.cashbox_entries c WHERE c.created_at>=s AND c.created_at<e),'[]'::jsonb)
  ) INTO v
  FROM public.cashbox_entries c WHERE c.created_at>=s AND c.created_at<e;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_cashbox_summary_v2(timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cashbox_summary_v2(timestamptz,timestamptz) TO authenticated;

COMMIT;
