-- QA ONLY: Review permissions and test on an isolated database before any production deployment.
-- Read-only unified event feed. All amounts retain their recorded currency; no accounting recomputation.
CREATE OR REPLACE FUNCTION public.admin_daily_activity_v1(p_start timestamptz,p_end timestamptz,p_limit integer DEFAULT 500,p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $function$
DECLARE v_result jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start OR p_end-p_start>interval '31 days' THEN RAISE EXCEPTION 'Invalid date range'; END IF;
 IF p_limit<1 OR p_limit>1000 OR p_offset<0 THEN RAISE EXCEPTION 'Invalid pagination'; END IF;
 WITH events AS (
 SELECT 'sale'::text AS kind, s.id, s.created_at AS occurred_at, to_jsonb(s) || jsonb_build_object('items',COALESCE((SELECT jsonb_agg(to_jsonb(si)||jsonb_build_object('product_name',p.name) ORDER BY si.created_at,si.id) FROM public.sale_items si LEFT JOIN public.products p ON p.id=si.product_id WHERE si.sale_id=s.id),'[]'::jsonb)) AS details FROM public.sales s WHERE s.created_at >= p_start AND s.created_at < p_end
 UNION ALL
 SELECT 'purchase'::text AS kind, s.id, s.created_at AS occurred_at, to_jsonb(s) || jsonb_build_object('items',COALESCE((SELECT jsonb_agg(to_jsonb(pi)||jsonb_build_object('product_name',p.name) ORDER BY pi.created_at,pi.id) FROM public.purchase_items pi LEFT JOIN public.products p ON p.id=pi.product_id WHERE pi.purchase_id=s.id),'[]'::jsonb)) AS details FROM public.purchases s WHERE s.created_at >= p_start AND s.created_at < p_end
 UNION ALL
 SELECT 'return'::text AS kind, s.id, s.created_at AS occurred_at, to_jsonb(s) || jsonb_build_object('product_name',(SELECT name FROM public.products WHERE id=s.product_id)) AS details FROM public.returns s WHERE s.created_at >= p_start AND s.created_at < p_end
 UNION ALL
 SELECT 'cash'::text AS kind, s.id, s.created_at AS occurred_at, to_jsonb(s) || '{}'::jsonb AS details FROM public.cashbox_entries s WHERE s.created_at >= p_start AND s.created_at < p_end
 UNION ALL
 SELECT 'supplier'::text AS kind, s.id, s.created_at AS occurred_at, to_jsonb(s) || jsonb_build_object('supplier_name',(SELECT name FROM public.suppliers WHERE id=s.supplier_id)) AS details FROM public.supplier_payments s WHERE s.created_at >= p_start AND s.created_at < p_end
 UNION ALL
 SELECT 'debt'::text AS kind, s.id, s.created_at AS occurred_at, to_jsonb(s) || jsonb_build_object('debtor_name',(SELECT name FROM public.debtors WHERE id=s.debtor_id)) AS details FROM public.debtor_transactions s WHERE s.created_at >= p_start AND s.created_at < p_end
 UNION ALL
 SELECT 'stock'::text AS kind, s.id, s.created_at AS occurred_at, to_jsonb(s) || jsonb_build_object('product_name',(SELECT name FROM public.products WHERE id=s.product_id)) AS details FROM public.stock_movements s WHERE s.created_at >= p_start AND s.created_at < p_end
 UNION ALL
 SELECT 'audit'::text AS kind, s.id, s.created_at AS occurred_at, to_jsonb(s) || '{}'::jsonb AS details FROM public.audit_logs s WHERE s.created_at >= p_start AND s.created_at < p_end
 UNION ALL
 SELECT 'inventory_count'::text AS kind, s.id, s.started_at AS occurred_at, to_jsonb(s) || jsonb_build_object('items',COALESCE((SELECT jsonb_agg(to_jsonb(ci)||jsonb_build_object('product_name',p.name)) FROM public.inventory_count_items ci LEFT JOIN public.products p ON p.id=ci.product_id WHERE ci.count_id=s.id),'[]'::jsonb)) AS details FROM public.inventory_counts s WHERE s.started_at >= p_start AND s.started_at < p_end
 UNION ALL
 SELECT 'cash_count'::text AS kind, s.id, s.counted_at AS occurred_at, to_jsonb(s) || '{}'::jsonb AS details FROM public.cashbox_counts s WHERE s.counted_at >= p_start AND s.counted_at < p_end
 UNION ALL
 SELECT 'order'::text AS kind, s.id, s.created_at AS occurred_at, to_jsonb(s) || '{}'::jsonb AS details FROM public.orders s WHERE s.created_at >= p_start AND s.created_at < p_end
 UNION ALL
 SELECT 'prescription'::text AS kind, s.id, s.created_at AS occurred_at, to_jsonb(s) || '{}'::jsonb AS details FROM public.prescriptions s WHERE s.created_at >= p_start AND s.created_at < p_end
 UNION ALL
 SELECT 'medicine_request'::text AS kind, s.id, s.created_at AS occurred_at, to_jsonb(s) || '{}'::jsonb AS details FROM public.medicine_requests s WHERE s.created_at >= p_start AND s.created_at < p_end
 ), numbered AS (SELECT *, count(*) OVER() AS total_count FROM events), page AS (SELECT * FROM numbered ORDER BY occurred_at DESC,id DESC LIMIT p_limit OFFSET p_offset)
 SELECT jsonb_build_object('total',COALESCE((SELECT max(total_count) FROM numbered),0),'events',COALESCE((SELECT jsonb_agg(jsonb_build_object('kind',kind,'id',id,'occurred_at',occurred_at,'details',details) ORDER BY occurred_at DESC,id DESC) FROM page),'[]'::jsonb)) INTO v_result;
 RETURN v_result;
END;$function$;
REVOKE ALL ON FUNCTION public.admin_daily_activity_v1(timestamptz,timestamptz,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_daily_activity_v1(timestamptz,timestamptz,integer,integer) TO authenticated;
