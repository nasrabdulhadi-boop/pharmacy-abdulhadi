-- Pharmacy Abdelhadi v5.5 — Smart inventory, profitability, returns, customer history, audit and reorder intelligence
BEGIN;

-- 1) Inventory count sessions
CREATE TABLE IF NOT EXISTS public.inventory_counts(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','completed','cancelled')),
 started_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 created_by uuid REFERENCES auth.users(id),
 notes text
);
CREATE TABLE IF NOT EXISTS public.inventory_count_items(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 count_id uuid NOT NULL REFERENCES public.inventory_counts(id) ON DELETE CASCADE,
 batch_id uuid NOT NULL REFERENCES public.batches(id) ON DELETE CASCADE,
 expected_quantity numeric NOT NULL DEFAULT 0,
 actual_quantity numeric,
 difference numeric GENERATED ALWAYS AS (COALESCE(actual_quantity,0)-expected_quantity) STORED,
 notes text,
 UNIQUE(count_id,batch_id)
);
ALTER TABLE public.inventory_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_count_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin inventory counts" ON public.inventory_counts;
CREATE POLICY "admin inventory counts" ON public.inventory_counts FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());
DROP POLICY IF EXISTS "admin inventory count items" ON public.inventory_count_items;
CREATE POLICY "admin inventory count items" ON public.inventory_count_items FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());

CREATE OR REPLACE FUNCTION public.admin_start_inventory_count(p_notes text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_id uuid;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 INSERT INTO public.inventory_counts(created_by,notes) VALUES(auth.uid(),NULLIF(trim(COALESCE(p_notes,'')),'')) RETURNING id INTO v_id;
 INSERT INTO public.inventory_count_items(count_id,batch_id,expected_quantity)
 SELECT v_id,b.id,b.quantity FROM public.batches b WHERE b.quantity>0;
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.admin_start_inventory_count(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_start_inventory_count(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_inventory_count_items(p_count_id uuid)
RETURNS TABLE(id uuid,batch_id uuid,product_name text,barcode text,expiry_date date,expected_quantity numeric,actual_quantity numeric,difference numeric,supplier_name text,invoice_number text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT i.id,i.batch_id,pr.name,pr.barcode,b.expiry_date,i.expected_quantity,i.actual_quantity,i.difference,s.name,p.invoice_number
 FROM public.inventory_count_items i
 JOIN public.batches b ON b.id=i.batch_id
 JOIN public.products pr ON pr.id=b.product_id
 LEFT JOIN public.suppliers s ON s.id=b.supplier_id
 LEFT JOIN public.purchases p ON p.id=b.purchase_id
 WHERE public.is_admin() AND i.count_id=p_count_id ORDER BY pr.name,b.expiry_date;
$$;
REVOKE ALL ON FUNCTION public.admin_inventory_count_items(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_inventory_count_items(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_inventory_count_actual(p_item_id uuid,p_actual numeric,p_notes text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_actual<0 THEN RAISE EXCEPTION 'Actual quantity cannot be negative'; END IF;
 UPDATE public.inventory_count_items SET actual_quantity=p_actual,notes=NULLIF(trim(COALESCE(p_notes,'')),'') WHERE id=p_item_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Count item not found'; END IF;
END; $$;
REVOKE ALL ON FUNCTION public.admin_set_inventory_count_actual(uuid,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_inventory_count_actual(uuid,numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_complete_inventory_count(p_count_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE r record; v_diff numeric:=0; v_changes integer:=0;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF EXISTS(SELECT 1 FROM public.inventory_counts WHERE id=p_count_id AND status<>'open') THEN RAISE EXCEPTION 'Inventory count is not open'; END IF;
 IF EXISTS(SELECT 1 FROM public.inventory_count_items WHERE count_id=p_count_id AND actual_quantity IS NULL) THEN RAISE EXCEPTION 'Enter actual quantity for every counted item'; END IF;
 FOR r IN SELECT i.*,b.product_id FROM public.inventory_count_items i JOIN public.batches b ON b.id=i.batch_id WHERE i.count_id=p_count_id FOR UPDATE LOOP
   IF r.difference<>0 THEN
     UPDATE public.batches SET quantity=r.actual_quantity WHERE id=r.batch_id;
     INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by) VALUES(r.product_id,r.batch_id,'inventory_count',r.difference,'تسوية جرد v5.5',auth.uid());
     v_diff:=v_diff+r.difference; v_changes:=v_changes+1;
   END IF;
 END LOOP;
 UPDATE public.inventory_counts SET status='completed',completed_at=now() WHERE id=p_count_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'inventory_count_complete','inventory_count',p_count_id,jsonb_build_object('changes',v_changes,'net_difference',v_diff));
 RETURN jsonb_build_object('id',p_count_id,'changes',v_changes,'net_difference',v_diff);
END; $$;
REVOKE ALL ON FUNCTION public.admin_complete_inventory_count(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_complete_inventory_count(uuid) TO authenticated;

-- 2) Smart reorder recommendations
CREATE OR REPLACE FUNCTION public.admin_reorder_recommendations()
RETURNS TABLE(product_id uuid,product_name text,barcode text,current_stock numeric,reorder_level numeric,suggested_quantity numeric,estimated_cost numeric,suggested_supplier text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT pr.id,pr.name,pr.barcode,COALESCE(SUM(b.quantity),0),COALESCE(pr.reorder_level,0),
        GREATEST(COALESCE(pr.reorder_level,0)*2-COALESCE(SUM(b.quantity),0),1),
        GREATEST(COALESCE(pr.reorder_level,0)*2-COALESCE(SUM(b.quantity),0),1)*COALESCE(pr.purchase_price,0),
        (SELECT s.name FROM public.batches b2 LEFT JOIN public.suppliers s ON s.id=b2.supplier_id WHERE b2.product_id=pr.id AND s.id IS NOT NULL ORDER BY b2.received_date DESC NULLS LAST,b2.created_at DESC LIMIT 1)
 FROM public.products pr LEFT JOIN public.batches b ON b.product_id=pr.id AND b.quantity>0
 WHERE public.is_admin() GROUP BY pr.id,pr.name,pr.barcode,pr.reorder_level,pr.purchase_price
 HAVING COALESCE(SUM(b.quantity),0)<=COALESCE(pr.reorder_level,0)
 ORDER BY COALESCE(SUM(b.quantity),0) ASC,pr.name;
$$;
REVOKE ALL ON FUNCTION public.admin_reorder_recommendations() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reorder_recommendations() TO authenticated;

-- 3) Expired/damaged stock disposal
CREATE OR REPLACE FUNCTION public.admin_dispose_stock(p_batch_id uuid,p_quantity numeric,p_reason text DEFAULT 'تالف/منتهي الصلاحية')
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_product uuid; v_old numeric; v_new numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_quantity<=0 THEN RAISE EXCEPTION 'Quantity must be greater than zero'; END IF;
 SELECT product_id,quantity INTO v_product,v_old FROM public.batches WHERE id=p_batch_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Batch not found'; END IF;
 IF p_quantity>v_old THEN RAISE EXCEPTION 'Insufficient batch stock'; END IF;
 v_new:=v_old-p_quantity;
 UPDATE public.batches SET quantity=v_new WHERE id=p_batch_id;
 INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by) VALUES(v_product,p_batch_id,'disposal',-p_quantity,p_reason,auth.uid());
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'admin_dispose_stock','batch',p_batch_id,jsonb_build_object('quantity',p_quantity,'reason',p_reason,'old_quantity',v_old,'new_quantity',v_new));
 RETURN v_new;
END; $$;
REVOKE ALL ON FUNCTION public.admin_dispose_stock(uuid,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dispose_stock(uuid,numeric,text) TO authenticated;

-- 4) Returns
CREATE TABLE IF NOT EXISTS public.returns(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 return_type text NOT NULL CHECK(return_type IN ('customer','supplier')),
 sale_id uuid REFERENCES public.sales(id) ON DELETE SET NULL,
 sale_item_id uuid REFERENCES public.sale_items(id) ON DELETE SET NULL,
 purchase_id uuid REFERENCES public.purchases(id) ON DELETE SET NULL,
 product_id uuid NOT NULL REFERENCES public.products(id),
 batch_id uuid REFERENCES public.batches(id) ON DELETE SET NULL,
 quantity numeric NOT NULL CHECK(quantity>0),
 amount numeric NOT NULL DEFAULT 0,
 reason text,
 created_by uuid REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.returns ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin returns" ON public.returns;
CREATE POLICY "admin returns" ON public.returns FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());

CREATE OR REPLACE FUNCTION public.admin_customer_return(p_sale_item_id uuid,p_quantity numeric,p_reason text DEFAULT 'مرتجع من الزبون')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v record; v_left numeric; v_amount numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT si.id,si.sale_id,si.product_id,si.batch_id,si.quantity,si.unit_price INTO v FROM public.sale_items si WHERE si.id=p_sale_item_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Sale item not found'; END IF;
 IF p_quantity<=0 OR p_quantity>v.quantity THEN RAISE EXCEPTION 'Invalid return quantity'; END IF;
 SELECT v.quantity-COALESCE(SUM(r.quantity),0) INTO v_left FROM public.returns r WHERE r.return_type='customer' AND r.sale_item_id=v.id;
 IF p_quantity>v_left THEN RAISE EXCEPTION 'Return quantity exceeds remaining sold quantity'; END IF;
 UPDATE public.batches SET quantity=quantity+p_quantity WHERE id=v.batch_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Original batch no longer exists'; END IF;
 v_amount:=p_quantity*v.unit_price;
 INSERT INTO public.returns(return_type,sale_id,sale_item_id,product_id,batch_id,quantity,amount,reason,created_by) VALUES('customer',v.sale_id,v.id,v.product_id,v.batch_id,p_quantity,v_amount,p_reason,auth.uid());
 INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by) VALUES(v.product_id,v.batch_id,'customer_return',p_quantity,v.sale_id,p_reason,auth.uid());
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'customer_return','sale',v.sale_id,jsonb_build_object('sale_item_id',v.id,'quantity',p_quantity,'amount',v_amount,'reason',p_reason));
 RETURN jsonb_build_object('sale_id',v.sale_id,'quantity',p_quantity,'amount',v_amount);
END; $$;
REVOKE ALL ON FUNCTION public.admin_customer_return(uuid,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_customer_return(uuid,numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_supplier_return(p_batch_id uuid,p_quantity numeric,p_reason text DEFAULT 'مرتجع إلى المورد')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v record; v_amount numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_quantity<=0 THEN RAISE EXCEPTION 'Invalid quantity'; END IF;
 SELECT b.product_id,b.quantity,b.purchase_id,b.purchase_price INTO v FROM public.batches b WHERE b.id=p_batch_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Batch not found'; END IF;
 IF p_quantity>v.quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
 UPDATE public.batches SET quantity=quantity-p_quantity WHERE id=p_batch_id;
 v_amount:=p_quantity*v.purchase_price;
 INSERT INTO public.returns(return_type,purchase_id,product_id,batch_id,quantity,amount,reason,created_by) VALUES('supplier',v.purchase_id,v.product_id,p_batch_id,p_quantity,v_amount,p_reason,auth.uid());
 INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by) VALUES(v.product_id,p_batch_id,'supplier_return',-p_quantity,v.purchase_id,p_reason,auth.uid());
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'supplier_return','batch',p_batch_id,jsonb_build_object('quantity',p_quantity,'amount',v_amount,'reason',p_reason));
 RETURN jsonb_build_object('batch_id',p_batch_id,'quantity',p_quantity,'amount',v_amount);
END; $$;
REVOKE ALL ON FUNCTION public.admin_supplier_return(uuid,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_supplier_return(uuid,numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_return_list()
RETURNS TABLE(id uuid,return_type text,product_name text,quantity numeric,amount numeric,reason text,created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT r.id,r.return_type,p.name,r.quantity,r.amount,r.reason,r.created_at FROM public.returns r JOIN public.products p ON p.id=r.product_id WHERE public.is_admin() ORDER BY r.created_at DESC LIMIT 500;
$$;
REVOKE ALL ON FUNCTION public.admin_return_list() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_return_list() TO authenticated;

-- 5) Customer profile/history
CREATE OR REPLACE FUNCTION public.admin_customer_profiles()
RETURNS TABLE(id uuid,name text,phone text,address text,created_at timestamptz,orders_count bigint,total_spent numeric,last_order_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT c.id,c.name,c.phone,c.address,c.created_at,COUNT(DISTINCT o.id),COALESCE(SUM(o.total),0),MAX(o.created_at)
 FROM public.customers c LEFT JOIN public.orders o ON o.customer_id=c.id AND o.status<>'cancelled'
 WHERE public.is_admin() GROUP BY c.id ORDER BY MAX(o.created_at) DESC NULLS LAST,c.created_at DESC LIMIT 500;
$$;
REVOKE ALL ON FUNCTION public.admin_customer_profiles() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_customer_profiles() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_customer_history(p_customer_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object('customer',to_jsonb(c),'orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'public_code',o.public_code,'status',o.status,'total',o.total,'created_at',o.created_at,'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',p.name,'quantity',oi.quantity,'unit_price',oi.unit_price)) FROM public.order_items oi JOIN public.products p ON p.id=oi.product_id WHERE oi.order_id=o.id),'[]'::jsonb)) ORDER BY o.created_at DESC) FROM public.orders o WHERE o.customer_id=c.id),'[]'::jsonb)) INTO v FROM public.customers c WHERE c.id=p_customer_id;
 RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.admin_customer_history(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_customer_history(uuid) TO authenticated;

-- 6) Smart dashboard summary
CREATE OR REPLACE FUNCTION public.admin_smart_summary()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object(
  'today_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=current_date),0),
  'today_profit',COALESCE((SELECT SUM((unit_price-unit_cost)*quantity) FROM public.sale_items WHERE created_at>=current_date),0),
  'low_stock',COALESCE((SELECT COUNT(*) FROM (SELECT pr.id,COALESCE(SUM(b.quantity),0) q,COALESCE(pr.reorder_level,0) r FROM public.products pr LEFT JOIN public.batches b ON b.product_id=pr.id GROUP BY pr.id,pr.reorder_level HAVING COALESCE(SUM(b.quantity),0)<=COALESCE(pr.reorder_level,0)) x),0),
  'expired',COALESCE((SELECT COUNT(*) FROM public.batches WHERE expiry_date<current_date AND quantity>0),0),
  'expiring_30',COALESCE((SELECT COUNT(*) FROM public.batches WHERE expiry_date>=current_date AND expiry_date<=current_date+30 AND quantity>0),0),
  'dead_stock',COALESCE((SELECT COUNT(*) FROM public.products pr WHERE NOT EXISTS(SELECT 1 FROM public.sale_items si WHERE si.product_id=pr.id AND si.created_at>=now()-interval '90 days') AND EXISTS(SELECT 1 FROM public.batches b WHERE b.product_id=pr.id AND b.quantity>0)),0),
  'today_orders',COALESCE((SELECT COUNT(*) FROM public.orders WHERE created_at>=current_date),0),
  'new_prescriptions',COALESCE((SELECT COUNT(*) FROM public.prescriptions WHERE status IN ('new','pending','review') ),0)
 ) INTO v;
 RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.admin_smart_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_smart_summary() TO authenticated;

-- 7) Audit for product price changes
CREATE OR REPLACE FUNCTION public.audit_product_changes() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
BEGIN
 IF public.is_admin() AND (NEW.sale_price IS DISTINCT FROM OLD.sale_price OR NEW.purchase_price IS DISTINCT FROM OLD.purchase_price) THEN
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'admin_update_product_price','product',NEW.id,jsonb_build_object('product_name',NEW.name,'old_purchase_price',OLD.purchase_price,'new_purchase_price',NEW.purchase_price,'old_sale_price',OLD.sale_price,'new_sale_price',NEW.sale_price));
 END IF;
 RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_audit_product_changes ON public.products;
CREATE TRIGGER trg_audit_product_changes AFTER UPDATE OF purchase_price,sale_price ON public.products FOR EACH ROW EXECUTE FUNCTION public.audit_product_changes();

-- 8) Better indexes
CREATE INDEX IF NOT EXISTS idx_batches_expiry_quantity ON public.batches(expiry_date,quantity);
CREATE INDEX IF NOT EXISTS idx_batches_product_quantity ON public.batches(product_id,quantity);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_created ON public.sale_items(product_id,created_at);
CREATE INDEX IF NOT EXISTS idx_orders_customer_created ON public.orders(customer_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_returns_created ON public.returns(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON public.audit_logs(created_at DESC);

COMMIT;
