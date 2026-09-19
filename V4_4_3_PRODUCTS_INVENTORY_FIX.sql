-- Pharmacy Abdelhadi v4.4.3
-- Fix product visibility RLS and provide controlled product price updates for inventory batches.

CREATE OR REPLACE FUNCTION public.admin_set_product_visibility(
  p_product_id uuid,
  p_visible boolean
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;
  UPDATE public.products
  SET customer_visible = COALESCE(p_visible, false), updated_at = now()
  WHERE id = p_product_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_set_product_visibility(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_product_visibility(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_product_prices(
  p_product_id uuid,
  p_purchase_price numeric,
  p_sale_price numeric
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;
  UPDATE public.products
  SET purchase_price = GREATEST(COALESCE(p_purchase_price,0),0),
      sale_price = GREATEST(COALESCE(p_sale_price,0),0),
      updated_at = now()
  WHERE id = p_product_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_product_prices(uuid, numeric, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_product_prices(uuid, numeric, numeric) TO authenticated;
