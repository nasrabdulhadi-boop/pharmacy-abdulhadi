-- Pharmacy Abdelhadi V6.4.13
-- Invoice-level purchase discount: percent or Syrian pounds.
-- Safe migration: adds only discount metadata to purchases and a new purchase RPC.
-- Existing purchase records are preserved and treated as no-discount invoices.

BEGIN;

ALTER TABLE public.purchases
  ADD COLUMN IF NOT EXISTS subtotal numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS discount_type text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS discount_value numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS discount_amount numeric NOT NULL DEFAULT 0;

UPDATE public.purchases
SET subtotal = COALESCE(NULLIF(subtotal,0), COALESCE(total,0)),
    discount_type = COALESCE(NULLIF(discount_type,''),'none'),
    discount_value = GREATEST(COALESCE(discount_value,0),0),
    discount_amount = GREATEST(COALESCE(discount_amount,0),0)
WHERE subtotal = 0 OR subtotal IS NULL OR discount_type IS NULL OR discount_type='';

ALTER TABLE public.purchases DROP CONSTRAINT IF EXISTS purchases_discount_type_check;
ALTER TABLE public.purchases ADD CONSTRAINT purchases_discount_type_check
  CHECK (discount_type IN ('none','percent','amount'));

ALTER TABLE public.purchases DROP CONSTRAINT IF EXISTS purchases_discount_value_nonnegative_check;
ALTER TABLE public.purchases ADD CONSTRAINT purchases_discount_value_nonnegative_check
  CHECK (discount_value >= 0);

ALTER TABLE public.purchases DROP CONSTRAINT IF EXISTS purchases_discount_amount_valid_check;
ALTER TABLE public.purchases ADD CONSTRAINT purchases_discount_amount_valid_check
  CHECK (discount_amount >= 0 AND discount_amount <= subtotal AND total >= 0);

-- New RPC so the existing purchase RPC remains untouched and backward-compatible.
CREATE OR REPLACE FUNCTION public.admin_create_purchase_with_payment_discount(
  p_supplier_id uuid DEFAULT NULL,
  p_new_supplier jsonb DEFAULT NULL,
  p_invoice_number text DEFAULT NULL,
  p_invoice_date date DEFAULT CURRENT_DATE,
  p_notes text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_payment_amount numeric DEFAULT 0,
  p_payment_method text DEFAULT 'cash',
  p_payment_notes text DEFAULT NULL,
  p_discount_type text DEFAULT 'none',
  p_discount_value numeric DEFAULT 0
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
  v_subtotal numeric := 0;
  v_discount_value numeric := GREATEST(COALESCE(p_discount_value,0),0);
  v_discount_amount numeric := 0;
  v_total numeric := 0;
  v_paid numeric := GREATEST(COALESCE(p_payment_amount,0),0);
  v_due numeric := 0;
  v_new_name text;
  v_new_phone text;
  v_new_address text;
  v_new_notes text;
  v_discount_type text := COALESCE(NULLIF(trim(p_discount_type),''),'none');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  IF v_discount_type NOT IN ('none','percent','amount') THEN
    RAISE EXCEPTION 'نوع الخصم غير صالح';
  END IF;
  IF v_discount_value < 0 THEN
    RAISE EXCEPTION 'قيمة الخصم لا يمكن أن تكون سالبة';
  END IF;
  IF v_discount_type='percent' AND v_discount_value > 100 THEN
    RAISE EXCEPTION 'نسبة الخصم يجب أن تكون بين 0 و100٪';
  END IF;
  IF v_discount_type='none' THEN
    v_discount_value := 0;
  END IF;
  IF p_payment_method NOT IN ('cash','other') THEN
    RAISE EXCEPTION 'طريقة الدفع غير صالحة';
  END IF;

  IF v_supplier_id IS NULL THEN
    IF p_new_supplier IS NULL OR jsonb_typeof(p_new_supplier) <> 'object' THEN
      RAISE EXCEPTION 'يجب اختيار مورد أو إدخال بيانات مورد جديد';
    END IF;
    v_new_name := NULLIF(trim(COALESCE(p_new_supplier->>'name','')), '');
    v_new_phone := NULLIF(trim(COALESCE(p_new_supplier->>'phone','')), '');
    v_new_address := NULLIF(trim(COALESCE(p_new_supplier->>'address','')), '');
    v_new_notes := NULLIF(trim(COALESCE(p_new_supplier->>'notes','')), '');
    IF v_new_name IS NULL THEN RAISE EXCEPTION 'اسم المورد الجديد مطلوب'; END IF;
    IF EXISTS (SELECT 1 FROM public.suppliers WHERE lower(trim(name))=lower(v_new_name)) THEN
      RAISE EXCEPTION 'يوجد مورد بهذا الاسم مسبقاً. اختر المورد الموجود بدلاً من إنشاء نسخة مكررة';
    END IF;
    INSERT INTO public.suppliers(name,phone,address,notes)
    VALUES(v_new_name,v_new_phone,v_new_address,v_new_notes)
    RETURNING id,name INTO v_supplier_id,v_supplier_name;
    INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
    VALUES(auth.uid(),'admin_create_supplier','supplier',v_supplier_id,
      jsonb_build_object('name',v_new_name,'phone',v_new_phone,'address',v_new_address,'notes',v_new_notes,'source','purchase_invoice'));
  ELSE
    SELECT name INTO v_supplier_name FROM public.suppliers WHERE id=v_supplier_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier not found'; END IF;
  END IF;

  -- This remains the single source for item/batch/stock creation.
  v_purchase := public.admin_create_purchase(
    v_supplier_id,
    p_invoice_number,
    COALESCE(p_invoice_date,CURRENT_DATE),
    p_notes,
    p_items
  );

  v_subtotal := ROUND(COALESCE((v_purchase->>'total')::numeric,0),2);
  IF v_discount_type='percent' THEN
    v_discount_amount := ROUND(v_subtotal * v_discount_value / 100,2);
  ELSIF v_discount_type='amount' THEN
    v_discount_amount := ROUND(v_discount_value,2);
  ELSE
    v_discount_amount := 0;
  END IF;
  IF v_discount_amount > v_subtotal THEN
    RAISE EXCEPTION 'قيمة الخصم لا يمكن أن تتجاوز إجمالي الفاتورة';
  END IF;
  v_total := ROUND(GREATEST(v_subtotal-v_discount_amount,0),2);

  UPDATE public.purchases
  SET subtotal=v_subtotal,
      discount_type=v_discount_type,
      discount_value=v_discount_value,
      discount_amount=v_discount_amount,
      total=v_total
  WHERE id=(v_purchase->>'id')::uuid;

  IF v_paid > v_total THEN
    RAISE EXCEPTION 'المبلغ المدفوع أكبر من إجمالي الفاتورة بعد الخصم: %', v_total;
  END IF;
  v_due := GREATEST(v_total-v_paid,0);

  IF v_paid > 0 THEN
    v_payment := public.admin_record_supplier_payment(
      v_supplier_id,
      v_paid,
      (v_purchase->>'id')::uuid,
      p_payment_method,
      p_payment_notes
    );
  ELSE
    PERFORM public.admin_refresh_purchase_balance((v_purchase->>'id')::uuid);
  END IF;

  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'admin_create_purchase_discount','purchase',(v_purchase->>'id')::uuid,
    jsonb_build_object('subtotal',v_subtotal,'discount_type',v_discount_type,'discount_value',v_discount_value,'discount_amount',v_discount_amount,'total_after_discount',v_total));

  RETURN jsonb_build_object(
    'id',(v_purchase->>'id')::uuid,
    'public_code',v_purchase->>'public_code',
    'supplier_id',v_supplier_id,
    'supplier_name',v_supplier_name,
    'subtotal',v_subtotal,
    'discount_type',v_discount_type,
    'discount_value',v_discount_value,
    'discount_amount',v_discount_amount,
    'total',v_total,
    'paid_amount',v_paid,
    'due_amount',v_due,
    'payment_method',CASE WHEN v_paid>0 THEN p_payment_method ELSE NULL END,
    'payment',v_payment
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_purchase_with_payment_discount(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_purchase_with_payment_discount(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric) TO authenticated;

-- Purchase list: preserve all existing fields and expose discount details.
DROP FUNCTION IF EXISTS public.admin_list_purchases();
CREATE OR REPLACE FUNCTION public.admin_list_purchases()
RETURNS TABLE(
  id uuid, supplier_id uuid, supplier_name text, invoice_number text, invoice_date date,
  total numeric, subtotal numeric, discount_type text, discount_value numeric, discount_amount numeric,
  status text, notes text, created_at timestamptz, item_count bigint, bonus_quantity numeric,
  paid_amount numeric, due_amount numeric, payment_status text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
  SELECT p.id,p.supplier_id,s.name,p.invoice_number,p.invoice_date,p.total,
         COALESCE(p.subtotal,p.total),COALESCE(p.discount_type,'none'),COALESCE(p.discount_value,0),COALESCE(p.discount_amount,0),
         p.status,p.notes,p.created_at,COUNT(pi.id)::bigint,COALESCE(SUM(pi.bonus_quantity),0),
         p.paid_amount,p.due_amount,p.payment_status
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
    'invoice_date',p.invoice_date,'subtotal',COALESCE(p.subtotal,p.total),'discount_type',COALESCE(p.discount_type,'none'),
    'discount_value',COALESCE(p.discount_value,0),'discount_amount',COALESCE(p.discount_amount,0),'total',p.total,
    'paid_amount',p.paid_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,
    'status',p.status,'notes',p.notes,'created_at',p.created_at,
    'bonus_quantity',COALESCE((SELECT SUM(pi2.bonus_quantity) FROM public.purchase_items pi2 WHERE pi2.purchase_id=p.id),0),
    'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',pi.id,'product_id',pi.product_id,'product_name',pr.name,'barcode',pr.barcode,
      'active_ingredient',pr.active_ingredient,'quantity',pi.quantity,'bonus_quantity',pi.bonus_quantity,
      'total_quantity',pi.quantity+pi.bonus_quantity,'purchase_price',pi.purchase_price,
      'sale_price',pi.sale_price,'expiry_date',pi.expiry_date,'batch_id',pi.batch_id
    ) ORDER BY pi.id) FROM public.purchase_items pi JOIN public.products pr ON pr.id=pi.product_id WHERE pi.purchase_id=p.id),'[]'::jsonb),
    'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',sp.id,'amount',sp.amount,'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
      'cashbox_entry_id',sp.cashbox_entry_id
    ) ORDER BY sp.created_at DESC)
    FROM public.supplier_payment_allocations spa JOIN public.supplier_payments sp ON sp.id=spa.payment_id
    WHERE spa.purchase_id=p.id),'[]'::jsonb)
  ) INTO v
  FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id
  WHERE p.id=p_purchase_id;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_get_purchase_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_purchase_detail(uuid) TO authenticated;

COMMIT;
