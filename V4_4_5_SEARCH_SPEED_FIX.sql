-- v4.4.5: allow hidden pharmacy products in batch selector and fast prefix POS search

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

CREATE OR REPLACE FUNCTION public.admin_search_pos_products(
  p_query text,
  p_limit integer DEFAULT 30
)
RETURNS TABLE(
  id uuid,
  name text,
  barcode text,
  active_ingredient text,
  strength text,
  dosage_form text,
  unit text,
  sale_price numeric,
  purchase_price numeric,
  parts_per_unit numeric,
  stock numeric,
  expiry_date date
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT
    p.id,
    p.name,
    p.barcode,
    p.active_ingredient,
    p.strength,
    p.dosage_form,
    p.unit,
    p.sale_price,
    p.purchase_price,
    p.parts_per_unit,
    COALESCE(SUM(CASE WHEN b.quantity > 0 THEN b.quantity ELSE 0 END),0) AS stock,
    MIN(CASE WHEN b.quantity > 0 THEN b.expiry_date END) AS expiry_date
  FROM public.products p
  LEFT JOIN public.batches b ON b.product_id = p.id
  WHERE public.is_admin()
    AND (
      p.name ILIKE p_query || '%'
      OR COALESCE(p.active_ingredient,'') ILIKE p_query || '%'
      OR COALESCE(p.barcode,'') ILIKE p_query || '%'
    )
  GROUP BY p.id
  ORDER BY
    CASE
      WHEN p.barcode = p_query THEN 0
      WHEN lower(p.name) = lower(p_query) THEN 1
      WHEN lower(p.name) LIKE lower(p_query) || '%' THEN 2
      ELSE 3
    END,
    p.name
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit,30),100));
$$;

REVOKE ALL ON FUNCTION public.admin_search_pos_products(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_pos_products(text, integer) TO authenticated;

-- Prefix-search indexes for immediate results from the first characters.
CREATE INDEX IF NOT EXISTS idx_products_name_lower ON public.products (lower(name));
CREATE INDEX IF NOT EXISTS idx_products_active_ingredient_lower ON public.products (lower(active_ingredient));
CREATE INDEX IF NOT EXISTS idx_products_barcode ON public.products (barcode);

-- Optional trigram indexes if pg_trgm is available; safe if extension is already enabled.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_products_name_trgm ON public.products USING gin (name gin_trgm_ops)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_products_active_ingredient_trgm ON public.products USING gin (active_ingredient gin_trgm_ops)';
  END IF;
END $$;
