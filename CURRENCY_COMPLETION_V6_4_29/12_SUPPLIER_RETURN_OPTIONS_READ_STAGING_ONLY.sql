-- Safe listing: price currency is explicitly tied to the original purchase invoice.
-- USD supplier return remains blocked pending supplier credit note/debt settlement.
BEGIN;
CREATE OR REPLACE FUNCTION public.admin_currency_supplier_return_options_v1()
RETURNS TABLE(purchase_id uuid,invoice_number text,supplier_name text,purchase_date date,
 purchase_item_id uuid,batch_id uuid,product_id uuid,product_name text,
 purchased_quantity numeric,available_quantity numeric,purchase_price numeric,expiry_date date,currency text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
 SELECT p.id,p.invoice_number,s.name,p.invoice_date,pi.id,b.id,pr.id,pr.name,
   CASE WHEN b.id=pi.batch_id THEN pi.quantity ELSE pi.bonus_quantity END,
   COALESCE(b.quantity,0),CASE WHEN b.id=pi.batch_id THEN pi.purchase_price ELSE 0 END,b.expiry_date,p.currency
 FROM public.purchase_items pi JOIN public.purchases p ON p.id=pi.purchase_id
 JOIN public.products pr ON pr.id=pi.product_id
 LEFT JOIN public.suppliers s ON s.id=p.supplier_id
 JOIN public.batches b ON b.purchase_item_id=pi.id
 WHERE public.is_admin() AND b.id IS NOT NULL AND COALESCE(b.quantity,0)>0
 ORDER BY p.created_at DESC NULLS LAST,pr.name;
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_supplier_return_options_v1() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_return_options_v1() TO authenticated;
COMMIT;
