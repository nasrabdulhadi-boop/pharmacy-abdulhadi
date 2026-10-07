-- Pharmacy Abdelhadi V6.4.8
-- Purpose:
-- 1) Purchase invoice searches the database directly instead of depending on a full in-memory product list.
-- 2) Existing products can be found by exact barcode, name, active ingredient, strength, or manufacturer.
-- 3) Pharmacy Products uses server-side paging/search instead of loading the whole catalog into the browser.
-- 4) Read-only/search RPCs only; no operational data is deleted or changed.

CREATE OR REPLACE FUNCTION public.admin_search_purchase_products(
  p_query text DEFAULT NULL,
  p_limit integer DEFAULT 40
)
RETURNS TABLE(
  id uuid,
  name text,
  barcode text,
  active_ingredient text,
  strength text,
  dosage_form text,
  manufacturer text,
  category text,
  unit text,
  purchase_price numeric,
  sale_price numeric,
  parts_per_unit numeric,
  reorder_level numeric,
  active boolean,
  customer_visible boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT
    p.id,p.name,p.barcode,p.active_ingredient,p.strength,p.dosage_form,
    p.manufacturer,p.category,p.unit,p.purchase_price,p.sale_price,
    p.parts_per_unit,p.reorder_level,p.active,p.customer_visible
  FROM public.products p
  WHERE public.is_admin()
    AND COALESCE(p.active,true)=true
    AND (
      NULLIF(trim(COALESCE(p_query,'')),'') IS NULL
      OR p.barcode = trim(p_query)
      OR p.name ILIKE '%' || trim(p_query) || '%'
      OR COALESCE(p.active_ingredient,'') ILIKE '%' || trim(p_query) || '%'
      OR COALESCE(p.strength,'') ILIKE '%' || trim(p_query) || '%'
      OR COALESCE(p.manufacturer,'') ILIKE '%' || trim(p_query) || '%'
    )
  ORDER BY
    CASE WHEN p.barcode = trim(COALESCE(p_query,'')) THEN 0 ELSE 1 END,
    CASE WHEN lower(p.name)=lower(trim(COALESCE(p_query,''))) THEN 0 ELSE 1 END,
    p.name,p.id
  LIMIT GREATEST(1,LEAST(COALESCE(p_limit,40),100));
$$;

REVOKE ALL ON FUNCTION public.admin_search_purchase_products(text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_purchase_products(text,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_product_catalog(
  p_query text DEFAULT NULL,
  p_manufacturer text DEFAULT NULL,
  p_dosage_form text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_customer_visible boolean DEFAULT NULL,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0,
  p_sort text DEFAULT 'name',
  p_desc boolean DEFAULT false
)
RETURNS TABLE(
  id uuid,
  name text,
  barcode text,
  active_ingredient text,
  strength text,
  dosage_form text,
  manufacturer text,
  category text,
  unit text,
  reorder_level numeric,
  purchase_price numeric,
  sale_price numeric,
  parts_per_unit numeric,
  customer_visible boolean,
  active boolean,
  total_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  WITH filtered AS (
    SELECT p.*
    FROM public.products p
    WHERE public.is_admin()
      AND COALESCE(p.active,true)=true
      AND (p_customer_visible IS NULL OR p.customer_visible=p_customer_visible)
      AND (
        NULLIF(trim(COALESCE(p_query,'')),'') IS NULL
        OR p.name ILIKE '%' || trim(p_query) || '%'
        OR COALESCE(p.barcode,'') ILIKE '%' || trim(p_query) || '%'
        OR COALESCE(p.active_ingredient,'') ILIKE '%' || trim(p_query) || '%'
        OR COALESCE(p.strength,'') ILIKE '%' || trim(p_query) || '%'
        OR COALESCE(p.manufacturer,'') ILIKE '%' || trim(p_query) || '%'
        OR COALESCE(p.dosage_form,'') ILIKE '%' || trim(p_query) || '%'
      )
      AND (NULLIF(trim(COALESCE(p_manufacturer,'')),'') IS NULL OR COALESCE(p.manufacturer,'')=trim(p_manufacturer))
      AND (NULLIF(trim(COALESCE(p_dosage_form,'')),'') IS NULL OR COALESCE(p.dosage_form,'')=trim(p_dosage_form))
      AND (NULLIF(trim(COALESCE(p_category,'')),'') IS NULL OR COALESCE(p.category,'')=trim(p_category))
  )
  SELECT
    f.id,f.name,f.barcode,f.active_ingredient,f.strength,f.dosage_form,f.manufacturer,
    f.category,f.unit,f.reorder_level,f.purchase_price,f.sale_price,f.parts_per_unit,
    f.customer_visible,f.active,COUNT(*) OVER() AS total_count
  FROM filtered f
  ORDER BY
    CASE WHEN p_sort='name' AND NOT p_desc THEN lower(COALESCE(f.name,'')) END ASC,
    CASE WHEN p_sort='name' AND p_desc THEN lower(COALESCE(f.name,'')) END DESC,
    CASE WHEN p_sort='manufacturer' AND NOT p_desc THEN lower(COALESCE(f.manufacturer,'')) END ASC,
    CASE WHEN p_sort='manufacturer' AND p_desc THEN lower(COALESCE(f.manufacturer,'')) END DESC,
    CASE WHEN p_sort='dosage_form' AND NOT p_desc THEN lower(COALESCE(f.dosage_form,'')) END ASC,
    CASE WHEN p_sort='dosage_form' AND p_desc THEN lower(COALESCE(f.dosage_form,'')) END DESC,
    CASE WHEN p_sort='active_ingredient' AND NOT p_desc THEN lower(COALESCE(f.active_ingredient,'')) END ASC,
    CASE WHEN p_sort='active_ingredient' AND p_desc THEN lower(COALESCE(f.active_ingredient,'')) END DESC,
    CASE WHEN p_sort='category' AND NOT p_desc THEN lower(COALESCE(f.category,'')) END ASC,
    CASE WHEN p_sort='category' AND p_desc THEN lower(COALESCE(f.category,'')) END DESC,
    CASE WHEN p_sort='sale_price' AND NOT p_desc THEN f.sale_price END ASC,
    CASE WHEN p_sort='sale_price' AND p_desc THEN f.sale_price END DESC,
    CASE WHEN p_sort='purchase_price' AND NOT p_desc THEN f.purchase_price END ASC,
    CASE WHEN p_sort='purchase_price' AND p_desc THEN f.purchase_price END DESC,
    f.id
  LIMIT GREATEST(1,LEAST(COALESCE(p_limit,100),200))
  OFFSET GREATEST(COALESCE(p_offset,0),0);
$$;

REVOKE ALL ON FUNCTION public.admin_product_catalog(text,text,text,text,boolean,integer,integer,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_product_catalog(text,text,text,text,boolean,integer,integer,text,boolean) TO authenticated;

-- Safe supporting indexes. They do not alter existing data.
CREATE INDEX IF NOT EXISTS idx_products_active_name ON public.products(active,name);
CREATE INDEX IF NOT EXISTS idx_products_manufacturer ON public.products(manufacturer);
CREATE INDEX IF NOT EXISTS idx_products_dosage_form ON public.products(dosage_form);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category);
CREATE INDEX IF NOT EXISTS idx_products_name_lower ON public.products(lower(name));
CREATE INDEX IF NOT EXISTS idx_products_active_ingredient_lower ON public.products(lower(active_ingredient));
CREATE INDEX IF NOT EXISTS idx_products_barcode ON public.products(barcode);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_trgm') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_products_name_trgm ON public.products USING gin (name gin_trgm_ops)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_products_active_ingredient_trgm ON public.products USING gin (active_ingredient gin_trgm_ops)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_products_manufacturer_trgm ON public.products USING gin (manufacturer gin_trgm_ops)';
  END IF;
END $$;
