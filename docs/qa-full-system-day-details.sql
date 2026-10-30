CREATE OR REPLACE FUNCTION pharmacy_supplier_stage.admin_dashboard_day_details(p_start timestamp with time zone, p_end timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pharmacy_supplier_stage', 'auth'
AS $function$
DECLARE v jsonb;f jsonb;
BEGIN
 IF NOT pharmacy_supplier_stage.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid dashboard day range'; END IF;
 f:=pharmacy_supplier_stage.admin_dashboard_financial_summary(p_start,p_end);
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
    FROM pharmacy_supplier_stage.sale_items si LEFT JOIN pharmacy_supplier_stage.products p ON p.id=si.product_id WHERE si.sale_id=s.id),'[]'::jsonb)
   ) ORDER BY s.created_at DESC) FROM pharmacy_supplier_stage.sales s LEFT JOIN pharmacy_supplier_stage.debtors d ON d.id=s.debtor_id
   WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
  'purchases',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,
   'invoice_number',p.invoice_number,'supplier_name',sp.name,
   'total',COALESCE(p.total_syp,p.total),'original_total',p.total,
   'paid_amount',CASE WHEN p.currency='USD' THEN ROUND(p.paid_amount*p.fx_rate,2) ELSE p.paid_amount END,
   'due_amount',CASE WHEN p.currency='USD' THEN ROUND(p.due_amount*p.fx_rate,2) ELSE p.due_amount END,
   'currency',p.currency,'fx_rate',p.fx_rate,'payment_status',p.payment_status,
   'item_count',(SELECT COUNT(*) FROM pharmacy_supplier_stage.purchase_items pi WHERE pi.purchase_id=p.id),
   'bonus_quantity',(SELECT COALESCE(SUM(pi2.bonus_quantity),0) FROM pharmacy_supplier_stage.purchase_items pi2 WHERE pi2.purchase_id=p.id))
   ORDER BY p.created_at DESC) FROM pharmacy_supplier_stage.purchases p LEFT JOIN pharmacy_supplier_stage.suppliers sp ON sp.id=p.supplier_id
   WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb),
  'cashbox',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,
    'type',c.entry_type,'amount',COALESCE(c.amount_syp,c.amount),'original_amount',c.amount,
    'currency',c.currency,'description',c.description) ORDER BY c.created_at DESC)
    FROM pharmacy_supplier_stage.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb),
  'returns',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,
    'type',r.return_type,'product_name',pr.name,'quantity',r.quantity,
    'amount',COALESCE(r.amount_syp,r.amount),'original_amount',r.amount,'currency',r.currency,'reason',r.reason)
    ORDER BY r.created_at DESC) FROM pharmacy_supplier_stage.returns r LEFT JOIN pharmacy_supplier_stage.products pr ON pr.id=r.product_id
    WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb),
  'debtor_payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,
    'debtor_name',d.name,'amount',COALESCE(t.amount_syp,t.credit),
    'payment_method',t.payment_method,'notes',t.notes) ORDER BY t.created_at DESC)
    FROM pharmacy_supplier_stage.debtor_transactions t JOIN pharmacy_supplier_stage.debtors d ON d.id=t.debtor_id
    WHERE t.transaction_type='payment' AND t.created_at>=p_start AND t.created_at<p_end),'[]'::jsonb),
  'orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'created_at',o.created_at,
    'public_code',o.public_code,'customer_name',c.name,'customer_phone',c.phone,
    'status',o.status,'total',o.total) ORDER BY o.created_at DESC)
    FROM pharmacy_supplier_stage.orders o LEFT JOIN pharmacy_supplier_stage.customers c ON c.id=o.customer_id
    WHERE o.created_at>=p_start AND o.created_at<p_end),'[]'::jsonb),
  'prescriptions',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pr.id,'created_at',pr.created_at,
    'customer_name',pr.customer_name,'customer_phone',pr.customer_phone,'status',pr.status,
    'file_name',pr.file_name) ORDER BY pr.created_at DESC)
    FROM pharmacy_supplier_stage.prescriptions pr WHERE pr.created_at>=p_start AND pr.created_at<p_end),'[]'::jsonb),
  'supplier_payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',sp.id,'created_at',sp.created_at,
    'supplier_name',s.name,'amount',COALESCE(sp.amount_syp,sp.amount),
    'original_amount',sp.amount,'currency',sp.currency,'tender_amount',coalesce(sp.tender_amount,sp.amount),'tender_currency',coalesce(sp.tender_currency,sp.currency),'settled_amount',sp.amount,'payment_method',sp.payment_method,
    'notes',sp.notes) ORDER BY sp.created_at DESC)
    FROM pharmacy_supplier_stage.supplier_payments sp JOIN pharmacy_supplier_stage.suppliers s ON s.id=sp.supplier_id
    WHERE sp.created_at>=p_start AND sp.created_at<p_end),'[]'::jsonb)
 ) INTO v;
 RETURN v;
END;
$function$
;
