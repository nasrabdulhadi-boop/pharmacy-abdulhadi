-- v4.2.5: robust admin order status updates + richer public tracking
CREATE OR REPLACE FUNCTION public.admin_update_order_status(
  p_order_id uuid,
  p_status text
)
RETURNS TABLE(id uuid, status text, updated_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_status text := lower(trim(coalesce(p_status,'')));
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;
  IF v_status NOT IN ('new','confirmed','preparing','ready','completed','cancelled') THEN
    RAISE EXCEPTION 'Invalid order status';
  END IF;

  UPDATE public.orders o
  SET status = v_status,
      updated_at = now()
  WHERE o.id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  RETURN QUERY
  SELECT o.id, o.status, o.updated_at
  FROM public.orders o
  WHERE o.id = p_order_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_order_status(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_order_status(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.track_public_order(p_code text,p_phone text)
RETURNS TABLE(
  public_code text,
  status text,
  created_at timestamptz,
  updated_at timestamptz,
  total numeric,
  customer_name text,
  customer_phone text,
  customer_address text,
  notes text,
  items jsonb
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    o.public_code,
    o.status,
    o.created_at,
    o.updated_at,
    o.total,
    c.name,
    c.phone,
    c.address,
    o.notes,
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'product_name', p.name,
          'quantity', oi.quantity,
          'unit_price', oi.unit_price
        ) ORDER BY oi.created_at
      )
      FROM public.order_items oi
      LEFT JOIN public.products p ON p.id = oi.product_id
      WHERE oi.order_id = o.id
    ), '[]'::jsonb)
  FROM public.orders o
  JOIN public.customers c ON c.id = o.customer_id
  WHERE upper(o.public_code)=upper(trim(p_code))
    AND c.phone=trim(p_phone)
  ORDER BY o.created_at DESC
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.track_public_order(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.track_public_order(text,text) TO anon, authenticated;
