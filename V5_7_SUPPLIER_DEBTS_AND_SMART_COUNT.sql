-- Pharmacy Abdelhadi v5.7
-- Smart single-product count aggregation + supplier debts/payments + cashbox linkage + supplier ledger
-- Run AFTER V5_6_ACCOUNTING.sql and V5_6_1_CREDIT_SALE_FIX.sql
BEGIN;

-- =========================================================
-- 1) Supplier debt fields on purchase invoices
-- =========================================================
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS paid_amount numeric NOT NULL DEFAULT 0;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS due_amount numeric NOT NULL DEFAULT 0;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'unpaid';

DO $$ BEGIN
  ALTER TABLE public.purchases DROP CONSTRAINT IF EXISTS purchases_payment_status_check;
  ALTER TABLE public.purchases ADD CONSTRAINT purchases_payment_status_check CHECK(payment_status IN ('unpaid','partial','paid'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

UPDATE public.purchases
SET paid_amount=COALESCE(paid_amount,0),
    due_amount=GREATEST(COALESCE(total,0)-COALESCE(paid_amount,0),0),
    payment_status=CASE
      WHEN COALESCE(paid_amount,0)>=COALESCE(total,0) AND COALESCE(total,0)>0 THEN 'paid'
      WHEN COALESCE(paid_amount,0)>0 THEN 'partial'
      ELSE 'unpaid'
    END;


-- Keep every purchase invoice balance synchronized whenever its total changes.
CREATE OR REPLACE FUNCTION public.sync_purchase_payment_state()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP='INSERT' OR NEW.total IS DISTINCT FROM OLD.total THEN
    NEW.paid_amount:=LEAST(GREATEST(COALESCE(NEW.paid_amount,0),0),COALESCE(NEW.total,0));
    NEW.due_amount:=GREATEST(COALESCE(NEW.total,0)-NEW.paid_amount,0);
    NEW.payment_status:=CASE WHEN NEW.paid_amount>=NEW.total AND NEW.total>0 THEN 'paid' WHEN NEW.paid_amount>0 THEN 'partial' ELSE 'unpaid' END;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_sync_purchase_payment_state ON public.purchases;
CREATE TRIGGER trg_sync_purchase_payment_state
BEFORE INSERT OR UPDATE OF total ON public.purchases
FOR EACH ROW EXECUTE FUNCTION public.sync_purchase_payment_state();

-- =========================================================
-- 2) Supplier payments + invoice allocations
-- =========================================================
CREATE TABLE IF NOT EXISTS public.supplier_payments(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id uuid NOT NULL REFERENCES public.suppliers(id) ON DELETE CASCADE,
  amount numeric NOT NULL CHECK(amount>0),
  payment_method text NOT NULL DEFAULT 'cash',
  notes text,
  cashbox_entry_id uuid REFERENCES public.cashbox_entries(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.cashbox_entries ADD COLUMN IF NOT EXISTS supplier_payment_id uuid;

CREATE TABLE IF NOT EXISTS public.supplier_payment_allocations(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES public.supplier_payments(id) ON DELETE CASCADE,
  purchase_id uuid NOT NULL REFERENCES public.purchases(id) ON DELETE CASCADE,
  amount numeric NOT NULL CHECK(amount>0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(payment_id,purchase_id)
);

ALTER TABLE public.supplier_payments ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='cashbox_entries_supplier_payment_id_fkey') THEN
    ALTER TABLE public.cashbox_entries ADD CONSTRAINT cashbox_entries_supplier_payment_id_fkey FOREIGN KEY (supplier_payment_id) REFERENCES public.supplier_payments(id) ON DELETE SET NULL;
  END IF;
END $$;

ALTER TABLE public.supplier_payment_allocations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin supplier payments" ON public.supplier_payments;
CREATE POLICY "admin supplier payments" ON public.supplier_payments FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());
DROP POLICY IF EXISTS "admin supplier payment allocations" ON public.supplier_payment_allocations;
CREATE POLICY "admin supplier payment allocations" ON public.supplier_payment_allocations FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());

CREATE INDEX IF NOT EXISTS idx_supplier_payments_supplier_created ON public.supplier_payments(supplier_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_supplier_payment_alloc_purchase ON public.supplier_payment_allocations(purchase_id);
CREATE INDEX IF NOT EXISTS idx_purchases_supplier_status ON public.purchases(supplier_id,payment_status,invoice_date DESC);

-- =========================================================
-- 3) Recalculate invoice balances from allocations
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_refresh_purchase_balance(p_purchase_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_total numeric; v_paid numeric;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT COALESCE(total,0) INTO v_total FROM public.purchases WHERE id=p_purchase_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة الشراء غير موجودة'; END IF;
  SELECT COALESCE(SUM(amount),0) INTO v_paid FROM public.supplier_payment_allocations WHERE purchase_id=p_purchase_id;
  UPDATE public.purchases
  SET paid_amount=LEAST(v_paid,v_total),
      due_amount=GREATEST(v_total-v_paid,0),
      payment_status=CASE WHEN v_paid>=v_total AND v_total>0 THEN 'paid' WHEN v_paid>0 THEN 'partial' ELSE 'unpaid' END
  WHERE id=p_purchase_id;
END; $$;
REVOKE ALL ON FUNCTION public.admin_refresh_purchase_balance(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_refresh_purchase_balance(uuid) TO authenticated;

-- =========================================================
-- 4) Record supplier payment, allocate to selected invoice or oldest open invoices,
--    and if cash, create a real cashbox OUT movement.
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_record_supplier_payment(
  p_supplier_id uuid,
  p_amount numeric,
  p_purchase_id uuid DEFAULT NULL,
  p_payment_method text DEFAULT 'cash',
  p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE
  v_payment_id uuid := gen_random_uuid();
  v_cash_id uuid;
  v_remaining numeric := COALESCE(p_amount,0);
  v_invoice_due numeric;
  v_alloc numeric;
  r record;
  v_supplier_name text;
  v_previous_debt numeric;
  v_new_debt numeric;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_supplier_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.suppliers WHERE id=p_supplier_id) THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
  IF COALESCE(p_amount,0)<=0 THEN RAISE EXCEPTION 'مبلغ الدفعة يجب أن يكون أكبر من صفر'; END IF;
  IF p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الدفع غير صالحة'; END IF;
  SELECT name INTO v_supplier_name FROM public.suppliers WHERE id=p_supplier_id;
  SELECT COALESCE(SUM(GREATEST(total-COALESCE(paid_amount,0),0)),0) INTO v_previous_debt FROM public.purchases WHERE supplier_id=p_supplier_id;

  IF p_purchase_id IS NOT NULL THEN
    SELECT GREATEST(COALESCE(total,0)-COALESCE(paid_amount,0),0) INTO v_invoice_due
    FROM public.purchases WHERE id=p_purchase_id AND supplier_id=p_supplier_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'الفاتورة المحددة غير موجودة أو لا تتبع لهذا المورد'; END IF;
    IF v_invoice_due<=0 THEN RAISE EXCEPTION 'هذه الفاتورة مسددة بالكامل'; END IF;
    IF p_amount>v_invoice_due THEN RAISE EXCEPTION 'الدفعة أكبر من المتبقي على الفاتورة: %',v_invoice_due; END IF;
  END IF;

  INSERT INTO public.supplier_payments(id,supplier_id,amount,payment_method,notes,created_by)
  VALUES(v_payment_id,p_supplier_id,p_amount,p_payment_method,NULLIF(trim(COALESCE(p_notes,'')),''),auth.uid());

  IF p_purchase_id IS NOT NULL THEN
    INSERT INTO public.supplier_payment_allocations(payment_id,purchase_id,amount)
    VALUES(v_payment_id,p_purchase_id,p_amount);
    v_remaining:=0;
  ELSE
    FOR r IN
      SELECT id,GREATEST(COALESCE(total,0)-COALESCE(paid_amount,0),0) AS due
      FROM public.purchases
      WHERE supplier_id=p_supplier_id AND GREATEST(COALESCE(total,0)-COALESCE(paid_amount,0),0)>0
      ORDER BY COALESCE(invoice_date,created_at::date),created_at,id
      FOR UPDATE
    LOOP
      EXIT WHEN v_remaining<=0;
      v_alloc:=LEAST(v_remaining,r.due);
      INSERT INTO public.supplier_payment_allocations(payment_id,purchase_id,amount)
      VALUES(v_payment_id,r.id,v_alloc);
      v_remaining:=v_remaining-v_alloc;
    END LOOP;
    IF v_remaining>0 THEN
      DELETE FROM public.supplier_payment_allocations WHERE payment_id=v_payment_id;
      DELETE FROM public.supplier_payments WHERE id=v_payment_id;
      RAISE EXCEPTION 'الدفعة أكبر من إجمالي الدين على المورد';
    END IF;
  END IF;

  FOR r IN SELECT DISTINCT purchase_id FROM public.supplier_payment_allocations WHERE payment_id=v_payment_id LOOP
    PERFORM public.admin_refresh_purchase_balance(r.purchase_id);
  END LOOP;

  IF p_payment_method='cash' THEN
    INSERT INTO public.cashbox_entries(entry_type,amount,description,purchase_id,supplier_payment_id,created_by)
    VALUES('purchase_payment',-abs(p_amount),'دفع للمورد: '||v_supplier_name||CASE WHEN p_purchase_id IS NOT NULL THEN ' — فاتورة '||(SELECT invoice_number FROM public.purchases WHERE id=p_purchase_id) ELSE ' — توزيع على الفواتير المفتوحة' END,p_purchase_id,v_payment_id,auth.uid())
    RETURNING id INTO v_cash_id;
    UPDATE public.supplier_payments SET cashbox_entry_id=v_cash_id WHERE id=v_payment_id;
  END IF;

  SELECT COALESCE(SUM(GREATEST(total-COALESCE(paid_amount,0),0)),0) INTO v_new_debt FROM public.purchases WHERE supplier_id=p_supplier_id;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'supplier_payment','supplier',p_supplier_id,jsonb_build_object(
    'supplier_name',v_supplier_name,'amount',p_amount,'payment_method',p_payment_method,
    'purchase_id',p_purchase_id,'previous_debt',v_previous_debt,'new_debt',v_new_debt,
    'cashbox_entry_id',v_cash_id,'notes',p_notes));

  RETURN jsonb_build_object('payment_id',v_payment_id,'amount',p_amount,'previous_debt',v_previous_debt,'new_debt',v_new_debt,'cashbox_entry_id',v_cash_id);
END; $$;
REVOKE ALL ON FUNCTION public.admin_record_supplier_payment(uuid,numeric,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_record_supplier_payment(uuid,numeric,uuid,text,text) TO authenticated;

-- =========================================================
-- 5) Supplier debt list / ledger / invoices
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_supplier_debt_list()
RETURNS TABLE(
  id uuid,name text,phone text,address text,
  invoice_total numeric,paid_total numeric,balance numeric,
  invoice_count bigint,payment_count bigint,last_payment timestamptz,last_invoice timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
  SELECT s.id,s.name,s.phone,s.address,
    COALESCE((SELECT SUM(COALESCE(p.total,0)) FROM public.purchases p WHERE p.supplier_id=s.id),0),
    COALESCE((SELECT SUM(COALESCE(spa.amount,0)) FROM public.supplier_payment_allocations spa JOIN public.supplier_payments sp ON sp.id=spa.payment_id WHERE sp.supplier_id=s.id),0),
    COALESCE((SELECT SUM(GREATEST(COALESCE(p.total,0)-COALESCE(p.paid_amount,0),0)) FROM public.purchases p WHERE p.supplier_id=s.id),0),
    (SELECT COUNT(*) FROM public.purchases p WHERE p.supplier_id=s.id),
    (SELECT COUNT(*) FROM public.supplier_payments sp WHERE sp.supplier_id=s.id),
    (SELECT MAX(sp.created_at) FROM public.supplier_payments sp WHERE sp.supplier_id=s.id),
    (SELECT MAX(p.created_at) FROM public.purchases p WHERE p.supplier_id=s.id)
  FROM public.suppliers s
  WHERE public.is_admin()
  ORDER BY 7 DESC,s.name;
$$;
REVOKE ALL ON FUNCTION public.admin_supplier_debt_list() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_supplier_debt_list() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_supplier_debt_ledger(p_supplier_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.suppliers WHERE id=p_supplier_id) THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
  SELECT jsonb_build_object(
    'supplier',to_jsonb(s),
    'summary',jsonb_build_object(
      'invoice_total',COALESCE((SELECT SUM(total) FROM public.purchases WHERE supplier_id=s.id),0),
      'paid_total',COALESCE((SELECT SUM(spa.amount) FROM public.supplier_payment_allocations spa JOIN public.supplier_payments sp ON sp.id=spa.payment_id WHERE sp.supplier_id=s.id),0),
      'balance',COALESCE((SELECT SUM(GREATEST(total-COALESCE(paid_amount,0),0)) FROM public.purchases WHERE supplier_id=s.id),0)
    ),
    'invoices',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',p.id,'invoice_number',p.invoice_number,'invoice_date',p.invoice_date,'created_at',p.created_at,
      'total',p.total,'paid_amount',p.paid_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,
      'status',p.status,'notes',p.notes,
      'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',pr.name,'barcode',pr.barcode,'quantity',pi.quantity,'purchase_price',pi.purchase_price,'sale_price',pi.sale_price,'expiry_date',pi.expiry_date,'batch_id',pi.batch_id) ORDER BY pi.id) FROM public.purchase_items pi JOIN public.products pr ON pr.id=pi.product_id WHERE pi.purchase_id=p.id),'[]'::jsonb)
    ) ORDER BY COALESCE(p.invoice_date,p.created_at::date) DESC,p.created_at DESC) FROM public.purchases p WHERE p.supplier_id=s.id),'[]'::jsonb),
    'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',sp.id,'amount',sp.amount,'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,
      'cashbox_entry_id',sp.cashbox_entry_id,
      'allocations',COALESCE((SELECT jsonb_agg(jsonb_build_object('purchase_id',spa.purchase_id,'invoice_number',p2.invoice_number,'amount',spa.amount) ORDER BY p2.invoice_date,p2.created_at) FROM public.supplier_payment_allocations spa JOIN public.purchases p2 ON p2.id=spa.purchase_id WHERE spa.payment_id=sp.id),'[]'::jsonb)
    ) ORDER BY sp.created_at DESC) FROM public.supplier_payments sp WHERE sp.supplier_id=s.id),'[]'::jsonb)
  ) INTO v
  FROM public.suppliers s WHERE s.id=p_supplier_id;
  RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.admin_supplier_debt_ledger(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_supplier_debt_ledger(uuid) TO authenticated;

-- Rebuild supplier purchase history to expose payment state too.
CREATE OR REPLACE FUNCTION public.admin_supplier_purchase_history(p_supplier_id uuid)
RETURNS TABLE(id uuid,invoice_number text,invoice_date date,total numeric,status text,paid_amount numeric,due_amount numeric,payment_status text,created_at timestamptz,item_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT p.id,p.invoice_number,p.invoice_date,p.total,p.status,p.paid_amount,p.due_amount,p.payment_status,p.created_at,COUNT(pi.id)::bigint
 FROM public.purchases p LEFT JOIN public.purchase_items pi ON pi.purchase_id=p.id
 WHERE public.is_admin() AND p.supplier_id=p_supplier_id
 GROUP BY p.id ORDER BY COALESCE(p.invoice_date,p.created_at::date) DESC,p.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.admin_supplier_purchase_history(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_supplier_purchase_history(uuid) TO authenticated;

-- =========================================================
-- 6) Smart inventory: aggregate one product into one count item.
-- Existing count item batch_id becomes nullable; product_id is added.
-- =========================================================
ALTER TABLE public.inventory_count_items ALTER COLUMN batch_id DROP NOT NULL;
ALTER TABLE public.inventory_count_items ADD COLUMN IF NOT EXISTS product_id uuid REFERENCES public.products(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_inventory_count_items_product ON public.inventory_count_items(product_id);

-- Existing batch-based counts keep working. New single-product counts use product_id and one aggregate row.
CREATE OR REPLACE FUNCTION public.admin_start_product_inventory_count(p_product_id uuid,p_notes text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_id uuid; v_stock numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT COALESCE(SUM(quantity),0) INTO v_stock FROM public.batches WHERE product_id=p_product_id;
 IF NOT EXISTS(SELECT 1 FROM public.products WHERE id=p_product_id) THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;
 INSERT INTO public.inventory_counts(created_by,notes) VALUES(auth.uid(),COALESCE(NULLIF(trim(COALESCE(p_notes,'')),''),'جرد منتج واحد')) RETURNING id INTO v_id;
 INSERT INTO public.inventory_count_items(count_id,batch_id,product_id,expected_quantity)
 VALUES(v_id,NULL,p_product_id,v_stock);
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.admin_start_product_inventory_count(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_start_product_inventory_count(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_inventory_count_items(p_count_id uuid)
RETURNS TABLE(id uuid,batch_id uuid,product_id uuid,product_name text,barcode text,expiry_date date,expected_quantity numeric,actual_quantity numeric,difference numeric,supplier_name text,invoice_number text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT i.id,i.batch_id,i.product_id,pr.name,pr.barcode,
   CASE WHEN i.product_id IS NOT NULL THEN NULL ELSE b.expiry_date END,
   i.expected_quantity,i.actual_quantity,i.difference,
   CASE WHEN i.product_id IS NOT NULL THEN NULL ELSE s.name END,
   CASE WHEN i.product_id IS NOT NULL THEN NULL ELSE p.invoice_number END
 FROM public.inventory_count_items i
 LEFT JOIN public.batches b ON b.id=i.batch_id
 JOIN public.products pr ON pr.id=COALESCE(i.product_id,b.product_id)
 LEFT JOIN public.suppliers s ON s.id=b.supplier_id
 LEFT JOIN public.purchases p ON p.id=b.purchase_id
 WHERE public.is_admin() AND i.count_id=p_count_id
 ORDER BY pr.name,b.expiry_date;
$$;
REVOKE ALL ON FUNCTION public.admin_inventory_count_items(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_inventory_count_items(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_complete_inventory_count(p_count_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE r record; v_diff numeric:=0; v_changes integer:=0; v_batch uuid; v_product uuid; v_current numeric; v_target numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF EXISTS(SELECT 1 FROM public.inventory_counts WHERE id=p_count_id AND status<>'open') THEN RAISE EXCEPTION 'Inventory count is not open'; END IF;
 IF EXISTS(SELECT 1 FROM public.inventory_count_items WHERE count_id=p_count_id AND actual_quantity IS NULL) THEN RAISE EXCEPTION 'أدخل الكمية الفعلية لكل منتج'; END IF;

 FOR r IN SELECT * FROM public.inventory_count_items WHERE count_id=p_count_id LOOP
   IF r.product_id IS NOT NULL THEN
     v_product:=r.product_id; v_target:=r.actual_quantity;
     SELECT COALESCE(SUM(quantity),0) INTO v_current FROM public.batches WHERE product_id=v_product;
     IF v_target<>v_current THEN
       SELECT id INTO v_batch FROM public.batches WHERE product_id=v_product ORDER BY quantity DESC,expiry_date NULLS LAST,id LIMIT 1 FOR UPDATE;
       IF v_batch IS NULL AND v_target>0 THEN RAISE EXCEPTION 'لا توجد دفعة لتسوية المنتج %',r.product_id; END IF;
       IF v_batch IS NOT NULL THEN
         UPDATE public.batches SET quantity=GREATEST(0,quantity+(v_target-v_current)) WHERE id=v_batch;
         INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
         VALUES(v_product,v_batch,'inventory_count',v_target-v_current,'تسوية جرد إجمالي للمنتج',auth.uid());
       END IF;
       v_diff:=v_diff+(v_target-v_current); v_changes:=v_changes+1;
     END IF;
   ELSE
     IF r.difference<>0 THEN
       UPDATE public.batches SET quantity=r.actual_quantity WHERE id=r.batch_id;
       SELECT product_id INTO v_product FROM public.batches WHERE id=r.batch_id;
       INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
       VALUES(v_product,r.batch_id,'inventory_count',r.difference,'تسوية جرد v5.5',auth.uid());
       v_diff:=v_diff+r.difference; v_changes:=v_changes+1;
     END IF;
   END IF;
 END LOOP;
 UPDATE public.inventory_counts SET status='completed',completed_at=now() WHERE id=p_count_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'inventory_count_complete','inventory_count',p_count_id,jsonb_build_object('changes',v_changes,'net_difference',v_diff,'mode','aggregate_product'));
 RETURN jsonb_build_object('id',p_count_id,'changes',v_changes,'net_difference',v_diff);
END; $$;
REVOKE ALL ON FUNCTION public.admin_complete_inventory_count(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_complete_inventory_count(uuid) TO authenticated;

-- Product search now exposes total sold and total received in addition to current stock.
CREATE OR REPLACE FUNCTION public.admin_search_inventory_products(p_query text DEFAULT NULL)
RETURNS TABLE(id uuid,name text,barcode text,active_ingredient text,stock numeric,total_received numeric,total_sold numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT p.id,p.name,p.barcode,p.active_ingredient,
   COALESCE((SELECT SUM(b.quantity) FROM public.batches b WHERE b.product_id=p.id),0),
   COALESCE((SELECT SUM(sm.quantity) FROM public.stock_movements sm WHERE sm.product_id=p.id AND sm.movement_type='purchase'),0),
   COALESCE((SELECT SUM(-sm.quantity) FROM public.stock_movements sm WHERE sm.product_id=p.id AND sm.movement_type='sale' AND sm.quantity<0),0)
 FROM public.products p
 WHERE public.is_admin() AND (NULLIF(trim(COALESCE(p_query,'')),'') IS NULL OR p.name ILIKE '%'||trim(p_query)||'%' OR COALESCE(p.active_ingredient,'') ILIKE '%'||trim(p_query)||'%' OR COALESCE(p.barcode,'')=trim(p_query))
 ORDER BY CASE WHEN COALESCE(p.barcode,'')=trim(COALESCE(p_query,'')) THEN 0 ELSE 1 END,p.name LIMIT 30;
$$;
REVOKE ALL ON FUNCTION public.admin_search_inventory_products(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_inventory_products(text) TO authenticated;

COMMIT;
