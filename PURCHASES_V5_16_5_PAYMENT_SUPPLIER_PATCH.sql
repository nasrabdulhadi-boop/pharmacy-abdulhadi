-- Pharmacy Abdelhadi — V5.16.5 targeted patch (FIXED)
-- Scope: purchase invoice supplier creation + payment at invoice time.
-- Keeps the existing admin_create_purchase() and admin_record_supplier_payment()
-- intact and composes them atomically inside one transaction.

CREATE OR REPLACE FUNCTION public.admin_create_purchase_with_payment(
  p_supplier_id uuid DEFAULT NULL,
  p_new_supplier jsonb DEFAULT NULL,
  p_invoice_number text DEFAULT NULL,
  p_invoice_date date DEFAULT CURRENT_DATE,
  p_notes text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_payment_amount numeric DEFAULT 0,
  p_payment_method text DEFAULT 'cash',
  p_payment_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_supplier_id uuid := p_supplier_id;
  v_supplier_name text;
  v_purchase jsonb;
  v_payment jsonb := NULL;
  v_total numeric := 0;
  v_paid numeric := greatest(coalesce(p_payment_amount,0),0);
  v_due numeric := 0;
  v_new_name text;
  v_new_phone text;
  v_new_address text;
  v_new_notes text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  IF coalesce(v_paid,0) < 0 THEN
    RAISE EXCEPTION 'Invalid payment amount';
  END IF;

  IF p_payment_method NOT IN ('cash','other') THEN
    RAISE EXCEPTION 'طريقة الدفع غير صالحة';
  END IF;

  -- Create the supplier inside the same transaction when requested.
  IF v_supplier_id IS NULL THEN
    IF p_new_supplier IS NULL OR jsonb_typeof(p_new_supplier) <> 'object' THEN
      RAISE EXCEPTION 'يجب اختيار مورد أو إدخال بيانات مورد جديد';
    END IF;

    v_new_name := nullif(trim(coalesce(p_new_supplier->>'name','')), '');
    v_new_phone := nullif(trim(coalesce(p_new_supplier->>'phone','')), '');
    v_new_address := nullif(trim(coalesce(p_new_supplier->>'address','')), '');
    v_new_notes := nullif(trim(coalesce(p_new_supplier->>'notes','')), '');

    IF v_new_name IS NULL THEN
      RAISE EXCEPTION 'اسم المورد الجديد مطلوب';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.suppliers
      WHERE lower(trim(name)) = lower(v_new_name)
    ) THEN
      RAISE EXCEPTION 'يوجد مورد بهذا الاسم مسبقاً. اختر المورد الموجود بدلاً من إنشاء نسخة مكررة';
    END IF;

    INSERT INTO public.suppliers(name,phone,address,notes)
    VALUES(v_new_name,v_new_phone,v_new_address,v_new_notes)
    RETURNING id,name INTO v_supplier_id,v_supplier_name;

    INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
    VALUES(
      auth.uid(),'admin_create_supplier','supplier',v_supplier_id,
      jsonb_build_object('name',v_new_name,'phone',v_new_phone,'address',v_new_address,'notes',v_new_notes,'source','purchase_invoice')
    );
  ELSE
    SELECT name INTO v_supplier_name
    FROM public.suppliers
    WHERE id=v_supplier_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Supplier not found';
    END IF;
  END IF;

  -- Existing purchase RPC remains the single source for purchase/batch/stock creation.
  v_purchase := public.admin_create_purchase(
    v_supplier_id,
    p_invoice_number,
    coalesce(p_invoice_date,current_date),
    p_notes,
    p_items
  );

  v_total := coalesce((v_purchase->>'total')::numeric,0);

  IF v_paid > v_total THEN
    RAISE EXCEPTION 'المبلغ المدفوع أكبر من إجمالي الفاتورة: %', v_total;
  END IF;

  v_due := greatest(v_total-v_paid,0);

  IF v_paid > 0 THEN
    v_payment := public.admin_record_supplier_payment(
      v_supplier_id,
      v_paid,
      (v_purchase->>'id')::uuid,
      p_payment_method,
      p_payment_notes
    );
  ELSE
    -- A zero-payment invoice must still get its true outstanding balance.
    PERFORM public.admin_refresh_purchase_balance((v_purchase->>'id')::uuid);
  END IF;

  RETURN jsonb_build_object(
    'id',(v_purchase->>'id')::uuid,
    'public_code',v_purchase->>'public_code',
    'supplier_id',v_supplier_id,
    'supplier_name',v_supplier_name,
    'total',v_total,
    'paid_amount',v_paid,
    'due_amount',v_due,
    'payment_method',CASE WHEN v_paid>0 THEN p_payment_method ELSE NULL END,
    'payment',v_payment
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_purchase_with_payment(uuid,jsonb,text,date,text,jsonb,numeric,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_purchase_with_payment(uuid,jsonb,text,date,text,jsonb,numeric,text,text) TO authenticated;

COMMENT ON FUNCTION public.admin_create_purchase_with_payment(uuid,jsonb,text,date,text,jsonb,numeric,text,text)
IS 'Atomic purchase invoice creation with optional new supplier and immediate supplier payment; V5.16.5 targeted patch.';

-- PostgreSQL does not allow CREATE OR REPLACE to change a RETURNS TABLE row type.
-- Drop only the function definitions (NOT any data) before recreating them.
DROP FUNCTION IF EXISTS public.admin_list_purchases();
DROP FUNCTION IF EXISTS public.admin_get_purchase_detail(uuid);

-- Expose payment state in purchase list/detail.
CREATE OR REPLACE FUNCTION public.admin_list_purchases()
RETURNS TABLE(
  id uuid, supplier_id uuid, supplier_name text, invoice_number text, invoice_date date,
  total numeric, status text, notes text, created_at timestamptz, item_count bigint,
  paid_amount numeric, due_amount numeric, payment_status text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
  SELECT p.id,p.supplier_id,s.name,p.invoice_number,p.invoice_date,p.total,p.status,p.notes,p.created_at,
         COUNT(pi.id)::bigint,p.paid_amount,p.due_amount,p.payment_status
  FROM public.purchases p
  LEFT JOIN public.suppliers s ON s.id=p.supplier_id
  LEFT JOIN public.purchase_items pi ON pi.purchase_id=p.id
  WHERE public.is_admin()
  GROUP BY p.id,s.name
  ORDER BY COALESCE(p.invoice_date,p.created_at::date) DESC,p.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.admin_list_purchases() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_purchases() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_get_purchase_detail(p_purchase_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
DECLARE v jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT jsonb_build_object(
    'id',p.id,'supplier_id',p.supplier_id,'supplier_name',s.name,'invoice_number',p.invoice_number,
    'invoice_date',p.invoice_date,'total',p.total,'paid_amount',p.paid_amount,'due_amount',p.due_amount,
    'payment_status',p.payment_status,'status',p.status,'notes',p.notes,'created_at',p.created_at,
    'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',pi.id,'product_id',pi.product_id,'product_name',pr.name,'barcode',pr.barcode,
      'active_ingredient',pr.active_ingredient,'quantity',pi.quantity,'purchase_price',pi.purchase_price,
      'sale_price',pi.sale_price,'expiry_date',pi.expiry_date,'batch_id',pi.batch_id
    ) ORDER BY pi.id) FROM public.purchase_items pi JOIN public.products pr ON pr.id=pi.product_id WHERE pi.purchase_id=p.id),'[]'::jsonb),
    'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',sp.id,'amount',sp.amount,'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
      'cashbox_entry_id',sp.cashbox_entry_id
    ) ORDER BY sp.created_at DESC)
    FROM public.supplier_payment_allocations spa
    JOIN public.supplier_payments sp ON sp.id=spa.payment_id
    WHERE spa.purchase_id=p.id),'[]'::jsonb)
  ) INTO v
  FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id
  WHERE p.id=p_purchase_id;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_get_purchase_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_purchase_detail(uuid) TO authenticated;
