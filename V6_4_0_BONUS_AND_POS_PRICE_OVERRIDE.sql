-- Pharmacy Abdelhadi V6.4.0
-- Two integrated features:
-- 1) Purchase bonus/free units: bonus is excluded from invoice value/debt, but enters stock as zero-cost sellable stock.
-- 2) POS per-line net-price override: affects only the current sale line; never updates product/purchase/inventory prices.
-- Also keeps dashboard/reports/day-details/supplier returns consistent with the new fields.
BEGIN;

-- =========================================================
-- 1) Schema additions (non-destructive)
-- =========================================================
ALTER TABLE public.purchase_items
  ADD COLUMN IF NOT EXISTS bonus_quantity numeric NOT NULL DEFAULT 0;

ALTER TABLE public.sale_items
  ADD COLUMN IF NOT EXISTS base_unit_price numeric;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname='purchase_items_bonus_quantity_nonnegative'
      AND conrelid='public.purchase_items'::regclass
  ) THEN
    ALTER TABLE public.purchase_items
      ADD CONSTRAINT purchase_items_bonus_quantity_nonnegative CHECK (bonus_quantity>=0);
  END IF;
END $$;

-- =========================================================
-- 2) Purchase creation: paid quantity + bonus quantity.
--    Paid batch keeps invoice purchase price; bonus batch is zero-cost.
--    Therefore invoice total/debt uses paid quantity only, while stock gets both.
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_create_purchase(
  p_supplier_id uuid,
  p_invoice_number text DEFAULT NULL,
  p_invoice_date date DEFAULT CURRENT_DATE,
  p_notes text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE
  v_purchase_id uuid:=gen_random_uuid(); v_item jsonb; v_item_id uuid;
  v_batch_id uuid; v_bonus_batch_id uuid; v_total numeric:=0;
  v_qty numeric; v_bonus numeric; v_purchase_price numeric; v_sale_price numeric;
  v_product_id uuid; v_expiry date; v_invoice text; v_bonus_total numeric:=0;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_supplier_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.suppliers WHERE id=p_supplier_id) THEN RAISE EXCEPTION 'Supplier not found'; END IF;
  IF jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN RAISE EXCEPTION 'Purchase invoice must contain at least one item'; END IF;
  v_invoice:=NULLIF(trim(COALESCE(p_invoice_number,'')),'');
  IF v_invoice IS NULL THEN v_invoice:='PUR-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'); END IF;

  INSERT INTO public.purchases(supplier_id,invoice_number,invoice_date,notes,status,total)
  VALUES(p_supplier_id,v_invoice,COALESCE(p_invoice_date,CURRENT_DATE),NULLIF(trim(COALESCE(p_notes,'')),''),'received',0)
  RETURNING id INTO v_purchase_id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id:=NULLIF(v_item->>'product_id','')::uuid;
    v_qty:=COALESCE((v_item->>'quantity')::numeric,0);
    v_bonus:=GREATEST(COALESCE((v_item->>'bonus_quantity')::numeric,0),0);
    v_purchase_price:=COALESCE((v_item->>'purchase_price')::numeric,0);
    v_sale_price:=COALESCE((v_item->>'sale_price')::numeric,0);
    v_expiry:=NULLIF(v_item->>'expiry_date','')::date;
    IF v_product_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.products WHERE id=v_product_id) THEN RAISE EXCEPTION 'Invalid product in purchase invoice'; END IF;
    IF v_qty<=0 THEN RAISE EXCEPTION 'Purchase quantity must be greater than zero'; END IF;
    IF v_expiry IS NULL THEN RAISE EXCEPTION 'Expiry date is required for every purchase item'; END IF;
    IF v_purchase_price<0 OR v_sale_price<0 THEN RAISE EXCEPTION 'Prices cannot be negative'; END IF;

    INSERT INTO public.purchase_items(purchase_id,product_id,quantity,bonus_quantity,purchase_price,expiry_date,sale_price)
    VALUES(v_purchase_id,v_product_id,v_qty,v_bonus,v_purchase_price,v_expiry,v_sale_price)
    RETURNING id INTO v_item_id;

    -- Paid stock: normal purchase cost.
    v_batch_id:=gen_random_uuid();
    INSERT INTO public.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,received_date,supplier_id,purchase_id,purchase_item_id)
    VALUES(v_batch_id,v_product_id,'AUTO-'||substr(replace(v_item_id::text,'-',''),1,12),v_expiry,v_qty,v_purchase_price,COALESCE(p_invoice_date,CURRENT_DATE),p_supplier_id,v_purchase_id,v_item_id);
    UPDATE public.purchase_items SET batch_id=v_batch_id WHERE id=v_item_id;
    INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
    VALUES(v_product_id,v_batch_id,'purchase',v_qty,'استلام فاتورة شراء '||v_invoice,auth.uid());

    -- Bonus stock: separate zero-cost batch, same expiry/purchase traceability.
    IF v_bonus>0 THEN
      v_bonus_batch_id:=gen_random_uuid();
      INSERT INTO public.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,received_date,supplier_id,purchase_id,purchase_item_id)
      VALUES(v_bonus_batch_id,v_product_id,'AUTO-'||substr(replace(v_item_id::text,'-',''),1,12)||'-BONUS',v_expiry,v_bonus,0,COALESCE(p_invoice_date,CURRENT_DATE),p_supplier_id,v_purchase_id,v_item_id);
      INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
      VALUES(v_product_id,v_bonus_batch_id,'purchase_bonus',v_bonus,'بونص مجاني من فاتورة شراء '||v_invoice,auth.uid());
    END IF;

    -- Product defaults are based on the paid invoice price only; bonus never changes them.
    UPDATE public.products
    SET purchase_price=v_purchase_price,
        sale_price=CASE WHEN v_sale_price>0 THEN v_sale_price ELSE sale_price END,
        updated_at=now()
    WHERE id=v_product_id;

    v_total:=v_total+(v_qty*v_purchase_price);
    v_bonus_total:=v_bonus_total+v_bonus;
  END LOOP;

  UPDATE public.purchases SET total=v_total WHERE id=v_purchase_id;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'admin_create_purchase','purchase',v_purchase_id,
         jsonb_build_object('supplier_id',p_supplier_id,'invoice_number',v_invoice,'total',v_total,'bonus_quantity',v_bonus_total,'items_count',jsonb_array_length(p_items)));
  RETURN jsonb_build_object('id',v_purchase_id,'public_code',v_invoice,'total',v_total,'bonus_quantity',v_bonus_total);
END; $$;
REVOKE ALL ON FUNCTION public.admin_create_purchase(uuid,text,date,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_purchase(uuid,text,date,text,jsonb) TO authenticated;

-- =========================================================
-- 3) Purchase list/detail expose bonus quantity without changing totals.
-- =========================================================
DROP FUNCTION IF EXISTS public.admin_list_purchases();
CREATE OR REPLACE FUNCTION public.admin_list_purchases()
RETURNS TABLE(
 id uuid,supplier_id uuid,supplier_name text,invoice_number text,invoice_date date,total numeric,status text,notes text,created_at timestamptz,item_count bigint,bonus_quantity numeric,paid_amount numeric,due_amount numeric,payment_status text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT p.id,p.supplier_id,s.name,p.invoice_number,p.invoice_date,p.total,p.status,p.notes,p.created_at,
        COUNT(pi.id)::bigint,COALESCE(SUM(pi.bonus_quantity),0),p.paid_amount,p.due_amount,p.payment_status
 FROM public.purchases p
 LEFT JOIN public.suppliers s ON s.id=p.supplier_id
 LEFT JOIN public.purchase_items pi ON pi.purchase_id=p.id
 WHERE public.is_admin()
 GROUP BY p.id,s.name
 ORDER BY COALESCE(p.invoice_date,p.created_at::date) DESC,p.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.admin_list_purchases() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_purchases() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_get_purchase_detail(p_purchase_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object(
  'id',p.id,'supplier_id',p.supplier_id,'supplier_name',s.name,'invoice_number',p.invoice_number,'invoice_date',p.invoice_date,
  'total',p.total,'paid_amount',p.paid_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,'status',p.status,'notes',p.notes,'created_at',p.created_at,
  'bonus_quantity',COALESCE((SELECT SUM(pi2.bonus_quantity) FROM public.purchase_items pi2 WHERE pi2.purchase_id=p.id),0),
  'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pi.id,'product_id',pi.product_id,'product_name',pr.name,'barcode',pr.barcode,'active_ingredient',pr.active_ingredient,'quantity',pi.quantity,'bonus_quantity',pi.bonus_quantity,'total_quantity',pi.quantity+pi.bonus_quantity,'purchase_price',pi.purchase_price,'sale_price',pi.sale_price,'expiry_date',pi.expiry_date,'batch_id',pi.batch_id) ORDER BY pi.id) FROM public.purchase_items pi JOIN public.products pr ON pr.id=pi.product_id WHERE pi.purchase_id=p.id),'[]'::jsonb),
  'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',sp.id,'amount',sp.amount,'payment_method',sp.payment_method,'notes',sp.notes,'created_at',sp.created_at,'cashbox_entry_id',sp.cashbox_entry_id) ORDER BY sp.created_at DESC) FROM public.supplier_payment_allocations spa JOIN public.supplier_payments sp ON sp.id=spa.payment_id WHERE spa.purchase_id=p.id),'[]'::jsonb)
 ) INTO v
 FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id WHERE p.id=p_purchase_id;
 RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.admin_get_purchase_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_purchase_detail(uuid) TO authenticated;

-- =========================================================
-- 4) Supplier returns: bonus batches are also returnable, at zero value.
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_supplier_return_bundle(
 p_purchase_id uuid,p_mode text,p_items jsonb DEFAULT '[]'::jsonb,p_reason text DEFAULT 'مرتجع إلى المورد'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE r record; it jsonb; v_batch uuid; v_qty numeric; v_total numeric:=0; v_count integer:=0; v_items jsonb:='[]'::jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_purchase_id IS NULL OR p_mode NOT IN ('full','count_1','count_2','count_3','selected') THEN RAISE EXCEPTION 'نوع المرتجع غير صالح'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.purchases WHERE id=p_purchase_id) THEN RAISE EXCEPTION 'فاتورة الشراء غير موجودة'; END IF;
 IF p_mode<>'full' AND jsonb_typeof(COALESCE(p_items,'[]'::jsonb))<>'array' THEN RAISE EXCEPTION 'بيانات المنتجات غير صالحة'; END IF;
 IF p_mode='full' THEN
   FOR r IN
     SELECT pi.id purchase_item_id,b.id batch_id,b.product_id,pr.name product_name,
            LEAST(COALESCE(b.quantity,0),GREATEST(pi.quantity+pi.bonus_quantity-COALESCE((SELECT SUM(rr.quantity) FROM public.returns rr WHERE rr.return_type='supplier' AND rr.batch_id=b.id),0),0)) returnable_qty,
            b.purchase_price
     FROM public.purchase_items pi JOIN public.batches b ON b.purchase_item_id=pi.id JOIN public.products pr ON pr.id=pi.product_id
     WHERE pi.purchase_id=p_purchase_id AND COALESCE(b.quantity,0)>0
     FOR UPDATE OF b
   LOOP
     IF r.returnable_qty<=0 THEN CONTINUE; END IF;
     UPDATE public.batches SET quantity=quantity-r.returnable_qty WHERE id=r.batch_id;
     INSERT INTO public.returns(return_type,purchase_id,product_id,batch_id,quantity,amount,reason,created_by)
     VALUES('supplier',p_purchase_id,r.product_id,r.batch_id,r.returnable_qty,r.returnable_qty*r.purchase_price,COALESCE(p_reason,'مرتجع إلى المورد'),auth.uid());
     INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by)
     VALUES(r.product_id,r.batch_id,'supplier_return',-r.returnable_qty,p_purchase_id,COALESCE(p_reason,'مرتجع إلى المورد'),auth.uid());
     v_total:=v_total+r.returnable_qty*r.purchase_price; v_count:=v_count+1;
     v_items:=v_items||jsonb_build_object('product_name',r.product_name,'quantity',r.returnable_qty,'amount',r.returnable_qty*r.purchase_price,'bonus_batch',r.purchase_price=0);
   END LOOP;
 ELSE
   IF p_mode='count_1' AND jsonb_array_length(COALESCE(p_items,'[]'::jsonb))<>1 THEN RAISE EXCEPTION 'يجب تحديد منتج واحد فقط'; END IF;
   IF p_mode='count_2' AND jsonb_array_length(COALESCE(p_items,'[]'::jsonb))<>2 THEN RAISE EXCEPTION 'يجب تحديد منتجين فقط'; END IF;
   IF p_mode='count_3' AND jsonb_array_length(COALESCE(p_items,'[]'::jsonb))<>3 THEN RAISE EXCEPTION 'يجب تحديد ثلاثة منتجات فقط'; END IF;
   IF p_mode='selected' AND jsonb_array_length(COALESCE(p_items,'[]'::jsonb))<1 THEN RAISE EXCEPTION 'يجب تحديد منتج واحد على الأقل'; END IF;
   FOR it IN SELECT value FROM jsonb_array_elements(COALESCE(p_items,'[]'::jsonb)) LOOP
     v_batch:=NULLIF(it->>'batch_id','')::uuid; v_qty:=COALESCE((it->>'quantity')::numeric,0);
     IF v_batch IS NULL OR v_qty<=0 THEN RAISE EXCEPTION 'كل منتج مرتجع يحتاج دفعة وكمية موجبة'; END IF;
     SELECT b.id,b.product_id,pr.name,b.quantity,b.purchase_price,pi.quantity+pi.bonus_quantity AS invoice_qty
     INTO r FROM public.batches b JOIN public.purchase_items pi ON pi.id=b.purchase_item_id AND pi.purchase_id=p_purchase_id JOIN public.products pr ON pr.id=b.product_id
     WHERE b.id=v_batch FOR UPDATE OF b;
     IF NOT FOUND THEN RAISE EXCEPTION 'الدفعة المحددة ليست ضمن فاتورة الشراء'; END IF;
     IF v_qty>COALESCE(r.quantity,0) THEN RAISE EXCEPTION 'كمية المرتجع أكبر من الرصيد المتاح للمنتج: %',r.name; END IF;
     IF v_qty>GREATEST(r.quantity-COALESCE((SELECT SUM(rr.quantity) FROM public.returns rr WHERE rr.return_type='supplier' AND rr.batch_id=v_batch),0),0) THEN RAISE EXCEPTION 'كمية المرتجع تتجاوز الكمية القابلة للإرجاع للمنتج: %',r.name; END IF;
     UPDATE public.batches SET quantity=quantity-v_qty WHERE id=v_batch;
     INSERT INTO public.returns(return_type,purchase_id,product_id,batch_id,quantity,amount,reason,created_by) VALUES('supplier',p_purchase_id,r.product_id,v_batch,v_qty,v_qty*r.purchase_price,COALESCE(p_reason,'مرتجع إلى المورد'),auth.uid());
     INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,note,created_by) VALUES(r.product_id,v_batch,'supplier_return',-v_qty,p_purchase_id,COALESCE(p_reason,'مرتجع إلى المورد'),auth.uid());
     v_total:=v_total+v_qty*r.purchase_price; v_count:=v_count+1; v_items:=v_items||jsonb_build_object('product_name',r.name,'quantity',v_qty,'amount',v_qty*r.purchase_price,'bonus_batch',r.purchase_price=0);
   END LOOP;
 END IF;
 IF v_count=0 THEN RAISE EXCEPTION 'لا توجد كمية متاحة للإرجاع في هذه الفاتورة'; END IF;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'supplier_return','purchase',p_purchase_id,jsonb_build_object('mode',p_mode,'items',v_items,'total_amount',v_total,'reason',p_reason));
 RETURN jsonb_build_object('purchase_id',p_purchase_id,'items_count',v_count,'total_amount',v_total,'items',v_items);
END; $$;
REVOKE ALL ON FUNCTION public.admin_supplier_return_bundle(uuid,text,jsonb,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_supplier_return_bundle(uuid,text,jsonb,text) TO authenticated;

-- =========================================================
-- 5) POS: line-level price override, product price remains untouched.
-- =========================================================
CREATE OR REPLACE FUNCTION public.complete_sale_accounting(
 p_items jsonb,p_discount numeric DEFAULT 0,p_payment_method text DEFAULT 'cash',p_debtor_id uuid DEFAULT NULL,p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE
 v_sale_id uuid:=gen_random_uuid(); it jsonb; b record; need numeric; take numeric; sub numeric:=0; v_total numeric:=0; v_paid numeric:=0; v_due numeric:=0;
 v_debtor_name text; v_product_id uuid; v_unit_price numeric; v_base_price numeric; v_overrides jsonb:='[]'::jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF jsonb_typeof(COALESCE(p_items,'[]'::jsonb))<>'array' OR jsonb_array_length(COALESCE(p_items,'[]'::jsonb))=0 THEN RAISE EXCEPTION 'Sale must contain items'; END IF;
 IF COALESCE(p_discount,0)<0 THEN RAISE EXCEPTION 'Invalid discount'; END IF;
 IF p_payment_method NOT IN ('cash','credit') THEN RAISE EXCEPTION 'Invalid payment method'; END IF;
 IF p_payment_method='credit' AND p_debtor_id IS NULL THEN RAISE EXCEPTION 'اختر ملف المتدين أولاً'; END IF;
 IF p_debtor_id IS NOT NULL THEN SELECT name INTO v_debtor_name FROM public.debtors WHERE id=p_debtor_id; IF NOT FOUND THEN RAISE EXCEPTION 'ملف المتدين غير موجود'; END IF; END IF;
 INSERT INTO public.sales(id,customer_id,debtor_id,subtotal,discount,total,created_by,payment_method,paid_amount,due_amount,payment_notes)
 VALUES(v_sale_id,NULL,p_debtor_id,0,GREATEST(COALESCE(p_discount,0),0),0,auth.uid(),p_payment_method,0,0,p_notes);
 FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   v_product_id:=NULLIF(it->>'product_id','')::uuid; need:=COALESCE((it->>'quantity')::numeric,0); v_unit_price:=COALESCE((it->>'unit_price')::numeric,0);
   IF v_product_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.products WHERE id=v_product_id) THEN RAISE EXCEPTION 'Invalid sale product'; END IF;
   IF need<=0 THEN RAISE EXCEPTION 'Invalid quantity'; END IF;
   IF v_unit_price<0 THEN RAISE EXCEPTION 'سعر البيع لا يمكن أن يكون سالباً'; END IF;
   SELECT COALESCE(p.sale_price,0) INTO v_base_price FROM public.products p WHERE p.id=v_product_id;
   IF ABS(v_unit_price-v_base_price)>0.000001 THEN
     v_overrides:=v_overrides||jsonb_build_object('product_id',v_product_id,'base_unit_price',v_base_price,'final_unit_price',v_unit_price,'difference',v_unit_price-v_base_price);
   END IF;
   FOR b IN SELECT bt.id,bt.quantity,bt.purchase_price,bt.expiry_date FROM public.batches bt WHERE bt.product_id=v_product_id AND bt.quantity>0 AND (bt.expiry_date IS NULL OR bt.expiry_date>=current_date) ORDER BY bt.expiry_date NULLS LAST,bt.received_date NULLS FIRST,bt.batch_number NULLS LAST,bt.id FOR UPDATE OF bt LOOP
     EXIT WHEN need<=0; take:=LEAST(need,b.quantity); UPDATE public.batches bt SET quantity=bt.quantity-take WHERE bt.id=b.id;
     INSERT INTO public.sale_items(sale_id,product_id,batch_id,quantity,unit_price,unit_cost,base_unit_price) VALUES(v_sale_id,v_product_id,b.id,take,v_unit_price,b.purchase_price,v_base_price);
     INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,created_by) VALUES(v_product_id,b.id,'sale',-take,v_sale_id,auth.uid());
     sub:=sub+take*v_unit_price; need:=need-take;
   END LOOP;
   IF need>0 THEN RAISE EXCEPTION 'Insufficient non-expired stock for product %',v_product_id; END IF;
 END LOOP;
 v_total:=GREATEST(sub-GREATEST(COALESCE(p_discount,0),0),0);
 IF p_payment_method='cash' THEN v_paid:=v_total; v_due:=0; ELSE v_paid:=0; v_due:=v_total; END IF;
 UPDATE public.sales s SET subtotal=sub,total=v_total,paid_amount=v_paid,due_amount=v_due WHERE s.id=v_sale_id;
 IF p_payment_method='credit' THEN
   INSERT INTO public.debtor_transactions(debtor_id,transaction_type,sale_id,amount,debit,credit,payment_method,notes,created_by) VALUES(p_debtor_id,'sale',v_sale_id,v_total,v_total,0,'credit',p_notes,auth.uid());
 ELSE
   INSERT INTO public.cashbox_entries(entry_type,amount,description,sale_id,created_by) VALUES('sale_cash',v_total,'بيع نقدي',v_sale_id,auth.uid());
 END IF;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'complete_sale','sale',v_sale_id,jsonb_build_object('subtotal',sub,'discount',p_discount,'total',v_total,'payment_method',p_payment_method,'debtor_id',p_debtor_id,'debtor_name',v_debtor_name,'paid_amount',v_paid,'due_amount',v_due,'price_overrides',v_overrides,'notes',p_notes));
 RETURN jsonb_build_object('sale_id',v_sale_id,'total',v_total,'payment_method',p_payment_method,'debtor_id',p_debtor_id,'paid_amount',v_paid,'due_amount',v_due,'price_overrides',v_overrides);
END; $$;
REVOKE ALL ON FUNCTION public.complete_sale_accounting(jsonb,numeric,text,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_sale_accounting(jsonb,numeric,text,uuid,text) TO authenticated;

-- =========================================================
-- 6) Dashboard day-details and reports expose bonus quantities only; financial totals remain unchanged.
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_dashboard_day_details(p_start timestamptz,p_end timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v jsonb; f jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid dashboard day range'; END IF;
 f:=public.admin_dashboard_financial_summary(p_start,p_end);
 SELECT jsonb_build_object(
  'period',jsonb_build_object('start',p_start,'end',p_end),'summary',f,
  'sales',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,'invoice_number',s.id::text,'total',s.total,'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount,'debtor_name',d.name,'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',p.name,'barcode',p.barcode,'quantity',si.quantity,'unit_price',si.unit_price,'base_unit_price',si.base_unit_price,'line_total',si.quantity*si.unit_price) ORDER BY p.name) FROM public.sale_items si LEFT JOIN public.products p ON p.id=si.product_id WHERE si.sale_id=s.id),'[]'::jsonb)) ORDER BY s.created_at DESC) FROM public.sales s LEFT JOIN public.debtors d ON d.id=s.debtor_id WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
  'purchases',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,'supplier_name',sp.name,'total',p.total,'paid_amount',p.paid_amount,'due_amount',p.due_amount,'payment_status',p.payment_status,'item_count',(SELECT COUNT(*) FROM public.purchase_items pi WHERE pi.purchase_id=p.id),'bonus_quantity',(SELECT COALESCE(SUM(pi2.bonus_quantity),0) FROM public.purchase_items pi2 WHERE pi2.purchase_id=p.id)) ORDER BY p.created_at DESC) FROM public.purchases p LEFT JOIN public.suppliers sp ON sp.id=p.supplier_id WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb),
  'cashbox',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,'type',c.entry_type,'amount',c.amount,'description',c.description) ORDER BY c.created_at DESC) FROM public.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb),
  'returns',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',pr.name,'quantity',r.quantity,'amount',r.amount,'reason',r.reason) ORDER BY r.created_at DESC) FROM public.returns r LEFT JOIN public.products pr ON pr.id=r.product_id WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb),
  'debtor_payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,'debtor_name',d.name,'amount',t.credit,'payment_method',t.payment_method,'notes',t.notes) ORDER BY t.created_at DESC) FROM public.debtor_transactions t JOIN public.debtors d ON d.id=t.debtor_id WHERE t.transaction_type='payment' AND t.created_at>=p_start AND t.created_at<p_end),'[]'::jsonb),
  'orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',o.id,'created_at',o.created_at,'public_code',o.public_code,'customer_name',c.name,'customer_phone',c.phone,'status',o.status,'total',o.total) ORDER BY o.created_at DESC) FROM public.orders o LEFT JOIN public.customers c ON c.id=o.customer_id WHERE o.created_at>=p_start AND o.created_at<p_end),'[]'::jsonb),
  'prescriptions',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pr.id,'created_at',pr.created_at,'customer_name',pr.customer_name,'customer_phone',pr.customer_phone,'status',pr.status,'file_name',pr.file_name) ORDER BY pr.created_at DESC) FROM public.prescriptions pr WHERE pr.created_at>=p_start AND pr.created_at<p_end),'[]'::jsonb),
  'supplier_payments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',sp.id,'created_at',sp.created_at,'supplier_name',s.name,'amount',sp.amount,'payment_method',sp.payment_method,'notes',sp.notes) ORDER BY sp.created_at DESC) FROM public.supplier_payments sp JOIN public.suppliers s ON s.id=sp.supplier_id WHERE sp.created_at>=p_start AND sp.created_at<p_end),'[]'::jsonb)
 ) INTO v;
 RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.admin_dashboard_day_details(timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_day_details(timestamptz,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_accounting_report(p_start timestamptz,p_end timestamptz,p_compare_start timestamptz DEFAULT NULL,p_compare_end timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v jsonb; f jsonb; cf jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 f:=public.admin_dashboard_financial_summary(p_start,p_end);
 cf:=CASE WHEN p_compare_start IS NULL OR p_compare_end IS NULL THEN NULL ELSE public.admin_dashboard_financial_summary(p_compare_start,p_compare_end) END;
 SELECT jsonb_build_object(
  'period',jsonb_build_object('start',p_start,'end',p_end),
  'summary',jsonb_build_object('sales',COALESCE((f->>'sales')::numeric,0),'cash_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0),'credit_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),'debt_collections',COALESCE((f->>'debtor_payments')::numeric,0),'new_debt',COALESCE((SELECT SUM(debit) FROM public.debtor_transactions WHERE transaction_type='sale' AND created_at>=p_start AND created_at<p_end),0),'purchases',COALESCE((f->>'purchases')::numeric,0),'gross_profit',COALESCE((f->>'profit')::numeric,0),'return_profit',COALESCE((f->>'customer_return_cost')::numeric,0),'supplier_returns',COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end),0),'net_purchases',COALESCE((f->>'purchases')::numeric,0)-COALESCE((SELECT SUM(amount) FROM public.returns WHERE return_type='supplier' AND created_at>=p_start AND created_at<p_end),0),'profit',COALESCE((f->>'profit')::numeric,0),'margin',COALESCE((f->>'margin')::numeric,0),'cash_in',COALESCE((f->>'cash_in')::numeric,0),'cash_out',COALESCE((f->>'cash_out')::numeric,0),'cash_net',COALESCE((f->>'cash_net')::numeric,0),'cash_balance',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries),0),'outstanding_debt',COALESCE((SELECT SUM(debit-credit) FROM public.debtor_transactions),0),'sales_count',COALESCE((f->>'invoice_count')::bigint,0),'purchase_count',COALESCE((f->>'purchase_count')::bigint,0),'customer_returns',COALESCE((f->>'customer_returns')::numeric,0),'net_sales',COALESCE((f->>'net_sales')::numeric,0),'cost_of_goods',COALESCE((f->>'cost_of_goods')::numeric,0)),
  'comparison',CASE WHEN cf IS NULL THEN NULL ELSE jsonb_build_object('sales',COALESCE((cf->>'sales')::numeric,0),'net_sales',COALESCE((cf->>'net_sales')::numeric,0),'purchases',COALESCE((cf->>'purchases')::numeric,0),'profit',COALESCE((cf->>'profit')::numeric,0),'new_debt',COALESCE((SELECT SUM(debit) FROM public.debtor_transactions WHERE transaction_type='sale' AND created_at>=p_compare_start AND created_at<p_compare_end),0),'debt_collections',COALESCE((cf->>'debtor_payments')::numeric,0)) END,
  'sales_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,'total',s.total,'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount,'debtor_id',s.debtor_id,'debtor_name',d.name) ORDER BY s.created_at DESC) FROM public.sales s LEFT JOIN public.debtors d ON d.id=s.debtor_id WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
  'purchase_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,'supplier_name',s.name,'total',p.total,'bonus_quantity',COALESCE((SELECT SUM(pi.bonus_quantity) FROM public.purchase_items pi WHERE pi.purchase_id=p.id),0)) ORDER BY p.created_at DESC) FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb),
  'debt_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,'type',t.transaction_type,'debtor_name',d.name,'amount',t.amount,'debit',t.debit,'credit',t.credit,'notes',t.notes) ORDER BY t.created_at DESC) FROM public.debtor_transactions t JOIN public.debtors d ON d.id=t.debtor_id WHERE t.created_at>=p_start AND t.created_at<p_end),'[]'::jsonb),
  'cash_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,'type',c.entry_type,'amount',c.amount,'description',c.description) ORDER BY c.created_at DESC) FROM public.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb),
  'return_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'type',r.return_type,'product_name',p.name,'quantity',r.quantity,'amount',r.amount,'reason',r.reason) ORDER BY r.created_at DESC) FROM public.returns r LEFT JOIN public.products p ON p.id=r.product_id WHERE r.created_at>=p_start AND r.created_at<p_end),'[]'::jsonb),
  'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_id',x.product_id,'product_name',x.product_name,'quantity',x.quantity,'sales',x.sales,'cost',x.cost,'gross_profit',x.gross_profit,'return_amount',x.return_amount,'return_profit',x.return_profit,'net_sales',x.sales-x.return_amount,'net_profit',x.gross_profit-x.return_profit) ORDER BY (x.sales-x.return_amount) DESC) FROM (SELECT p.id product_id,p.name product_name,SUM(si.quantity) quantity,SUM(si.quantity*si.unit_price) sales,SUM(si.quantity*si.unit_cost) cost,SUM(si.quantity*(si.unit_price-si.unit_cost)) gross_profit,COALESCE((SELECT SUM(r.amount) FROM public.returns r WHERE r.return_type='customer' AND r.product_id=p.id AND r.created_at>=p_start AND r.created_at<p_end),0) return_amount,COALESCE((SELECT SUM(r.quantity*(si2.unit_price-si2.unit_cost)) FROM public.returns r JOIN public.sale_items si2 ON si2.id=r.sale_item_id WHERE r.return_type='customer' AND r.product_id=p.id AND r.created_at>=p_start AND r.created_at<p_end),0) return_profit FROM public.sale_items si JOIN public.products p ON p.id=si.product_id JOIN public.sales s ON s.id=si.sale_id WHERE s.created_at>=p_start AND s.created_at<p_end GROUP BY p.id,p.name) x),'[]'::jsonb),
  'checks',jsonb_build_object('sales_split_delta',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0)-COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),'sales_item_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.sales s WHERE s.created_at>=p_start AND s.created_at<p_end AND ABS(COALESCE((SELECT SUM(si.quantity*si.unit_price) FROM public.sale_items si WHERE si.sale_id=s.id),0)-(COALESCE(s.total,0)+COALESCE(s.discount,0)))>0.01),0),'customer_return_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.returns r JOIN public.sale_items si ON si.id=r.sale_item_id WHERE r.return_type='customer' AND r.created_at>=p_start AND r.created_at<p_end AND r.quantity>(si.quantity+0.000001)),0),'supplier_return_mismatch_count',COALESCE((SELECT COUNT(*) FROM public.returns r JOIN public.purchase_items pi ON pi.id=(SELECT b2.purchase_item_id FROM public.batches b2 WHERE b2.id=r.batch_id) WHERE r.return_type='supplier' AND r.created_at>=p_start AND r.created_at<p_end AND r.quantity>(pi.quantity+pi.bonus_quantity+0.000001)),0),'cash_delta',0)
 ) INTO v;
 RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.admin_accounting_report(timestamptz,timestamptz,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_accounting_report(timestamptz,timestamptz,timestamptz,timestamptz) TO authenticated;

COMMIT;
