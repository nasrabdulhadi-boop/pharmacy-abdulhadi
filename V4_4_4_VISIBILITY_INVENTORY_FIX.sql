-- v4.4.4: keep hidden products visible in admin + inventory, independent of customer_visible
CREATE OR REPLACE FUNCTION public.admin_get_products()
RETURNS SETOF public.products
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT p.*
  FROM public.products p
  WHERE public.is_admin()
  ORDER BY p.name;
$$;
REVOKE ALL ON FUNCTION public.admin_get_products() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_products() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_get_inventory()
RETURNS TABLE(
  batch_id uuid,
  product_id uuid,
  expiry_date date,
  quantity numeric,
  purchase_price numeric,
  received_date date,
  name text,
  barcode text,
  active_ingredient text,
  reorder_level numeric,
  sale_price numeric,
  product_purchase_price numeric,
  manufacturer text,
  strength text,
  dosage_form text,
  parts_per_unit numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT b.id, p.id, b.expiry_date, b.quantity, b.purchase_price, b.received_date,
         p.name, p.barcode, p.active_ingredient, p.reorder_level, p.sale_price,
         p.purchase_price, p.manufacturer, p.strength, p.dosage_form, p.parts_per_unit
  FROM public.batches b
  JOIN public.products p ON p.id = b.product_id
  WHERE public.is_admin()
  ORDER BY b.expiry_date NULLS LAST, p.name;
$$;
REVOKE ALL ON FUNCTION public.admin_get_inventory() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_inventory() TO authenticated;

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
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_set_product_visibility(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_product_visibility(uuid, boolean) TO authenticated;
