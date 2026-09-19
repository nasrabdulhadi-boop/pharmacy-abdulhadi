-- Pharmacy Abdelhadi v4.5.2
-- Fix material-card supplier/invoice visibility through an admin SECURITY DEFINER RPC.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_product_batch_trace(p_product_id uuid)
RETURNS TABLE(
  id uuid,
  expiry_date date,
  quantity numeric,
  purchase_price numeric,
  received_date date,
  supplier_name text,
  invoice_number text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
  SELECT b.id, b.expiry_date, b.quantity, b.purchase_price, b.received_date,
         s.name AS supplier_name, p.invoice_number
  FROM public.batches b
  LEFT JOIN public.suppliers s ON s.id=b.supplier_id
  LEFT JOIN public.purchases p ON p.id=b.purchase_id
  WHERE public.is_admin() AND b.product_id=p_product_id
  ORDER BY b.expiry_date ASC NULLS LAST, b.received_date ASC NULLS LAST;
$$;

REVOKE ALL ON FUNCTION public.admin_product_batch_trace(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_product_batch_trace(uuid) TO authenticated;

COMMIT;
