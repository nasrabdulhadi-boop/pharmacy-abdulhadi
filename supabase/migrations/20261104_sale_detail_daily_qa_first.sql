-- QA first: complete single-sale details, no writes. Uses historical invoice numbers when assigned.
CREATE OR REPLACE FUNCTION public.admin_sale_detail_daily_v1(p_sale_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $fn$
DECLARE v_result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object(
   'header',to_jsonb(s)||jsonb_build_object('invoice_number',CASE WHEN n.invoice_no IS NULL THEN NULL ELSE lpad(n.invoice_no::text,2,'0') END),
   'items',COALESCE((
      SELECT jsonb_agg(to_jsonb(si)||jsonb_build_object('product_name',p.name,'batch_number',b.batch_number,'expiry_date',b.expiry_date)
        ORDER BY si.created_at,si.id)
      FROM public.sale_items si
      LEFT JOIN public.products p ON p.id=si.product_id
      LEFT JOIN public.batches b ON b.id=si.batch_id
      WHERE si.sale_id=s.id
   ),'[]'::jsonb)
 ) INTO v_result
 FROM public.sales s LEFT JOIN public.sale_invoice_numbers n ON n.sale_id=s.id
 WHERE s.id=p_sale_id;
 RETURN v_result;
END;$fn$;
REVOKE ALL ON FUNCTION public.admin_sale_detail_daily_v1(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_sale_detail_daily_v1(uuid) TO authenticated;
