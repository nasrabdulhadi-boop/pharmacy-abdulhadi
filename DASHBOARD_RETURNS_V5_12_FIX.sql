-- Pharmacy Abdelhadi v5.12 — Dashboard day details + safe returns
-- Run once in Supabase SQL Editor.
BEGIN;

-- 1) Make return movement types valid while preserving any existing movement types.
DO $$
DECLARE
  vals text;
  c record;
BEGIN
  SELECT string_agg(format('%L', v), ', ' ORDER BY v)
  INTO vals
  FROM (
    SELECT DISTINCT movement_type AS v FROM public.stock_movements WHERE movement_type IS NOT NULL
    UNION SELECT 'customer_return'
    UNION SELECT 'supplier_return'
  ) q;

  FOR c IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid='public.stock_movements'::regclass
      AND contype='c'
      AND conname='stock_movements_movement_type_check'
  LOOP
    EXECUTE format('ALTER TABLE public.stock_movements DROP CONSTRAINT %I', c.conname);
  END LOOP;

  EXECUTE format(
    'ALTER TABLE public.stock_movements ADD CONSTRAINT stock_movements_movement_type_check CHECK (movement_type IN (%s))',
    vals
  );
END $$;

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

COMMIT;
