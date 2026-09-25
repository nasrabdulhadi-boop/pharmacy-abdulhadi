-- Pharmacy Abdelhadi v5.14 — Reports accuracy + UI support
-- Run this file once after the current system migrations.

CREATE OR REPLACE FUNCTION public.admin_accounting_report(
  p_start timestamptz,p_end timestamptz,p_compare_start timestamptz DEFAULT NULL,p_compare_end timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
DECLARE v jsonb; cs timestamptz:=p_compare_start; ce timestamptz:=p_compare_end;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object(
  'period',jsonb_build_object('start',p_start,'end',p_end),
  'summary',jsonb_build_object(
   'sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0),
   'cash_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0),
   'credit_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),
   'customer_returns',COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='customer' AND created_at>=p_start AND created_at<p_end),0),
   'supplier_returns',COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end),0),
   'net_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='customer' AND created_at>=p_start AND created_at<p_end),0),
   'debt_collections',COALESCE((SELECT SUM(credit) FROM public.debtor_transactions WHERE transaction_type='payment' AND created_at>=p_start AND created_at<p_end),0),
   'new_debt',COALESCE((SELECT SUM(debit) FROM public.debtor_transactions WHERE transaction_type='sale' AND created_at>=p_start AND created_at<p_end),0),
   'purchases',COALESCE((SELECT SUM(total) FROM public.purchases WHERE created_at>=p_start AND created_at<p_end),0),
   'net_purchases',COALESCE((SELECT SUM(total) FROM public.purchases WHERE created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end),0),
   'gross_profit',COALESCE((SELECT SUM((unit_price-unit_cost)*quantity) FROM public.sale_items WHERE created_at>=p_start AND created_at<p_end),0),
   'return_profit',COALESCE((SELECT SUM(r.quantity*(si.unit_price-si.unit_cost)) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0),
   'profit',COALESCE((SELECT SUM((unit_price-unit_cost)*quantity) FROM public.sale_items WHERE created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(r.quantity*(si.unit_price-si.unit_cost)) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0),
   'margin',CASE WHEN (COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='customer' AND created_at>=p_start AND created_at<p_end),0))=0 THEN 0 ELSE ROUND(((COALESCE((SELECT SUM((unit_price-unit_cost)*quantity) FROM public.sale_items WHERE created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(r.quantity*(si.unit_price-si.unit_cost)) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end),0))/NULLIF((COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='customer' AND created_at>=p_start AND created_at<p_end),0)),0))*100,2) END,
   'cash_in',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE amount>0 AND created_at>=p_start AND created_at<p_end),0),
   'cash_out',COALESCE((SELECT SUM(-amount) FROM public.cashbox_entries WHERE amount<0 AND created_at>=p_start AND created_at<p_end),0),
   'cash_net',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE created_at>=p_start AND created_at<p_end),0),
   'cash_balance',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries),0),
   'outstanding_debt',COALESCE((SELECT SUM(debit-credit) FROM public.debtor_transactions),0),
   'sales_count',COALESCE((SELECT COUNT(*) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0),
   'purchase_count',COALESCE((SELECT COUNT(*) FROM public.purchases WHERE created_at>=p_start AND created_at<p_end),0)
  ),
  'comparison',CASE WHEN cs IS NULL OR ce IS NULL THEN NULL ELSE jsonb_build_object(
   'sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=cs AND created_at<ce),0),
   'net_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=cs AND created_at<ce),0)-COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='customer' AND created_at>=cs AND created_at<ce),0),
   'purchases',COALESCE((SELECT SUM(total) FROM public.purchases WHERE created_at>=cs AND created_at<ce),0),
   'profit',COALESCE((SELECT SUM((unit_price-unit_cost)*quantity) FROM public.sale_items WHERE created_at>=cs AND created_at<ce),0)-COALESCE((SELECT SUM(r.quantity*(si.unit_price-si.unit_cost)) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=cs AND r.created_at<ce),0),
   'new_debt',COALESCE((SELECT SUM(debit) FROM public.debtor_transactions WHERE transaction_type='sale' AND created_at>=cs AND created_at<ce),0),
   'debt_collections',COALESCE((SELECT SUM(credit) FROM public.debtor_transactions WHERE transaction_type='payment' AND created_at>=cs AND created_at<ce),0)
  ) END,
  'sales_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,'total',s.total,'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount,'debtor_id',s.debtor_id,'debtor_name',d.name) ORDER BY s.created_at DESC) FROM public.sales s LEFT JOIN public.debtors d ON d.id=s.debtor_id WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
  'purchase_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,'supplier_name',s.name,'total',p.total) ORDER BY p.created_at DESC) FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb),
  'debt_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,'type',t.transaction_type,'debtor_name',d.name,'amount',t.amount,'debit',t.debit,'credit',t.credit,'notes',t.notes) ORDER BY t.created_at DESC) FROM public.debtor_transactions t JOIN public.debtors d ON d.id=t.debtor_id WHERE t.created_at>=p_start AND t.created_at<p_end),'[]'::jsonb),
  'cash_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,'type',c.entry_type,'amount',c.amount,'description',c.description) ORDER BY c.created_at DESC) FROM public.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb),
  'return_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',p.name,'quantity',r.quantity,'amount',r.amount,'reason',r.reason) ORDER BY r.created_at DESC) FROM public.returns r LEFT JOIN public.products p ON p.id=r.product_id WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb),
  'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_id',x.product_id,'product_name',x.product_name,'quantity',x.quantity,'sales',x.sales,'cost',x.cost,'gross_profit',x.gross_profit,'return_amount',x.return_amount,'return_profit',x.return_profit,'net_sales',x.sales-x.return_amount,'net_profit',x.gross_profit-x.return_profit) ORDER BY (x.sales-x.return_amount) DESC) FROM (SELECT p.id product_id,p.name AS product_name,SUM(si.quantity) AS quantity,SUM(si.quantity*si.unit_price) AS sales,SUM(si.quantity*si.unit_cost) AS cost,SUM(si.quantity*(si.unit_price-si.unit_cost)) AS gross_profit,COALESCE((SELECT SUM(r.amount) FROM public.returns r WHERE r.return_type='customer' AND r.product_id=p.id AND r.created_at>=p_start AND r.created_at<p_end),0) AS return_amount,COALESCE((SELECT SUM(r.quantity*(si2.unit_price-si2.unit_cost)) FROM public.returns r JOIN public.sale_items si2 ON si2.id=r.sale_item_id WHERE r.return_type='customer' AND r.product_id=p.id AND r.created_at>=p_start AND r.created_at<p_end),0) AS return_profit FROM public.sale_items si JOIN public.products p ON p.id=si.product_id WHERE si.created_at>=p_start AND si.created_at<p_end GROUP BY p.id,p.name) x),'[]'::jsonb),
  'checks',jsonb_build_object(
   'sales_split_delta',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),
   'sales_item_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end AND ABS(COALESCE((SELECT SUM(si.quantity*si.unit_price) FROM public.sale_items si WHERE si.sale_id=s.id),0)-(COALESCE(s.total,0)+COALESCE(s.discount,0)))>0.01),0),
   'customer_return_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end AND r.quantity>(si.quantity+0.000001)),0),
   'supplier_return_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.returns r JOIN public.purchase_items pi ON pi.batch_id=r.batch_id AND pi.purchase_id=r.purchase_id WHERE r.return_type='supplier' AND r.created_at>=p_start AND r.created_at<p_end AND r.quantity>(pi.quantity+0.000001)),0),
   'cash_delta',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE created_at>=p_start AND created_at<p_end),0)-(COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE amount>0 AND created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(-amount) FROM public.cashbox_entries WHERE amount<0 AND created_at>=p_start AND created_at<p_end),0))
  ) ) INTO v;
 RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_accounting_report(timestamptz,timestamptz,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_accounting_report(timestamptz,timestamptz,timestamptz,timestamptz) TO authenticated;
