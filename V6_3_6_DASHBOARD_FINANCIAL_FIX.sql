-- Pharmacy Abdelhadi V6.3.6
-- Dashboard financial authority + 7-day sales chart + day details.
-- Safe patch: does not drop existing application functions.
BEGIN;

-- 1) One authoritative calculation for a day/period.
CREATE OR REPLACE FUNCTION public.admin_dashboard_financial_summary(
  p_start timestamptz,
  p_end timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE
  v_sales numeric:=0;
  v_cost numeric:=0;
  v_returns numeric:=0;
  v_return_cost numeric:=0;
  v_purchases numeric:=0;
  v_profit numeric:=0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid financial period'; END IF;

  SELECT COALESCE(SUM(s.total),0) INTO v_sales
  FROM public.sales s
  WHERE s.created_at>=p_start AND s.created_at<p_end;

  -- Cost is taken from the actual sale_items/batch cost recorded at sale time,
  -- never from the current product purchase price.
  SELECT COALESCE(SUM(si.quantity*si.unit_cost),0) INTO v_cost
  FROM public.sale_items si
  JOIN public.sales s ON s.id=si.sale_id
  WHERE s.created_at>=p_start AND s.created_at<p_end;

  SELECT COALESCE(SUM(r.amount),0) INTO v_returns
  FROM public.returns r
  WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end;

  SELECT COALESCE(SUM(r.quantity*si.unit_cost),0) INTO v_return_cost
  FROM public.returns r
  JOIN public.sale_items si ON si.id=r.sale_item_id
  WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end;

  SELECT COALESCE(SUM(p.total),0) INTO v_purchases
  FROM public.purchases p
  WHERE p.created_at>=p_start AND p.created_at<p_end;

  -- Net gross profit = net sales after customer refunds minus the cost of
  -- goods actually sold after restoring the cost of returned goods.
  v_profit := v_sales-v_cost-v_returns+v_return_cost;

  RETURN jsonb_build_object(
    'sales',v_sales,
    'cost_of_goods',v_cost,
    'customer_returns',v_returns,
    'customer_return_cost',v_return_cost,
    'net_sales',v_sales-v_returns,
    'profit',v_profit,
    'margin',CASE WHEN (v_sales-v_returns)=0 THEN 0 ELSE ROUND((v_profit/NULLIF(v_sales-v_returns,0))*100,2) END,
    'purchases',v_purchases,
    'invoice_count',(SELECT COUNT(*) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),
    'purchase_count',(SELECT COUNT(*) FROM public.purchases WHERE created_at>=p_start AND created_at<p_end),
    'cash_in',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE amount>0 AND created_at>=p_start AND created_at<p_end),0),
    'cash_out',COALESCE((SELECT SUM(-amount) FROM public.cashbox_entries WHERE amount<0 AND created_at>=p_start AND created_at<p_end),0),
    'cash_net',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE created_at>=p_start AND created_at<p_end),0),
    'debtor_payments',COALESCE((SELECT SUM(credit) FROM public.debtor_transactions WHERE transaction_type='payment' AND created_at>=p_start AND created_at<p_end),0),
    'supplier_payments',COALESCE((SELECT SUM(amount) FROM public.supplier_payments WHERE created_at>=p_start AND created_at<p_end),0),
    'orders_count',(SELECT COUNT(*) FROM public.orders WHERE created_at>=p_start AND created_at<p_end),
    'prescriptions_count',(SELECT COUNT(*) FROM public.prescriptions WHERE created_at>=p_start AND created_at<p_end)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_dashboard_financial_summary(timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_financial_summary(timestamptz,timestamptz) TO authenticated;

-- 2) Chart endpoint now uses the same financial source for exact daily sales.
CREATE OR REPLACE FUNCTION public.admin_dashboard_sales_day(
  p_start timestamptz,
  p_end timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE v jsonb; f jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  f:=public.admin_dashboard_financial_summary(p_start,p_end);
  SELECT jsonb_build_object(
    'start',p_start,'end',p_end,'summary',f,
    'sales',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,'total',s.total,'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount) ORDER BY s.created_at DESC) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_dashboard_sales_day(timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_sales_day(timestamptz,timestamptz) TO authenticated;

-- 3) Full day details uses exactly the same financial summary.
CREATE OR REPLACE FUNCTION public.admin_dashboard_day_details(
  p_start timestamptz,
  p_end timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE v jsonb; f jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid dashboard day range'; END IF;
  f:=public.admin_dashboard_financial_summary(p_start,p_end);
  SELECT jsonb_build_object(
    'period',jsonb_build_object('start',p_start,'end',p_end),
    'summary',f,
    'sales',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,'invoice_number',s.id::text,'total',s.total,'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount,'debtor_name',d.name,'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',p.name,'barcode',p.barcode,'quantity',si.quantity,'unit_price',si.unit_price,'line_total',si.quantity*si.unit_price) ORDER BY p.name) FROM public.sale_items si LEFT JOIN public.products p ON p.id=si.product_id WHERE si.sale_id=s.id),'[]'::jsonb)) ORDER BY s.created_at DESC) FROM public.sales s LEFT JOIN public.debtors d ON d.id=s.debtor_id WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
    'purchases',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,'supplier_name',sp.name,'total',p.total,'paid_amount',p.paid_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,'item_count',(SELECT COUNT(*) FROM public.purchase_items pi WHERE pi.purchase_id=p.id)) ORDER BY p.created_at DESC) FROM public.purchases p LEFT JOIN public.suppliers sp ON sp.id=p.supplier_id WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb),
    'cashbox',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,'type',c.entry_type,'amount',c.amount,'description',c.description) ORDER BY c.created_at DESC) FROM public.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb),
    'returns',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',pr.name,'quantity',r.quantity,'amount',r.amount,'reason',r.reason) ORDER BY r.created_at DESC) FROM public.returns r LEFT JOIN public.products pr ON pr.id=r.product_id WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb),
    'debtor_payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,'debtor_name',d.name,'amount',t.credit,'payment_method',t.payment_method,'notes',t.notes) ORDER BY t.created_at DESC) FROM public.debtor_transactions t JOIN public.debtors d ON d.id=t.debtor_id WHERE t.transaction_type='payment' AND t.created_at>=p_start AND t.created_at<p_end),'[]'::jsonb),
    'orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'created_at',o.created_at,'public_code',o.public_code,'customer_name',o.customer_name,'customer_phone',o.customer_phone,'status',o.status,'total',o.total) ORDER BY o.created_at DESC) FROM public.orders o WHERE o.created_at>=p_start AND o.created_at<p_end),'[]'::jsonb),
    'prescriptions',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pr.id,'created_at',pr.created_at,'customer_name',pr.customer_name,'customer_phone',pr.customer_phone,'status',pr.status,'file_name',pr.file_name) ORDER BY pr.created_at DESC) FROM public.prescriptions pr WHERE pr.created_at>=p_start AND pr.created_at<p_end),'[]'::jsonb),
    'supplier_payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',sp.id,'created_at',sp.created_at,'supplier_name',s.name,'amount',sp.amount,'payment_method',sp.payment_method,'notes',sp.notes) ORDER BY sp.created_at DESC) FROM public.supplier_payments sp JOIN public.suppliers s ON s.id=sp.supplier_id WHERE sp.created_at>=p_start AND sp.created_at<p_end),'[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_dashboard_day_details(timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_day_details(timestamptz,timestamptz) TO authenticated;

-- 4) Reports use the same authoritative profit definition.
CREATE OR REPLACE FUNCTION public.admin_accounting_report(
  p_start timestamptz,
  p_end timestamptz,
  p_compare_start timestamptz DEFAULT NULL,
  p_compare_end timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE v jsonb; f jsonb; cf jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  f:=public.admin_dashboard_financial_summary(p_start,p_end);
  cf:=CASE WHEN p_compare_start IS NULL OR p_compare_end IS NULL THEN NULL ELSE public.admin_dashboard_financial_summary(p_compare_start,p_compare_end) END;
  SELECT jsonb_build_object(
    'period',jsonb_build_object('start',p_start,'end',p_end),
    'summary',jsonb_build_object(
      'sales',COALESCE((f->>'sales')::numeric,0),'cash_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0),'credit_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),
      'debt_collections',COALESCE((f->>'debtor_payments')::numeric,0),'new_debt',COALESCE((SELECT SUM(debit) FROM public.debtor_transactions WHERE transaction_type='sale' AND created_at>=p_start AND created_at<p_end),0),'purchases',COALESCE((f->>'purchases')::numeric,0),
      'gross_profit',COALESCE((f->>'profit')::numeric,0),'return_profit',COALESCE((f->>'customer_return_cost')::numeric,0),'supplier_returns',COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end),0),'net_purchases',COALESCE((f->>'purchases')::numeric,0)-COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end),0),'profit',COALESCE((f->>'profit')::numeric,0),'margin',COALESCE((f->>'margin')::numeric,0),'cash_in',COALESCE((f->>'cash_in')::numeric,0),'cash_out',COALESCE((f->>'cash_out')::numeric,0),'cash_net',COALESCE((f->>'cash_net')::numeric,0),'cash_balance',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries),0),'outstanding_debt',COALESCE((SELECT SUM(debit-credit) FROM public.debtor_transactions),0),'sales_count',COALESCE((f->>'invoice_count')::bigint,0),'purchase_count',COALESCE((f->>'purchase_count')::bigint,0),
      'customer_returns',COALESCE((f->>'customer_returns')::numeric,0),'net_sales',COALESCE((f->>'net_sales')::numeric,0),'cost_of_goods',COALESCE((f->>'cost_of_goods')::numeric,0)
    ),
    'comparison',CASE WHEN cf IS NULL THEN NULL ELSE jsonb_build_object('sales',COALESCE((cf->>'sales')::numeric,0),'purchases',COALESCE((cf->>'purchases')::numeric,0),'profit',COALESCE((cf->>'profit')::numeric,0),'new_debt',COALESCE((SELECT SUM(debit) FROM public.debtor_transactions WHERE transaction_type='sale' AND created_at>=p_compare_start AND created_at<p_compare_end),0),'debt_collections',COALESCE((cf->>'debtor_payments')::numeric,0)) END,
    'sales_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,'total',s.total,'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount,'debtor_id',s.debtor_id,'debtor_name',d.name) ORDER BY s.created_at DESC) FROM public.sales s LEFT JOIN public.debtors d ON d.id=s.debtor_id WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
    'purchase_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,'supplier_name',s.name,'total',p.total) ORDER BY p.created_at DESC) FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb),
    'debt_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,'type',t.transaction_type,'debtor_name',d.name,'amount',t.amount,'debit',t.debit,'credit',t.credit,'notes',t.notes) ORDER BY t.created_at DESC) FROM public.debtor_transactions t JOIN public.debtors d ON d.id=t.debtor_id WHERE t.created_at>=p_start AND t.created_at<p_end),'[]'::jsonb),
    'cash_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,'type',c.entry_type,'amount',c.amount,'description',c.description) ORDER BY c.created_at DESC) FROM public.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb),
    'return_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',p.name,'quantity',r.quantity,'amount',r.amount,'reason',r.reason) ORDER BY r.created_at DESC) FROM public.returns r LEFT JOIN public.products p ON p.id=r.product_id WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb),
    'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_id',x.product_id,'product_name',x.product_name,'quantity',x.quantity,'sales',x.sales,'cost',x.cost,'gross_profit',x.gross_profit,'return_amount',x.return_amount,'return_profit',x.return_profit,'net_sales',x.sales-x.return_amount,'net_profit',x.gross_profit-x.return_profit) ORDER BY (x.sales-x.return_amount) DESC) FROM (SELECT p.id product_id,p.name AS product_name,SUM(si.quantity) AS quantity,SUM(si.quantity*si.unit_price) AS sales,SUM(si.quantity*si.unit_cost) AS cost,SUM(si.quantity*(si.unit_price-si.unit_cost)) AS gross_profit,COALESCE((SELECT SUM(r.amount) FROM public.returns r WHERE r.return_type='customer' AND r.product_id=p.id AND r.created_at>=p_start AND r.created_at<p_end),0) AS return_amount,COALESCE((SELECT SUM(r.quantity*(si2.unit_price-si2.unit_cost)) FROM public.returns r JOIN public.sale_items si2 ON si2.id=r.sale_item_id WHERE r.return_type='customer' AND r.product_id=p.id AND r.created_at>=p_start AND r.created_at<p_end),0) AS return_profit FROM public.sale_items si JOIN public.products p ON p.id=si.product_id JOIN public.sales s ON s.id=si.sale_id WHERE s.created_at>=p_start AND s.created_at<p_end GROUP BY p.id,p.name) x),'[]'::jsonb),
    'checks',jsonb_build_object('sales_split_delta',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),'sales_item_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end AND ABS(COALESCE((SELECT SUM(si.quantity*si.unit_price) FROM public.sale_items si WHERE si.sale_id=s.id),0)-(COALESCE(s.total,0)+COALESCE(s.discount,0)))>0.01),0),'customer_return_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end AND r.quantity>(si.quantity+0.000001)),0),'supplier_return_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.returns r JOIN public.purchase_items pi ON pi.batch_id=r.batch_id AND pi.purchase_id=r.purchase_id WHERE r.return_type='supplier' AND r.created_at>=p_start AND r.created_at<p_end AND r.quantity>(pi.quantity+0.000001)),0),'cash_delta',0)
  ) INTO v;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_accounting_report(timestamptz,timestamptz,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_accounting_report(timestamptz,timestamptz,timestamptz,timestamptz) TO authenticated;

COMMIT;
