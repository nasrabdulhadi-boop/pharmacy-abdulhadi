-- Preserve existing supplier history UI with currency explicitly included. STAGING ONLY.
BEGIN;
CREATE OR REPLACE FUNCTION public.admin_currency_supplier_purchase_history_v1(p_supplier_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
 'id',x.id,'invoice_number',x.invoice_number,'invoice_date',x.invoice_date,
 'total',x.total,'status',x.status,'paid_amount',x.paid_amount,'due_amount',x.due_amount,
 'payment_status',x.payment_status,'created_at',x.created_at,'item_count',x.item_count,
 'currency',x.currency,'fx_rate',x.fx_rate,'total_syp',x.total_syp
 ) ORDER BY x.created_at DESC),'[]'::jsonb)
 FROM (
 SELECT p.id,p.invoice_number,p.invoice_date,p.total,p.status,p.paid_amount,p.due_amount,
 p.payment_status,p.created_at,p.currency,p.fx_rate,
 CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END total_syp,
 COUNT(pi.id)::bigint item_count
 FROM public.purchases p LEFT JOIN public.purchase_items pi ON pi.purchase_id=p.id
 WHERE public.is_admin() AND p.supplier_id=p_supplier_id GROUP BY p.id
 ) x;
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_supplier_purchase_history_v1(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_purchase_history_v1(uuid) TO authenticated;
COMMIT;
