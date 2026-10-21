-- USD + legacy SYP data exposed without ever mixing numeric currencies.
-- Staging only, run after scripts 01-04. No modification of stored amounts.
BEGIN;
CREATE OR REPLACE FUNCTION public.admin_currency_purchase_list_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
  'id',x.id,'supplier_id',x.supplier_id,'supplier_name',x.supplier_name,
  'invoice_number',x.invoice_number,'invoice_date',x.invoice_date,
  'created_at',x.created_at,'status',x.status,'notes',x.notes,
  'total',x.total,'subtotal',x.subtotal,'discount_type',x.discount_type,
  'discount_value',x.discount_value,'discount_amount',x.discount_amount,
  'paid_amount',x.paid_amount,'due_amount',x.due_amount,'payment_status',x.payment_status,
  'item_count',x.item_count,'bonus_quantity',x.bonus_quantity,
  'currency',x.currency,'fx_rate',x.fx_rate,'total_syp',x.total_syp
 ) ORDER BY x.created_at DESC), '[]'::jsonb)
 FROM (
 SELECT p.id,p.supplier_id,s.name supplier_name,p.invoice_number,p.invoice_date,p.created_at,
 p.status,p.notes,p.total,p.subtotal,p.discount_type,p.discount_value,p.discount_amount,
 p.paid_amount,p.due_amount,p.payment_status,p.currency,p.fx_rate,
 CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END total_syp,
 COUNT(pi.id)::bigint item_count,COALESCE(SUM(pi.bonus_quantity),0) bonus_quantity
 FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id
 LEFT JOIN public.purchase_items pi ON pi.purchase_id=p.id
 WHERE public.is_admin() GROUP BY p.id,s.name
 ) x;
$fn$;
CREATE OR REPLACE FUNCTION public.admin_currency_supplier_debt_list_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
 SELECT COALESCE(jsonb_agg(jsonb_build_object(
  'id',x.id,'name',x.name,'phone',x.phone,'address',x.address,
  'currency',x.currency,'invoice_total',x.invoice_total,'paid_total',x.paid_total,
  'balance',x.balance,'invoice_count',x.invoice_count,'payment_count',x.payment_count,
  'last_payment',x.last_payment,'last_invoice',x.last_invoice
 ) ORDER BY x.balance DESC,x.name,x.currency),'[]'::jsonb)
 FROM (
 SELECT s.id,s.name,s.phone,s.address,p.currency,
 SUM(p.total) invoice_total,SUM(p.paid_amount) paid_total,
 SUM(GREATEST(p.total-p.paid_amount,0)) balance,COUNT(*) invoice_count,
 (SELECT COUNT(*) FROM public.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=p.currency) payment_count,
 (SELECT MAX(sp.created_at) FROM public.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=p.currency) last_payment,
 MAX(p.created_at) last_invoice
 FROM public.suppliers s JOIN public.purchases p ON p.supplier_id=s.id
 WHERE public.is_admin() GROUP BY s.id,p.currency
 ) x;
$fn$;
CREATE OR REPLACE FUNCTION public.admin_currency_supplier_ledger_v1(p_supplier_id uuid,p_currency text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v jsonb; v_currency text:=upper(COALESCE(p_currency,''));
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF v_currency NOT IN ('USD','SYP') THEN RAISE EXCEPTION 'عملة المورد غير صالحة'; END IF;
 SELECT jsonb_build_object(
 'supplier',to_jsonb(s)||jsonb_build_object('currency',v_currency),
 'summary',jsonb_build_object(
 'invoice_total',COALESCE((SELECT SUM(total) FROM public.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
 'paid_total',COALESCE((SELECT SUM(paid_amount) FROM public.purchases WHERE supplier_id=s.id AND currency=v_currency),0),
 'balance',COALESCE((SELECT SUM(GREATEST(total-paid_amount,0)) FROM public.purchases WHERE supplier_id=s.id AND currency=v_currency),0)),
 'invoices',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'invoice_number',p.invoice_number,
 'invoice_date',p.invoice_date,'created_at',p.created_at,'total',p.total,'paid_amount',p.paid_amount,
 'due_amount',p.due_amount,'payment_status',p.payment_status,'currency',p.currency,'fx_rate',p.fx_rate,
 'total_syp',CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END,
 'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',pr.name,'barcode',pr.barcode,
 'quantity',pi.quantity,'purchase_price',pi.purchase_price,'purchase_price_syp',pi.purchase_price_syp,
 'sale_price',pi.sale_price,'sale_currency',pi.sale_price_currency,'expiry_date',pi.expiry_date,'batch_id',pi.batch_id))
 FROM public.purchase_items pi JOIN public.products pr ON pr.id=pi.product_id WHERE pi.purchase_id=p.id),'[]'::jsonb))
 ORDER BY p.created_at DESC) FROM public.purchases p WHERE p.supplier_id=s.id AND p.currency=v_currency),'[]'::jsonb),
 'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',sp.id,'amount',sp.amount,
 'currency',sp.currency,'fx_rate',sp.fx_rate,'amount_syp',sp.amount_syp,'payment_method',sp.payment_method,
 'notes',sp.notes,'created_at',sp.created_at,
 'allocations',COALESCE((SELECT jsonb_agg(jsonb_build_object('purchase_id',spa.purchase_id,
 'amount',spa.amount,'invoice_number',p2.invoice_number))
 FROM public.supplier_payment_allocations spa JOIN public.purchases p2 ON p2.id=spa.purchase_id
 WHERE spa.payment_id=sp.id),'[]'::jsonb)) ORDER BY sp.created_at DESC)
 FROM public.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=v_currency),'[]'::jsonb))
 INTO v FROM public.suppliers s WHERE s.id=p_supplier_id;
 IF v IS NULL THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 RETURN v;
END;
$fn$;
CREATE OR REPLACE FUNCTION public.admin_currency_purchase_detail_v1(p_purchase_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object('id',p.id,'supplier_id',p.supplier_id,'supplier_name',s.name,
 'invoice_number',p.invoice_number,'invoice_date',p.invoice_date,'subtotal',p.subtotal,
 'discount_type',p.discount_type,'discount_value',p.discount_value,'discount_amount',p.discount_amount,
 'total',p.total,'paid_amount',p.paid_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,
 'status',p.status,'notes',p.notes,'created_at',p.created_at,'currency',p.currency,'fx_rate',p.fx_rate,
 'total_syp',CASE WHEN p.currency='SYP' THEN p.total ELSE p.total_syp END,
 'bonus_quantity',COALESCE((SELECT SUM(bonus_quantity) FROM public.purchase_items WHERE purchase_id=p.id),0),
 'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pi.id,'product_id',pi.product_id,
 'product_name',pr.name,'barcode',pr.barcode,'active_ingredient',pr.active_ingredient,
 'quantity',pi.quantity,'bonus_quantity',pi.bonus_quantity,'purchase_price',pi.purchase_price,
 'purchase_price_syp',pi.purchase_price_syp,'sale_price',pi.sale_price,'sale_currency',pi.sale_price_currency,'expiry_date',pi.expiry_date,
 'batch_id',pi.batch_id)) FROM public.purchase_items pi JOIN public.products pr ON pr.id=pi.product_id
 WHERE pi.purchase_id=p.id),'[]'::jsonb),
 'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',sp.id,'amount',spa.amount,
 'currency',sp.currency,'fx_rate',sp.fx_rate,'payment_method',sp.payment_method,
 'notes',sp.notes,'created_at',sp.created_at,'cashbox_entry_id',sp.cashbox_entry_id))
 FROM public.supplier_payment_allocations spa JOIN public.supplier_payments sp ON sp.id=spa.payment_id
 WHERE spa.purchase_id=p.id),'[]'::jsonb)) INTO v FROM public.purchases p
 LEFT JOIN public.suppliers s ON s.id=p.supplier_id WHERE p.id=p_purchase_id;
 RETURN v;
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_currency_purchase_list_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_currency_supplier_debt_list_v1() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_currency_supplier_ledger_v1(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_currency_purchase_detail_v1(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_purchase_list_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_debt_list_v1() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_currency_supplier_ledger_v1(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_currency_purchase_detail_v1(uuid) TO authenticated;
COMMIT;
