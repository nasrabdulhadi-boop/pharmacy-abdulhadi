-- Pharmacy Abdelhadi V6.4.3
-- Exact dashboard product count. Read-only, non-destructive.
BEGIN;

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
    AND COALESCE(p.active, true) = true;
$$;

REVOKE ALL ON FUNCTION public.admin_products_count() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_products_count() TO authenticated;

COMMIT;
