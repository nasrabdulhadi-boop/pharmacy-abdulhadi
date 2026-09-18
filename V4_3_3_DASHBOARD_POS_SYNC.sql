-- v4.3.3: admin-safe sales visibility + dashboard/alert support
-- Run once in Supabase SQL Editor.

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

-- Verification (optional):
-- SELECT public.is_admin();
-- SELECT count(*) FROM public.sales;
