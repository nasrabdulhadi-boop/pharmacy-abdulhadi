-- Read-only lookup for all screens showing sales; authorization is enforced on server.
CREATE OR REPLACE FUNCTION public.admin_sale_invoice_numbers_v1(p_sale_ids uuid[])
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $fn$
DECLARE v_result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT COALESCE(jsonb_object_agg(n.sale_id::text,lpad(n.invoice_no::text,2,'0')),'{}'::jsonb)
 INTO v_result FROM public.sale_invoice_numbers n WHERE n.sale_id=ANY(COALESCE(p_sale_ids,ARRAY[]::uuid[]));
 RETURN v_result;
END;$fn$;
REVOKE ALL ON FUNCTION public.admin_sale_invoice_numbers_v1(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_sale_invoice_numbers_v1(uuid[]) TO authenticated;
