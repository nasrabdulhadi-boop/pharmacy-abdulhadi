-- Pharmacy Abdelhadi v4.3.4
-- Fixes report support and adds safe admin deletion for orders/batches.
-- Run once in Supabase SQL Editor while logged in as the project owner.

-- 1) Delete an online order and its order items, without deleting the customer.
CREATE OR REPLACE FUNCTION public.admin_delete_order(p_order_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_code text;
  v_customer_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  SELECT public_code, customer_id
  INTO v_code, v_customer_id
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  DELETE FROM public.order_items WHERE order_id = p_order_id;
  DELETE FROM public.orders WHERE id = p_order_id;

  INSERT INTO public.audit_logs(user_id, action, entity_type, entity_id, details)
  VALUES (
    auth.uid(),
    'admin_delete_order',
    'order',
    p_order_id,
    jsonb_build_object('public_code', v_code, 'customer_id', v_customer_id)
  );

  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_delete_order(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_order(uuid) TO authenticated;

-- 2) Delete a batch only when it has never been used by a sale.
--    Stock movement history for a standalone batch is removed with the batch.
--    Sale-linked batches are protected so sales history cannot be broken.
CREATE OR REPLACE FUNCTION public.admin_delete_batch(p_batch_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_product_id uuid;
  v_batch_number text;
  v_quantity numeric;
  v_product_name text;
  v_sales_count bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  SELECT b.product_id, b.batch_number, b.quantity, p.name
  INTO v_product_id, v_batch_number, v_quantity, v_product_name
  FROM public.batches b
  LEFT JOIN public.products p ON p.id = b.product_id
  WHERE b.id = p_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  SELECT count(*) INTO v_sales_count
  FROM public.sale_items
  WHERE batch_id = p_batch_id;

  IF v_sales_count > 0 THEN
    RAISE EXCEPTION 'لا يمكن حذف هذه الدفعة لأنها مرتبطة بمبيعات سابقة. للحفاظ على سجل المبيعات، عدّل الكمية بدلاً من حذفها.';
  END IF;

  DELETE FROM public.stock_movements WHERE batch_id = p_batch_id;
  DELETE FROM public.batches WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(user_id, action, entity_type, entity_id, details)
  VALUES (
    auth.uid(),
    'admin_delete_batch',
    'batch',
    p_batch_id,
    jsonb_build_object(
      'product_id', v_product_id,
      'product_name', v_product_name,
      'batch_number', v_batch_number,
      'quantity_before_delete', v_quantity
    )
  );

  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_delete_batch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_batch(uuid) TO authenticated;

-- 3) Ensure the audit table has the details column used by the Security page.
ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS details jsonb;

-- 4) Report RPCs (idempotent). These are the admin-safe sources used by v4.3.4.
CREATE OR REPLACE FUNCTION public.admin_list_sales(p_start timestamptz DEFAULT NULL)
RETURNS TABLE(
  id uuid,
  customer_id uuid,
  subtotal numeric,
  discount numeric,
  total numeric,
  created_at timestamptz,
  created_by uuid
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  RETURN QUERY
  SELECT s.id,s.customer_id,s.subtotal,s.discount,s.total,s.created_at,s.created_by
  FROM public.sales s
  WHERE p_start IS NULL OR s.created_at >= p_start
  ORDER BY s.created_at DESC
  LIMIT 1000;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_sales(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_sales(timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_sale_items(p_start timestamptz DEFAULT NULL)
RETURNS TABLE(
  id uuid,
  sale_id uuid,
  product_id uuid,
  product_name text,
  quantity numeric,
  unit_price numeric,
  unit_cost numeric,
  created_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  RETURN QUERY
  SELECT si.id,si.sale_id,si.product_id,p.name,si.quantity,si.unit_price,si.unit_cost,si.created_at
  FROM public.sale_items si
  LEFT JOIN public.products p ON p.id=si.product_id
  WHERE p_start IS NULL OR si.created_at >= p_start
  ORDER BY si.created_at DESC
  LIMIT 5000;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_sale_items(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_sale_items(timestamptz) TO authenticated;

-- 5) Record report-related access in the audit log is intentionally not automatic;
--    the Security page displays actual data-changing operations.
