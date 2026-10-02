-- Pharmacy Abdelhadi V6.3.7
-- Returns + dashboard profit integrity patch.
-- Does not drop existing application functions.
BEGIN;

-- Authoritative financial summary:
-- 1) sales = recorded invoice totals
-- 2) customer returns reduce net sales
-- 3) returned quantities reduce COGS exactly once
-- 4) profit = net sales - net COGS
CREATE OR REPLACE FUNCTION public.admin_dashboard_financial_summary(
  p_start timestamptz,
  p_end timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE
  v_sales numeric:=0; v_cost numeric:=0; v_returns numeric:=0;
  v_return_cost numeric:=0; v_purchases numeric:=0; v_profit numeric:=0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid financial period'; END IF;

  SELECT COALESCE(SUM(s.total),0) INTO v_sales
  FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end;

  -- Net COGS: sold quantity minus the quantity already returned.
  SELECT COALESCE(SUM(GREATEST(si.quantity-COALESCE(rr.returned_qty,0),0)*si.unit_cost),0)
  INTO v_cost
  FROM public.sale_items si
  JOIN public.sales s ON s.id=si.sale_id
  LEFT JOIN (
    SELECT sale_item_id,SUM(quantity) returned_qty
    FROM public.returns WHERE return_type='customer'
    GROUP BY sale_item_id
  ) rr ON rr.sale_item_id=si.id
  WHERE s.created_at>=p_start AND s.created_at<p_end;

  SELECT COALESCE(SUM(r.amount),0) INTO v_returns
  FROM public.returns r
  WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end;

  SELECT COALESCE(SUM(r.quantity*si.unit_cost),0) INTO v_return_cost
  FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id
  WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end;

  SELECT COALESCE(SUM(p.total),0) INTO v_purchases
  FROM public.purchases p WHERE p.created_at>=p_start AND p.created_at<p_end;

  v_profit := (v_sales-v_returns)-v_cost;

  RETURN jsonb_build_object(
    'sales',v_sales,
    'cost_of_goods',v_cost,
    'customer_returns',v_returns,
    'customer_return_cost',v_return_cost,
    'net_sales',GREATEST(v_sales-v_returns,0),
    'profit',v_profit,
    'margin',CASE WHEN (v_sales-v_returns)<=0 THEN 0 ELSE ROUND((v_profit/NULLIF(v_sales-v_returns,0))*100,2) END,
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

-- Only still-returnable sale items appear in the return selector.
-- The original sale_items row is retained for accounting/audit/FK integrity;
-- its displayed quantity becomes the remaining returnable quantity.
CREATE OR REPLACE FUNCTION public.admin_list_sale_items(p_start timestamptz DEFAULT NULL)
RETURNS TABLE(id uuid,sale_id uuid,product_id uuid,product_name text,quantity numeric,unit_price numeric,unit_cost numeric,created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth
AS $$
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 RETURN QUERY
 SELECT si.id,si.sale_id,si.product_id,p.name,
        GREATEST(si.quantity-COALESCE(rr.returned_qty,0),0) AS quantity,
        si.unit_price,si.unit_cost,si.created_at
 FROM public.sale_items si
 LEFT JOIN public.products p ON p.id=si.product_id
 LEFT JOIN (
   SELECT sale_item_id,SUM(quantity) returned_qty
   FROM public.returns WHERE return_type='customer'
   GROUP BY sale_item_id
 ) rr ON rr.sale_item_id=si.id
 WHERE (p_start IS NULL OR si.created_at>=p_start)
   AND GREATEST(si.quantity-COALESCE(rr.returned_qty,0),0)>0
 ORDER BY si.created_at DESC LIMIT 5000;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_sale_items(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_sale_items(timestamptz) TO authenticated;

-- Customer return: stock movement + return record + cash/debtor effect + audit,
-- with discount-aware refund amount. A fully returned line disappears from the
-- selectable sale-item list but remains in sale_items for traceability.
CREATE OR REPLACE FUNCTION public.admin_customer_return(
  p_sale_item_id uuid,
  p_quantity numeric,
  p_reason text DEFAULT 'مرتجع من الزبون'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth
AS $$
DECLARE
  v record; v_returned numeric; v_remaining numeric; v_amount numeric;
  v_gross numeric; v_factor numeric;
  v_cash_id uuid; v_tx uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF COALESCE(p_quantity,0)<=0 THEN RAISE EXCEPTION 'كمية المرتجع يجب أن تكون أكبر من صفر'; END IF;

  SELECT si.id,si.sale_id,si.product_id,si.batch_id,si.quantity,si.unit_price,si.unit_cost,
         s.payment_method,s.debtor_id,s.total AS sale_total,COALESCE(s.discount,0) AS discount
  INTO v
  FROM public.sale_items si JOIN public.sales s ON s.id=si.sale_id
  WHERE si.id=p_sale_item_id FOR UPDATE OF si;
  IF NOT FOUND THEN RAISE EXCEPTION 'صنف البيع غير موجود'; END IF;

  SELECT COALESCE(SUM(r.quantity),0) INTO v_returned
  FROM public.returns r WHERE r.return_type='customer' AND r.sale_item_id=v.id;
  v_remaining:=v.quantity-v_returned;
  IF p_quantity>v_remaining+0.000001 THEN
    RAISE EXCEPTION 'كمية المرتجع تتجاوز الكمية المتبقية القابلة للإرجاع: %',GREATEST(v_remaining,0);
  END IF;

  -- Prorate invoice discount across this sale line so a full invoice return
  -- cannot create a refund larger than the recorded invoice total.
  SELECT COALESCE(SUM(x.quantity*x.unit_price),0) INTO v_gross
  FROM public.sale_items x WHERE x.sale_id=v.sale_id;
  v_factor:=CASE WHEN v_gross>0 THEN GREATEST(0,1-(v.discount/v_gross)) ELSE 1 END;
  v_amount:=ROUND(p_quantity*v.unit_price*v_factor,2);

  UPDATE public.batches SET quantity=quantity+p_quantity WHERE id=v.batch_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'دفعة البيع الأصلية غير موجودة'; END IF;

  INSERT INTO public.returns(return_type,sale_id,sale_item_id,product_id,batch_id,quantity,amount,reason,created_by)
  VALUES('customer',v.sale_id,v.id,v.product_id,v.batch_id,p_quantity,v_amount,COALESCE(p_reason,'مرتجع من الزبون'),auth.uid());

  INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by)
  VALUES(v.product_id,v.batch_id,'customer_return',p_quantity,v.sale_id,COALESCE(p_reason,'مرتجع من الزبون'),auth.uid());

  IF v.payment_method='cash' THEN
    INSERT INTO public.cashbox_entries(entry_type,amount,description,sale_id,created_by)
    VALUES('customer_return_refund',-abs(v_amount),'استرداد مرتجع زبون',v.sale_id,auth.uid()) RETURNING id INTO v_cash_id;
  ELSIF v.payment_method='credit' AND v.debtor_id IS NOT NULL THEN
    INSERT INTO public.debtor_transactions(debtor_id,transaction_type,sale_id,amount,debit,credit,payment_method,notes,created_by)
    VALUES(v.debtor_id,'adjustment',v.sale_id,v_amount,0,v_amount,'credit','تخفيض دين بسبب مرتجع زبون',auth.uid()) RETURNING id INTO v_tx;
  END IF;

  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'customer_return','sale',v.sale_id,jsonb_build_object(
    'sale_item_id',v.id,'product_id',v.product_id,'quantity',p_quantity,'amount',v_amount,
    'payment_method',v.payment_method,'cashbox_entry_id',v_cash_id,'debtor_transaction_id',v_tx,
    'remaining_returnable',v_remaining-p_quantity,'reason',p_reason));

  RETURN jsonb_build_object('sale_id',v.sale_id,'sale_item_id',v.id,'quantity',p_quantity,'amount',v_amount,
    'remaining_returnable',v_remaining-p_quantity,'cashbox_entry_id',v_cash_id,'debtor_transaction_id',v_tx);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_customer_return(uuid,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_customer_return(uuid,numeric,text) TO authenticated;

-- Repair missing stock-movement records for historical returns without blindly
-- duplicating already recorded quantities.
WITH expected AS (
 SELECT r.return_type,r.product_id,r.batch_id,r.sale_id,r.purchase_id,
        SUM(r.quantity) qty
 FROM public.returns r
 GROUP BY r.return_type,r.product_id,r.batch_id,r.sale_id,r.purchase_id
), existing AS (
 SELECT sm.movement_type,sm.product_id,sm.batch_id,sm.reference_id,SUM(sm.quantity) qty
 FROM public.stock_movements sm
 WHERE sm.movement_type IN ('customer_return','supplier_return')
 GROUP BY sm.movement_type,sm.product_id,sm.batch_id,sm.reference_id
)
INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by)
SELECT e.product_id,e.batch_id,
       CASE WHEN e.return_type='customer' THEN 'customer_return' ELSE 'supplier_return' END,
       GREATEST(e.qty-COALESCE(x.qty,0),0),CASE WHEN e.return_type='customer' THEN e.sale_id ELSE e.purchase_id END,
       'مزامنة سجل المرتجع مع حركة المخزون',auth.uid()
FROM expected e
LEFT JOIN existing x ON x.product_id=e.product_id AND x.batch_id=e.batch_id
 AND x.reference_id=CASE WHEN e.return_type='customer' THEN e.sale_id ELSE e.purchase_id END
 AND x.movement_type=CASE WHEN e.return_type='customer' THEN 'customer_return' ELSE 'supplier_return' END
WHERE e.qty>COALESCE(x.qty,0);

COMMIT;
