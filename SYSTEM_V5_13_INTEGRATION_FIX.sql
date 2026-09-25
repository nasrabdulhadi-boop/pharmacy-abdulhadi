-- Pharmacy Abdelhadi v5.13 — system integration / health repair
-- Run ONCE in Supabase SQL Editor after the V5.12.x versions.
-- This patch is idempotent and focuses on restoring cross-module compatibility.
BEGIN;

-- Minimal safety bootstrap for modules that may have been partially migrated.
CREATE TABLE IF NOT EXISTS public.cashbox_entries(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_type text NOT NULL,
  amount numeric NOT NULL CHECK(amount<>0),
  description text,
  sale_id uuid REFERENCES public.sales(id) ON DELETE SET NULL,
  debtor_transaction_id uuid REFERENCES public.debtor_transactions(id) ON DELETE SET NULL,
  purchase_id uuid REFERENCES public.purchases(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.audit_logs(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id),
  action text NOT NULL,
  entity_type text,
  entity_id uuid,
  details jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.returns(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  return_type text NOT NULL CHECK(return_type IN ('customer','supplier')),
  sale_id uuid REFERENCES public.sales(id) ON DELETE SET NULL,
  sale_item_id uuid REFERENCES public.sale_items(id) ON DELETE SET NULL,
  purchase_id uuid REFERENCES public.purchases(id) ON DELETE SET NULL,
  product_id uuid NOT NULL REFERENCES public.products(id),
  batch_id uuid REFERENCES public.batches(id) ON DELETE SET NULL,
  quantity numeric NOT NULL CHECK(quantity>0),
  amount numeric NOT NULL DEFAULT 0,
  reason text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- =========================================================
-- 1) Core compatibility columns / constraints
-- =========================================================
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS active boolean NOT NULL DEFAULT true;
UPDATE public.products SET active=true WHERE active IS NULL;

-- Keep the stock movement history while allowing explicit return movements.
DO $$
DECLARE vals text;
BEGIN
  SELECT string_agg(format('%L',v),', ' ORDER BY v) INTO vals
  FROM (
    SELECT DISTINCT movement_type v FROM public.stock_movements WHERE movement_type IS NOT NULL
    UNION SELECT 'customer_return'
    UNION SELECT 'supplier_return'
    UNION SELECT 'sale'
    UNION SELECT 'purchase'
    UNION SELECT 'adjustment'
  ) q;
  ALTER TABLE public.stock_movements DROP CONSTRAINT IF EXISTS stock_movements_movement_type_check;
  EXECUTE format('ALTER TABLE public.stock_movements ADD CONSTRAINT stock_movements_movement_type_check CHECK (movement_type IN (%s))',vals);
END $$;

-- Cashbox return type used by cash customer refunds.
DO $$
DECLARE vals text;
BEGIN
  SELECT string_agg(format('%L',v),', ' ORDER BY v) INTO vals
  FROM (
    SELECT DISTINCT entry_type v FROM public.cashbox_entries WHERE entry_type IS NOT NULL
    UNION SELECT 'sale_cash'
    UNION SELECT 'debtor_payment'
    UNION SELECT 'expense'
    UNION SELECT 'income'
    UNION SELECT 'purchase_payment'
    UNION SELECT 'withdrawal'
    UNION SELECT 'deposit'
    UNION SELECT 'adjustment'
    UNION SELECT 'customer_return_refund'
  ) q;
  ALTER TABLE public.cashbox_entries DROP CONSTRAINT IF EXISTS cashbox_entries_entry_type_check;
  EXECUTE format('ALTER TABLE public.cashbox_entries ADD CONSTRAINT cashbox_entries_entry_type_check CHECK (entry_type IN (%s))',vals);
END $$;

-- =========================================================
-- 2) Products: one admin source for pharmacy + site catalog
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_get_products()
RETURNS SETOF public.products
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
  SELECT p.* FROM public.products p
  WHERE public.is_admin() AND COALESCE(p.active,true)=true
  ORDER BY p.name;
$$;
REVOKE ALL ON FUNCTION public.admin_get_products() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_products() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_search_pos_products(
  p_query text,
  p_limit integer DEFAULT 30
)
RETURNS TABLE(
  id uuid,name text,barcode text,active_ingredient text,strength text,dosage_form text,
  unit text,sale_price numeric,purchase_price numeric,parts_per_unit numeric,stock numeric,expiry_date date
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
  WITH q AS (SELECT trim(COALESCE(p_query,'')) AS t)
  SELECT p.id,p.name,p.barcode,p.active_ingredient,p.strength,p.dosage_form,p.unit,
         p.sale_price,p.purchase_price,p.parts_per_unit,
         COALESCE(SUM(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=current_date) THEN b.quantity ELSE 0 END),0) AS stock,
         MIN(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=current_date) THEN b.expiry_date END) AS expiry_date
  FROM public.products p CROSS JOIN q
  LEFT JOIN public.batches b ON b.product_id=p.id
  WHERE public.is_admin() AND COALESCE(p.active,true)=true
    AND q.t<>''
    AND (
      p.barcode=q.t OR p.barcode ILIKE q.t||'%' OR
      p.name ILIKE '%'||q.t||'%' OR
      COALESCE(p.active_ingredient,'') ILIKE '%'||q.t||'%'
    )
  GROUP BY p.id,q.t
  ORDER BY
    CASE WHEN p.barcode=q.t THEN 0
         WHEN lower(p.name)=lower(q.t) THEN 1
         WHEN lower(COALESCE(p.active_ingredient,''))=lower(q.t) THEN 2
         WHEN lower(p.name) LIKE lower(q.t)||'%' THEN 3
         WHEN lower(COALESCE(p.active_ingredient,'')) LIKE lower(q.t)||'%' THEN 4
         ELSE 5 END,
    MIN(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=current_date) THEN b.expiry_date END) NULLS LAST,
    p.name
  LIMIT GREATEST(1,LEAST(COALESCE(p_limit,30),100));
$$;
REVOKE ALL ON FUNCTION public.admin_search_pos_products(text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_pos_products(text,integer) TO authenticated;

-- 2) Dashboard: exact sales details for a device-local day window.
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
  IF p_start IS NULL OR p_end IS NULL OR p_end <= p_start THEN RAISE EXCEPTION 'Invalid dashboard day range'; END IF;

  SELECT jsonb_build_object(
    'start',p_start,
    'end',p_end,
    'summary',jsonb_build_object(
      'sales',COALESCE((SELECT SUM(s.total) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end),0),
      'cash_sales',COALESCE((SELECT SUM(s.total) FROM public.sales s WHERE s.payment_method='cash' AND s.created_at>=p_start AND s.created_at<p_end),0),
      'credit_sales',COALESCE((SELECT SUM(s.total) FROM public.sales s WHERE s.payment_method='credit' AND s.created_at>=p_start AND s.created_at<p_end),0),
      'profit',COALESCE((SELECT SUM((si.unit_price-si.unit_cost)*si.quantity) FROM public.sale_items si WHERE si.created_at>=p_start AND si.created_at<p_end),0),
      'invoice_count',COALESCE((SELECT COUNT(*) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end),0)
    ),
    'sales',COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id',s.id,
          'created_at',s.created_at,
          'subtotal',s.subtotal,
          'discount',s.discount,
          'total',s.total,
          'payment_method',s.payment_method,
          'paid_amount',s.paid_amount,
          'due_amount',s.due_amount,
          'payment_notes',s.payment_notes,
          'debtor_name',d.name,
          'customer_name',c.name,
          'items',COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
              'product_name',p.name,
              'barcode',p.barcode,
              'strength',p.strength,
              'dosage_form',p.dosage_form,
              'quantity',si.quantity,
              'unit_price',si.unit_price,
              'unit_cost',si.unit_cost,
              'line_total',si.quantity*si.unit_price
            ) ORDER BY si.created_at, p.name
            )
            FROM public.sale_items si
            LEFT JOIN public.products p ON p.id=si.product_id
            WHERE si.sale_id=s.id
          ),'[]'::jsonb)
        ) ORDER BY s.created_at DESC
      )
      FROM public.sales s
      LEFT JOIN public.debtors d ON d.id=s.debtor_id
      LEFT JOIN public.customers c ON c.id=s.customer_id
      WHERE s.created_at>=p_start AND s.created_at<p_end
    ),'[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_dashboard_sales_day(timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_sales_day(timestamptz,timestamptz) TO authenticated;

-- 3) Return options: purchase invoice -> purchase item -> current batch.
CREATE OR REPLACE FUNCTION public.admin_supplier_return_options()
RETURNS TABLE(
  purchase_id uuid,
  invoice_number text,
  supplier_name text,
  purchase_date date,
  purchase_item_id uuid,
  batch_id uuid,
  product_id uuid,
  product_name text,
  purchased_quantity numeric,
  available_quantity numeric,
  purchase_price numeric,
  expiry_date date
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=public,auth
AS $$
  SELECT p.id,p.invoice_number,s.name,p.invoice_date,pi.id,b.id,pr.id,pr.name,
         pi.quantity,COALESCE(b.quantity,0),pi.purchase_price,b.expiry_date
  FROM public.purchase_items pi
  JOIN public.purchases p ON p.id=pi.purchase_id
  JOIN public.products pr ON pr.id=pi.product_id
  LEFT JOIN public.suppliers s ON s.id=p.supplier_id
  LEFT JOIN public.batches b ON b.id=pi.batch_id
  WHERE public.is_admin()
    AND b.id IS NOT NULL
    AND COALESCE(b.quantity,0)>0
  ORDER BY p.created_at DESC NULLS LAST,pr.name;
$$;
REVOKE ALL ON FUNCTION public.admin_supplier_return_options() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_supplier_return_options() TO authenticated;

-- 4) Atomic supplier return for one product, 2/3 products, selected products, or the
--    full remaining stock of a purchase invoice. Historical invoices are retained.
CREATE OR REPLACE FUNCTION public.admin_supplier_return_bundle(
  p_purchase_id uuid,
  p_mode text,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_reason text DEFAULT 'مرتجع إلى المورد'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE
  r record;
  it jsonb;
  v_batch uuid;
  v_qty numeric;
  v_total numeric:=0;
  v_count integer:=0;
  v_items jsonb:='[]'::jsonb;
  v_purchase_exists boolean;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_purchase_id IS NULL OR p_mode NOT IN ('full','count_1','count_2','count_3','selected') THEN RAISE EXCEPTION 'نوع المرتجع غير صالح'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.purchases WHERE id=p_purchase_id) THEN RAISE EXCEPTION 'فاتورة الشراء غير موجودة'; END IF;
  IF p_mode<>'full' AND jsonb_typeof(COALESCE(p_items,'[]'::jsonb))<>'array' THEN RAISE EXCEPTION 'بيانات المنتجات غير صالحة'; END IF;

  IF p_mode='full' THEN
    FOR r IN
      SELECT pi.id purchase_item_id,b.id batch_id,b.product_id,pr.name product_name,
             LEAST(COALESCE(b.quantity,0),GREATEST(pi.quantity-COALESCE((SELECT SUM(rr.quantity) FROM public.returns rr WHERE rr.return_type='supplier' AND rr.batch_id=b.id),0),0)) returnable_qty,
             b.purchase_price
      FROM public.purchase_items pi
      JOIN public.batches b ON b.id=pi.batch_id
      JOIN public.products pr ON pr.id=pi.product_id
      WHERE pi.purchase_id=p_purchase_id AND COALESCE(b.quantity,0)>0
      FOR UPDATE OF b
    LOOP
      IF r.returnable_qty<=0 THEN CONTINUE; END IF;
      UPDATE public.batches SET quantity=quantity-r.returnable_qty WHERE id=r.batch_id;
      INSERT INTO public.returns(return_type,purchase_id,product_id,batch_id,quantity,amount,reason,created_by)
      VALUES('supplier',p_purchase_id,r.product_id,r.batch_id,r.returnable_qty,r.returnable_qty*r.purchase_price,COALESCE(p_reason,'مرتجع إلى المورد'),auth.uid());
      INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by)
      VALUES(r.product_id,r.batch_id,'supplier_return',-r.returnable_qty,p_purchase_id,COALESCE(p_reason,'مرتجع إلى المورد'),auth.uid());
      v_total:=v_total+r.returnable_qty*r.purchase_price; v_count:=v_count+1;
      v_items:=v_items||jsonb_build_object('product_name',r.product_name,'quantity',r.returnable_qty,'amount',r.returnable_qty*r.purchase_price);
    END LOOP;
  ELSE
    IF p_mode='count_1' AND jsonb_array_length(COALESCE(p_items,'[]'::jsonb)) <> 1 THEN
      RAISE EXCEPTION 'يجب تحديد منتج واحد فقط';
    END IF;
    IF p_mode='count_2' AND jsonb_array_length(COALESCE(p_items,'[]'::jsonb)) <> 2 THEN
      RAISE EXCEPTION 'يجب تحديد منتجين فقط';
    END IF;
    IF p_mode='count_3' AND jsonb_array_length(COALESCE(p_items,'[]'::jsonb)) <> 3 THEN
      RAISE EXCEPTION 'يجب تحديد ثلاثة منتجات فقط';
    END IF;
    IF p_mode='selected' AND jsonb_array_length(COALESCE(p_items,'[]'::jsonb)) < 1 THEN
      RAISE EXCEPTION 'يجب تحديد منتج واحد على الأقل';
    END IF;

    FOR it IN SELECT value FROM jsonb_array_elements(COALESCE(p_items,'[]'::jsonb)) LOOP
      v_batch:=NULLIF(it->>'batch_id','')::uuid;
      v_qty:=COALESCE((it->>'quantity')::numeric,0);
      IF v_batch IS NULL OR v_qty<=0 THEN RAISE EXCEPTION 'كل منتج مرتجع يحتاج دفعة وكمية موجبة'; END IF;
      SELECT b.id,b.product_id,pr.name,b.quantity,b.purchase_price,pi.quantity
      INTO r
      FROM public.batches b
      JOIN public.purchase_items pi ON pi.batch_id=b.id AND pi.purchase_id=p_purchase_id
      JOIN public.products pr ON pr.id=b.product_id
      WHERE b.id=v_batch
      FOR UPDATE OF b;
      IF NOT FOUND THEN RAISE EXCEPTION 'الدفعة المحددة ليست ضمن فاتورة الشراء'; END IF;
      IF v_qty>COALESCE(r.quantity,0) THEN RAISE EXCEPTION 'كمية المرتجع أكبر من الرصيد المتاح للمنتج: %',r.name; END IF;
      IF v_qty > GREATEST(r.quantity-COALESCE((SELECT SUM(rr.quantity) FROM public.returns rr WHERE rr.return_type='supplier' AND rr.batch_id=v_batch),0),0) THEN
        RAISE EXCEPTION 'كمية المرتجع تتجاوز الكمية القابلة للإرجاع للمنتج: %',r.name;
      END IF;
      UPDATE public.batches SET quantity=quantity-v_qty WHERE id=v_batch;
      INSERT INTO public.returns(return_type,purchase_id,product_id,batch_id,quantity,amount,reason,created_by)
      VALUES('supplier',p_purchase_id,r.product_id,v_batch,v_qty,v_qty*r.purchase_price,COALESCE(p_reason,'مرتجع إلى المورد'),auth.uid());
      INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by)
      VALUES(r.product_id,v_batch,'supplier_return',-v_qty,p_purchase_id,COALESCE(p_reason,'مرتجع إلى المورد'),auth.uid());
      v_total:=v_total+v_qty*r.purchase_price; v_count:=v_count+1;
      v_items:=v_items||jsonb_build_object('product_name',r.name,'quantity',v_qty,'amount',v_qty*r.purchase_price);
    END LOOP;
  END IF;

  IF v_count=0 THEN RAISE EXCEPTION 'لا توجد كمية متاحة للإرجاع في هذه الفاتورة'; END IF;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'supplier_return','purchase',p_purchase_id,jsonb_build_object('mode',p_mode,'items',v_items,'total_amount',v_total,'reason',p_reason));
  RETURN jsonb_build_object('purchase_id',p_purchase_id,'items_count',v_count,'total_amount',v_total,'items',v_items);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_supplier_return_bundle(uuid,text,jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_supplier_return_bundle(uuid,text,jsonb,text) TO authenticated;



CREATE OR REPLACE FUNCTION public.admin_list_sale_items(p_start timestamptz DEFAULT NULL)
RETURNS TABLE(id uuid,sale_id uuid,product_id uuid,product_name text,quantity numeric,unit_price numeric,unit_cost numeric,created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth
AS $$
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 RETURN QUERY SELECT si.id,si.sale_id,si.product_id,p.name,si.quantity,si.unit_price,si.unit_cost,si.created_at
 FROM public.sale_items si LEFT JOIN public.products p ON p.id=si.product_id
 WHERE p_start IS NULL OR si.created_at>=p_start
 ORDER BY si.created_at DESC LIMIT 5000;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_sale_items(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_sale_items(timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_return_list()
RETURNS TABLE(id uuid,return_type text,product_name text,quantity numeric,amount numeric,reason text,created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
 SELECT r.id,r.return_type,p.name,r.quantity,r.amount,r.reason,r.created_at
 FROM public.returns r LEFT JOIN public.products p ON p.id=r.product_id
 WHERE public.is_admin() ORDER BY r.created_at DESC LIMIT 500;
$$;
REVOKE ALL ON FUNCTION public.admin_return_list() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_return_list() TO authenticated;

-- =========================================================
-- 3) Customer return: stock + cashbox/debtor + audit in one transaction
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_customer_return(
  p_sale_item_id uuid,
  p_quantity numeric,
  p_reason text DEFAULT 'مرتجع من الزبون'
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth
AS $$
DECLARE
  v record; v_returned numeric; v_remaining numeric; v_amount numeric; v_cash_id uuid; v_tx uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF COALESCE(p_quantity,0)<=0 THEN RAISE EXCEPTION 'كمية المرتجع يجب أن تكون أكبر من صفر'; END IF;

  SELECT si.id,si.sale_id,si.product_id,si.batch_id,si.quantity,si.unit_price,
         s.payment_method,s.debtor_id,s.total AS sale_total
  INTO v
  FROM public.sale_items si JOIN public.sales s ON s.id=si.sale_id
  WHERE si.id=p_sale_item_id
  FOR UPDATE OF si;
  IF NOT FOUND THEN RAISE EXCEPTION 'صنف البيع غير موجود'; END IF;

  SELECT COALESCE(SUM(r.quantity),0) INTO v_returned
  FROM public.returns r WHERE r.return_type='customer' AND r.sale_item_id=v.id;
  v_remaining:=v.quantity-v_returned;
  IF p_quantity>v_remaining+0.000001 THEN RAISE EXCEPTION 'كمية المرتجع تتجاوز الكمية المتبقية القابلة للإرجاع: %',GREATEST(v_remaining,0); END IF;

  UPDATE public.batches SET quantity=quantity+p_quantity WHERE id=v.batch_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'دفعة البيع الأصلية غير موجودة'; END IF;

  v_amount:=p_quantity*v.unit_price;
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

  RETURN jsonb_build_object('sale_id',v.sale_id,'quantity',p_quantity,'amount',v_amount,'cashbox_entry_id',v_cash_id,'debtor_transaction_id',v_tx);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_customer_return(uuid,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_customer_return(uuid,numeric,text) TO authenticated;

-- =========================================================
-- 4) Reports: replace nested aggregate with grouped subquery
-- =========================================================
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


-- =========================================================
-- 5) RLS needed by direct admin reads / cashbox / returns / audit
-- =========================================================
ALTER TABLE public.cashbox_entries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin cashbox" ON public.cashbox_entries;
CREATE POLICY "admin cashbox" ON public.cashbox_entries FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());
ALTER TABLE public.returns ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin returns" ON public.returns;
CREATE POLICY "admin returns" ON public.returns FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin audit read" ON public.audit_logs;
CREATE POLICY "admin audit read" ON public.audit_logs FOR SELECT TO authenticated USING(public.is_admin());

-- Helpful indexes for the modules above.
CREATE INDEX IF NOT EXISTS idx_cashbox_created_type ON public.cashbox_entries(created_at DESC,entry_type);
CREATE INDEX IF NOT EXISTS idx_returns_created_type ON public.returns(created_at DESC,return_type);
CREATE INDEX IF NOT EXISTS idx_returns_sale_item ON public.returns(sale_item_id);
CREATE INDEX IF NOT EXISTS idx_products_active_name ON public.products(active,name);


-- =========================================================
-- 6) One-click integration health check for the admin
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_system_healthcheck()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
  SELECT jsonb_build_object(
    'admin',public.is_admin(),
    'tables',jsonb_build_object(
      'products',to_regclass('public.products') IS NOT NULL,
      'batches',to_regclass('public.batches') IS NOT NULL,
      'sales',to_regclass('public.sales') IS NOT NULL,
      'sale_items',to_regclass('public.sale_items') IS NOT NULL,
      'purchases',to_regclass('public.purchases') IS NOT NULL,
      'purchase_items',to_regclass('public.purchase_items') IS NOT NULL,
      'stock_movements',to_regclass('public.stock_movements') IS NOT NULL,
      'cashbox_entries',to_regclass('public.cashbox_entries') IS NOT NULL,
      'returns',to_regclass('public.returns') IS NOT NULL,
      'audit_logs',to_regclass('public.audit_logs') IS NOT NULL
    ),
    'columns',jsonb_build_object(
      'products_active',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='products' AND column_name='active'),
      'products_sale_price',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='products' AND column_name='sale_price'),
      'purchases_paid_amount',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='purchases' AND column_name='paid_amount'),
      'purchases_due_amount',EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='purchases' AND column_name='due_amount')
    ),
    'functions',jsonb_build_object(
      'admin_get_products',to_regprocedure('public.admin_get_products()') IS NOT NULL,
      'admin_search_pos_products',to_regprocedure('public.admin_search_pos_products(text,integer)') IS NOT NULL,
      'complete_sale_accounting',to_regprocedure('public.complete_sale_accounting(jsonb,numeric,text,uuid,text)') IS NOT NULL,
      'admin_customer_return',to_regprocedure('public.admin_customer_return(uuid,numeric,text)') IS NOT NULL,
      'admin_supplier_return_bundle',to_regprocedure('public.admin_supplier_return_bundle(uuid,text,jsonb,text)') IS NOT NULL,
      'admin_accounting_report',to_regprocedure('public.admin_accounting_report(timestamp with time zone,timestamp with time zone,timestamp with time zone,timestamp with time zone)') IS NOT NULL,
      'admin_cashbox_summary',to_regprocedure('public.admin_cashbox_summary(timestamp with time zone,timestamp with time zone)') IS NOT NULL
    )
  );
$$;
REVOKE ALL ON FUNCTION public.admin_system_healthcheck() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_system_healthcheck() TO authenticated;

COMMIT;
