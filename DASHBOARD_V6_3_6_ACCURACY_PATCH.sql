-- Pharmacy Abdelhadi V6.3.6
-- Dashboard/report accuracy alignment + exact day details.
-- Does not drop existing functions. Run once after the current system patches.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_dashboard_sales_day(
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
  IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid dashboard day range'; END IF;

  SELECT jsonb_build_object(
    'start',p_start,
    'end',p_end,
    'summary',jsonb_build_object(
      'sales',COALESCE((SELECT SUM(s.total) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end),0),
      'customer_returns',COALESCE((SELECT SUM(r.amount) FROM public.returns r WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0),
      'net_sales',COALESCE((SELECT SUM(s.total) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end),0)-COALESCE((SELECT SUM(r.amount) FROM public.returns r WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0),
      'cash_sales',COALESCE((SELECT SUM(s.total) FROM public.sales s WHERE s.payment_method='cash' AND s.created_at>=p_start AND s.created_at<p_end),0),
      'credit_sales',COALESCE((SELECT SUM(s.total) FROM public.sales s WHERE s.payment_method='credit' AND s.created_at>=p_start AND s.created_at<p_end),0),
      'invoice_count',COALESCE((SELECT COUNT(*) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end),0),
      'gross_profit',COALESCE((SELECT SUM((si.unit_price-si.unit_cost)*si.quantity) FROM public.sale_items si JOIN public.sales s ON s.id=si.sale_id WHERE s.created_at>=p_start AND s.created_at<p_end),0),
      'return_profit',COALESCE((SELECT SUM(r.quantity*(si.unit_price-si.unit_cost)) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0),
      'profit',COALESCE((SELECT SUM((si.unit_price-si.unit_cost)*si.quantity) FROM public.sale_items si JOIN public.sales s ON s.id=si.sale_id WHERE s.created_at>=p_start AND s.created_at<p_end),0)-COALESCE((SELECT SUM(r.quantity*(si.unit_price-si.unit_cost)) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0),
      'purchases',COALESCE((SELECT SUM(p.total) FROM public.purchases p WHERE p.created_at>=p_start AND p.created_at<p_end),0),
      'customer_return_count',COALESCE((SELECT COUNT(*) FROM public.returns r WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0),
      'supplier_return_count',COALESCE((SELECT COUNT(*) FROM public.returns r WHERE r.return_type='supplier' AND r.created_at>=p_start AND r.created_at<p_end),0)
    ),
    'sales',COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id',s.id,'created_at',s.created_at,'subtotal',s.subtotal,'discount',s.discount,'total',s.total,
        'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount,
        'payment_notes',s.payment_notes,'debtor_name',d.name,'customer_name',c.name,
        'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'product_name',p.name,'barcode',p.barcode,'strength',p.strength,'dosage_form',p.dosage_form,
          'quantity',si.quantity,'unit_price',si.unit_price,'unit_cost',si.unit_cost,
          'line_total',si.quantity*si.unit_price,'line_profit',(si.unit_price-si.unit_cost)*si.quantity
        ) ORDER BY si.created_at,p.name) FROM public.sale_items si LEFT JOIN public.products p ON p.id=si.product_id WHERE si.sale_id=s.id),'[]'::jsonb)
      ) ORDER BY s.created_at DESC)
      FROM public.sales s LEFT JOIN public.debtors d ON d.id=s.debtor_id LEFT JOIN public.customers c ON c.id=s.customer_id
      WHERE s.created_at>=p_start AND s.created_at<p_end
    ),'[]'::jsonb),
    'returns',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',p.name,'quantity',r.quantity,'amount',r.amount,'reason',r.reason) ORDER BY r.created_at DESC) FROM public.returns r LEFT JOIN public.products p ON p.id=r.product_id WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_dashboard_sales_day(timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_sales_day(timestamptz,timestamptz) TO authenticated;

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
  IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid dashboard day range'; END IF;

  SELECT jsonb_build_object(
    'period',jsonb_build_object('start',p_start,'end',p_end),
    'summary',jsonb_build_object(
      'sales',COALESCE((SELECT SUM(s.total) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end),0),
      'net_sales',COALESCE((SELECT SUM(s.total) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end),0)-COALESCE((SELECT SUM(r.amount) FROM public.returns r WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0),
      'invoice_count',COALESCE((SELECT COUNT(*) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end),0),
      'cash_sales',COALESCE((SELECT SUM(s.total) FROM public.sales s WHERE s.payment_method='cash' AND s.created_at>=p_start AND s.created_at<p_end),0),
      'credit_sales',COALESCE((SELECT SUM(s.total) FROM public.sales s WHERE s.payment_method='credit' AND s.created_at>=p_start AND s.created_at<p_end),0),
      'gross_profit',COALESCE((SELECT SUM((si.unit_price-si.unit_cost)*si.quantity) FROM public.sale_items si JOIN public.sales s ON s.id=si.sale_id WHERE s.created_at>=p_start AND s.created_at<p_end),0),
      'return_profit',COALESCE((SELECT SUM(r.quantity*(si.unit_price-si.unit_cost)) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0),
      'profit',COALESCE((SELECT SUM((si.unit_price-si.unit_cost)*si.quantity) FROM public.sale_items si JOIN public.sales s ON s.id=si.sale_id WHERE s.created_at>=p_start AND s.created_at<p_end),0)-COALESCE((SELECT SUM(r.quantity*(si.unit_price-si.unit_cost)) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0),
      'purchases',COALESCE((SELECT SUM(p.total) FROM public.purchases p WHERE p.created_at>=p_start AND p.created_at<p_end),0),
      'purchase_count',COALESCE((SELECT COUNT(*) FROM public.purchases p WHERE p.created_at>=p_start AND p.created_at<p_end),0),
      'customer_returns',COALESCE((SELECT SUM(r.amount) FROM public.returns r WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0),
      'supplier_returns',COALESCE((SELECT SUM(r.amount) FROM public.returns r WHERE r.return_type='supplier' AND r.created_at>=p_start AND r.created_at<p_end),0),
      'cash_in',COALESCE((SELECT SUM(c.amount) FROM public.cashbox_entries c WHERE c.amount>0 AND c.created_at>=p_start AND c.created_at<p_end),0),
      'cash_out',COALESCE((SELECT SUM(-c.amount) FROM public.cashbox_entries c WHERE c.amount<0 AND c.created_at>=p_start AND c.created_at<p_end),0),
      'cash_net',COALESCE((SELECT SUM(c.amount) FROM public.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),0),
      'debtor_payments',COALESCE((SELECT SUM(t.credit) FROM public.debtor_transactions t WHERE t.transaction_type='payment' AND t.created_at>=p_start AND t.created_at<p_end),0),
      'supplier_payments',COALESCE((SELECT SUM(sp.amount) FROM public.supplier_payments sp WHERE sp.created_at>=p_start AND sp.created_at<p_end),0),
      'orders_count',COALESCE((SELECT COUNT(*) FROM public.orders o WHERE o.created_at>=p_start AND o.created_at<p_end),0),
      'prescriptions_count',COALESCE((SELECT COUNT(*) FROM public.prescriptions pr WHERE pr.created_at>=p_start AND pr.created_at<p_end),0)
    ),
    'sales',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',s.id,'created_at',s.created_at,'invoice_number',s.id::text,'total',s.total,'payment_method',s.payment_method,
      'paid_amount',s.paid_amount,'due_amount',s.due_amount,'debtor_name',d.name,'customer_name',c.name,
      'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',p.name,'barcode',p.barcode,'quantity',si.quantity,'unit_price',si.unit_price,'unit_cost',si.unit_cost,'line_total',si.quantity*si.unit_price,'line_profit',(si.unit_price-si.unit_cost)*si.quantity) ORDER BY si.created_at,p.name) FROM public.sale_items si LEFT JOIN public.products p ON p.id=si.product_id WHERE si.sale_id=s.id),'[]'::jsonb)
    ) ORDER BY s.created_at DESC) FROM public.sales s LEFT JOIN public.debtors d ON d.id=s.debtor_id LEFT JOIN public.customers c ON c.id=s.customer_id WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
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

COMMIT;
