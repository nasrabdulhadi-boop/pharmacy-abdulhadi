-- v4.2 repair: unify admin authorization and make order reading independent of UI relations
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id = auth.uid()
      AND (
        COALESCE(u.raw_app_meta_data->>'role','') = 'admin'
        OR u.email = 'drnaser@pharmahadi.com'
      )
  );
$$;
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_admin_orders()
RETURNS TABLE(
 id uuid, public_code text, status text, total numeric, created_at timestamptz,
 customer_name text, customer_phone text, customer_address text, items jsonb
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
 IF NOT public.is_admin() THEN
   RAISE EXCEPTION 'Admin authorization required';
 END IF;
 RETURN QUERY
 SELECT o.id,o.public_code,o.status,o.total,o.created_at,
        c.name,c.phone,c.address,
        COALESCE((SELECT jsonb_agg(
          jsonb_build_object('product_name',p.name,'quantity',oi.quantity,'unit_price',oi.unit_price)
          ORDER BY oi.created_at
        ) FROM public.order_items oi
        LEFT JOIN public.products p ON p.id=oi.product_id
        WHERE oi.order_id=o.id),'[]'::jsonb)
 FROM public.orders o
 LEFT JOIN public.customers c ON c.id=o.customer_id
 ORDER BY o.created_at DESC
 LIMIT 150;
END;
$$;
REVOKE ALL ON FUNCTION public.get_admin_orders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_admin_orders() TO authenticated;
