-- Pharmacy Abdelhadi V6.4.6
-- Fixes:
-- 1) createPortal runtime error caused by importing createPortal from react-dom/client.
--    (Frontend-only import fix; no SQL needed for that part.)
-- 2) Product list no longer relies on the default Supabase/PostgREST 1000-row response cap.
--    Products are fetched in controlled pages of up to 500 rows.
-- 3) Keeps admin authorization and active-product behavior consistent with admin_get_products.

CREATE OR REPLACE FUNCTION public.admin_get_products_page(
  p_limit integer DEFAULT 500,
  p_offset integer DEFAULT 0,
  p_customer_visible boolean DEFAULT NULL
)
RETURNS SETOF public.products
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT p.*
  FROM public.products p
  WHERE public.is_admin()
    AND COALESCE(p.active,true)=true
    AND (p_customer_visible IS NULL OR p.customer_visible=p_customer_visible)
  ORDER BY p.name, p.id
  LIMIT LEAST(GREATEST(COALESCE(p_limit,500),1),500)
  OFFSET GREATEST(COALESCE(p_offset,0),0);
$$;

REVOKE ALL ON FUNCTION public.admin_get_products_page(integer,integer,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_products_page(integer,integer,boolean) TO authenticated;

-- Exact count used by the dashboard and useful for validating the paginated product list.
CREATE OR REPLACE FUNCTION public.admin_products_count()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT COUNT(*)::bigint
  FROM public.products p
  WHERE public.is_admin()
    AND COALESCE(p.active,true)=true;
$$;

REVOKE ALL ON FUNCTION public.admin_products_count() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_products_count() TO authenticated;
