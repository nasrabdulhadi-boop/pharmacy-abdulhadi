-- Staging only. Preserve public RPC signatures/output keys; normalize all mixed-ledger sums to SYP.
-- Native supplier debts remain segregated by currency via admin_currency_supplier_*_v1.
BEGIN;
CREATE OR REPLACE FUNCTION public.admin_cashbox_summary_v2(
 p_start timestamptz DEFAULT NULL,p_end timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE s timestamptz:=COALESCE(p_start,'1900-01-01'::timestamptz);
 e timestamptz:=COALESCE(p_end,'2999-12-31'::timestamptz); v jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF e<=s THEN RAISE EXCEPTION 'فترة الصندوق غير صالحة'; END IF;
 IF EXISTS(SELECT 1 FROM public.cashbox_entries WHERE currency='USD' AND amount_syp IS NULL) THEN
   RAISE EXCEPTION 'حركات دولار بلا مقابل ليرة؛ أوقف التقرير وصحح المصدر'; END IF;
 SELECT jsonb_build_object(
  'cash_in',COALESCE(SUM(GREATEST(COALESCE(c.amount_syp,c.amount),0)),0),
  'cash_out',COALESCE(SUM(GREATEST(-COALESCE(c.amount_syp,c.amount),0)),0),
  'net',COALESCE(SUM(COALESCE(c.amount_syp,c.amount)),0),
  'balance',COALESCE((SELECT SUM(COALESCE(x.amount_syp,x.amount)) FROM public.cashbox_entries x),0),
  'entries',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'id',x.id,'type',x.entry_type,'amount',COALESCE(x.amount_syp,x.amount),
    'original_amount',x.amount,'currency',x.currency,'fx_rate',x.fx_rate,
    'description',x.description,'created_at',x.created_at
  ) ORDER BY x.created_at DESC) FROM public.cashbox_entries x WHERE x.created_at>=s AND x.created_at<e),'[]'::jsonb)
 ) INTO v FROM public.cashbox_entries c WHERE c.created_at>=s AND c.created_at<e;
 RETURN v;
END;
$fn$;
CREATE OR REPLACE FUNCTION public.admin_dashboard_financial_summary(p_start timestamptz,p_end timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
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
  'supplier_payments',COALESCE((SELECT SUM(COALESCE(amount_syp,amount))
     FROM public.supplier_payments WHERE created_at>=p_start AND created_at<p_end),0),
  'orders_count',(SELECT COUNT(*) FROM public.orders WHERE created_at>=p_start AND created_at<p_end),
  'prescriptions_count',(SELECT COUNT(*) FROM public.prescriptions WHERE created_at>=p_start AND created_at<p_end)
 );
END;
$fn$;
-- Old admin_accounting_report is retained. New wrapper returns its keys with corrected SYP totals/rows.
CREATE OR REPLACE FUNCTION public.admin_currency_accounting_report_v1(
 p_start timestamptz,p_end timestamptz,p_compare_start timestamptz DEFAULT NULL,p_compare_end timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v jsonb; v_supplier_returns numeric; v_purchase_total numeric; v_cash_balance numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 v:=public.admin_accounting_report(p_start,p_end,p_compare_start,p_compare_end);
 SELECT COALESCE(SUM(COALESCE(amount_syp,amount)),0) INTO v_supplier_returns
  FROM public.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end;
 SELECT COALESCE(SUM(COALESCE(total_syp,total)),0) INTO v_purchase_total
  FROM public.purchases WHERE created_at>=p_start AND created_at<p_end;
 SELECT COALESCE(SUM(COALESCE(amount_syp,amount)),0) INTO v_cash_balance FROM public.cashbox_entries;
 v:=jsonb_set(v,'{summary,supplier_returns}',to_jsonb(v_supplier_returns));
 v:=jsonb_set(v,'{summary,net_purchases}',to_jsonb(v_purchase_total-v_supplier_returns));
 v:=jsonb_set(v,'{summary,cash_balance}',to_jsonb(v_cash_balance));
 v:=jsonb_set(v,'{purchase_rows}',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,'supplier_name',s.name,
 'total',COALESCE(p.total_syp,p.total),'original_total',p.total,'currency',p.currency,
 'fx_rate',p.fx_rate,'bonus_quantity',COALESCE((SELECT SUM(pi.bonus_quantity) FROM public.purchase_items pi WHERE pi.purchase_id=p.id),0)
 ) ORDER BY p.created_at DESC) FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id
 WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb));
 v:=jsonb_set(v,'{cash_rows}',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'id',c.id,'created_at',c.created_at,'type',c.entry_type,
 'amount',COALESCE(c.amount_syp,c.amount),'original_amount',c.amount,
 'currency',c.currency,'fx_rate',c.fx_rate,'description',c.description
 ) ORDER BY c.created_at DESC) FROM public.cashbox_entries c
 WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb));
 v:=jsonb_set(v,'{return_rows}',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',p.name,
 'quantity',r.quantity,'amount',COALESCE(r.amount_syp,r.amount),
 'original_amount',r.amount,'currency',r.currency,'fx_rate',r.fx_rate,'reason',r.reason
 ) ORDER BY r.created_at DESC) FROM public.returns r LEFT JOIN public.products p ON p.id=r.product_id
 WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb));
 RETURN v;
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_accounting_report_v1(timestamptz,timestamptz,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_accounting_report_v1(timestamptz,timestamptz,timestamptz,timestamptz) TO authenticated;
COMMIT;
