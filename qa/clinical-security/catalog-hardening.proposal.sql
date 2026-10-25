-- PROPOSAL FOR DISPOSABLE STAGING TESTS ONLY. NOT AN AUTO-APPLIED MIGRATION.
-- No pharmacy records are modified. The opt-in guard deliberately refuses ordinary execution.
BEGIN;
DO $preflight$
BEGIN
 IF current_setting('pharmacy.catalog_hardening_test',true) IS DISTINCT FROM 'isolated-only' THEN
  RAISE EXCEPTION 'Isolated catalog-hardening test opt-in is required';
 END IF;
 IF to_regclass('public.products') IS NULL OR to_regprocedure('public.is_admin()') IS NULL THEN
  RAISE EXCEPTION 'Expected products table and existing admin check are required';
 END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.products'::regclass) THEN
  RAISE EXCEPTION 'Expected existing products RLS';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.products'::regclass AND polname='public products read' AND polcmd='r')
    OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.products'::regclass AND polcmd IN ('r','*') AND polname<>'public products read') THEN
  RAISE EXCEPTION 'Unexpected SELECT policies; review schema drift before proceeding';
 END IF;
 IF (SELECT pg_get_expr(polqual,polrelid) FROM pg_policy WHERE polrelid='public.products'::regclass AND polname='public products read') IS DISTINCT FROM '(customer_visible = true)' THEN
  RAISE EXCEPTION 'Public policy predicate changed; review before proceeding';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='pharmacy_catalog_reader')
    OR to_regnamespace('pharmacy_catalog_private') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='get_public_catalog_v1') THEN
  RAISE EXCEPTION 'Reserved hardening objects already exist; refusing to replace them';
 END IF;
END;$preflight$;

CREATE ROLE pharmacy_catalog_reader NOLOGIN NOINHERIT NOBYPASSRLS;
CREATE SCHEMA pharmacy_catalog_private;
REVOKE ALL ON SCHEMA pharmacy_catalog_private FROM PUBLIC;
GRANT USAGE ON SCHEMA pharmacy_catalog_private TO anon,authenticated,pharmacy_catalog_reader;
GRANT USAGE ON SCHEMA public TO pharmacy_catalog_reader;
GRANT SELECT(id,name,active_ingredient,dosage_form,strength,manufacturer,category,unit,sale_price,sale_currency,barcode,customer_visible,active)
 ON public.products TO pharmacy_catalog_reader;

-- Keep administrator direct-table reads. Ordinary authenticated users get no base-table rows.
DROP POLICY "public products read" ON public.products;
CREATE POLICY catalog_admin_read ON public.products FOR SELECT TO authenticated USING(public.is_admin());
CREATE POLICY catalog_reader_read ON public.products FOR SELECT TO pharmacy_catalog_reader
 USING(customer_visible IS TRUE AND COALESCE(active,true));
REVOKE SELECT ON public.products FROM anon,PUBLIC;
DO $revoke_columns$
DECLARE column_name text;
BEGIN
 FOR column_name IN SELECT attname FROM pg_attribute WHERE attrelid='public.products'::regclass AND attnum>0 AND NOT attisdropped LOOP
  EXECUTE format('REVOKE SELECT (%I) ON public.products FROM anon,PUBLIC',column_name);
 END LOOP;
END;$revoke_columns$;
GRANT SELECT ON public.products TO authenticated;

CREATE FUNCTION pharmacy_catalog_private.read_catalog(p_limit integer,p_offset integer)
RETURNS TABLE(id uuid,name text,active_ingredient text,dosage_form text,strength text,manufacturer text,category text,unit text,sale_price numeric,sale_currency text,barcode text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $catalog$
 SELECT p.id,p.name,p.active_ingredient,p.dosage_form,p.strength,p.manufacturer,p.category,p.unit,p.sale_price,p.sale_currency,p.barcode
 FROM public.products p
 WHERE p.customer_visible IS TRUE AND COALESCE(p.active,true)
 ORDER BY p.name,p.id
 LIMIT LEAST(GREATEST(COALESCE(p_limit,500),1),500)
 OFFSET GREATEST(COALESCE(p_offset,0),0);
$catalog$;
-- The definer owns neither the products table nor a bypass-RLS role and cannot read cost.
GRANT CREATE ON SCHEMA pharmacy_catalog_private TO pharmacy_catalog_reader;
GRANT pharmacy_catalog_reader TO CURRENT_USER WITH INHERIT FALSE, SET TRUE;
ALTER FUNCTION pharmacy_catalog_private.read_catalog(integer,integer) OWNER TO pharmacy_catalog_reader;
-- Remove this temporary grant; PostgreSQL retains its automatic management-only creator grant.
REVOKE pharmacy_catalog_reader FROM CURRENT_USER;
REVOKE CREATE ON SCHEMA pharmacy_catalog_private FROM pharmacy_catalog_reader;
REVOKE ALL ON FUNCTION pharmacy_catalog_private.read_catalog(integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pharmacy_catalog_private.read_catalog(integer,integer) TO anon,authenticated;

CREATE FUNCTION public.get_public_catalog_v1(p_limit integer DEFAULT 500,p_offset integer DEFAULT 0)
RETURNS TABLE(id uuid,name text,active_ingredient text,dosage_form text,strength text,manufacturer text,category text,unit text,sale_price numeric,sale_currency text,barcode text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $wrapper$
 SELECT * FROM pharmacy_catalog_private.read_catalog(p_limit,p_offset);
$wrapper$;
REVOKE ALL ON FUNCTION public.get_public_catalog_v1(integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_catalog_v1(integer,integer) TO anon,authenticated;
DO $postconditions$
BEGIN
 IF has_column_privilege('anon','public.products','purchase_price','SELECT')
    OR has_column_privilege('pharmacy_catalog_reader','public.products','purchase_price','SELECT') THEN
  RAISE EXCEPTION 'Unexpected inherited cost privilege; refusing partial hardening';
 END IF;
END;$postconditions$;
COMMIT;
