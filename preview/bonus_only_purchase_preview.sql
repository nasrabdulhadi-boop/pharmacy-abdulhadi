-- PREVIEW ONLY. Apply to a cloned Supabase database, never production.
-- Bonus-only invoice rows: paid quantity 0, bonus quantity > 0, zero invoice charge.
CREATE OR REPLACE FUNCTION public.admin_create_purchase(p_supplier_id uuid, p_invoice_number text DEFAULT NULL::text, p_invoice_date date DEFAULT CURRENT_DATE, p_notes text DEFAULT NULL::text, p_items jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
    IF v_qty<0 OR v_bonus<0 OR v_qty+v_bonus<=0 THEN RAISE EXCEPTION 'Paid and bonus quantities must be nonnegative and their sum positive'; END IF;
    IF v_expiry IS NULL THEN RAISE EXCEPTION 'Expiry date is required for every purchase item'; END IF;
    IF v_purchase_price<0 OR v_sale_price<0 THEN RAISE EXCEPTION 'Prices cannot be negative'; END IF;

    INSERT INTO public.purchase_items(purchase_id,product_id,quantity,bonus_quantity,purchase_price,expiry_date,sale_price)
    VALUES(v_purchase_id,v_product_id,v_qty,v_bonus,v_purchase_price,v_expiry,v_sale_price)
    RETURNING id INTO v_item_id;

    -- Paid stock: normal purchase cost.
    IF v_qty>0 THEN
    v_batch_id:=gen_random_uuid();
    INSERT INTO public.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,received_date,supplier_id,purchase_id,purchase_item_id)
    VALUES(v_batch_id,v_product_id,'AUTO-'||substr(replace(v_item_id::text,'-',''),1,12),v_expiry,v_qty,v_purchase_price,COALESCE(p_invoice_date,CURRENT_DATE),p_supplier_id,v_purchase_id,v_item_id);
    UPDATE public.purchase_items SET batch_id=v_batch_id WHERE id=v_item_id;
    INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
    VALUES(v_product_id,v_batch_id,'purchase',v_qty,'استلام فاتورة شراء '||v_invoice,auth.uid());

    END IF;
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
    SET purchase_price=CASE WHEN v_qty>0 THEN v_purchase_price ELSE purchase_price END,
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
END; $function$


CREATE OR REPLACE FUNCTION public.admin_create_purchase_usd_v1(p_supplier_id uuid, p_new_supplier jsonb, p_invoice_number text, p_invoice_date date, p_notes text, p_items jsonb, p_payment_amount numeric, p_payment_method text, p_payment_notes text, p_discount_type text, p_discount_value numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
 v_supplier uuid:=p_supplier_id; v_supplier_name text; v_id uuid:=gen_random_uuid();
 v_invoice text; v_fx numeric; v_sum numeric:=0; v_discount numeric:=0; v_total numeric:=0;
 v_factor numeric; v_due numeric; v_paid numeric:=COALESCE(p_payment_amount,0);
 v_discount_type text:=COALESCE(NULLIF(p_discount_type,''),'none');
 v_discount_value numeric:=COALESCE(p_discount_value,0);
 v_json jsonb; v_product uuid; v_qty numeric; v_bonus numeric; v_net_usd numeric;
 v_sale_price numeric; v_sale_currency text; v_cost_syp numeric;
 v_expiry date; v_line uuid; v_batch uuid; v_batch_bonus uuid;
 v_payment jsonb:=NULL; v_count int:=0; v_p record; v_seen uuid[]:=ARRAY[]::uuid[];
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT usd_to_syp INTO v_fx FROM public.pharmacy_currency_settings WHERE id=1 FOR SHARE;
 IF v_fx IS NULL OR v_fx<=1 THEN RAISE EXCEPTION 'سعر صرف الدولار غير مضبوط، لا يمكن إنشاء فاتورة'; END IF;
 IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items)=0 THEN
  RAISE EXCEPTION 'فاتورة الشراء تحتاج صنفاً واحداً على الأقل'; END IF;
 IF v_discount_type NOT IN ('none','percent','amount') OR v_discount_value<0 OR
  (v_discount_type='percent' AND v_discount_value>100) THEN RAISE EXCEPTION 'خصم الفاتورة غير صالح'; END IF;
 IF v_paid<0 OR v_paid<>ROUND(v_paid,2) OR p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الدفع أو المبلغ غير صالح'; END IF;
 IF v_supplier IS NULL THEN
   IF jsonb_typeof(p_new_supplier) IS DISTINCT FROM 'object' OR
      NULLIF(trim(p_new_supplier->>'name'),'') IS NULL THEN RAISE EXCEPTION 'اسم المورد مطلوب'; END IF;
   IF EXISTS (SELECT 1 FROM public.suppliers WHERE lower(trim(name))=lower(trim(p_new_supplier->>'name'))) THEN
     RAISE EXCEPTION 'اسم المورد موجود مسبقاً، اختر المورد الحالي'; END IF;
   INSERT INTO public.suppliers(name,phone,address,notes)
   VALUES(trim(p_new_supplier->>'name'),NULLIF(trim(p_new_supplier->>'phone'),''),
    NULLIF(trim(p_new_supplier->>'address'),''),NULLIF(trim(p_new_supplier->>'notes'),''))
   RETURNING id,name INTO v_supplier,v_supplier_name;
 ELSE
   SELECT name INTO v_supplier_name FROM public.suppliers WHERE id=v_supplier;
   IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 END IF;
 -- First pass calculates USD subtotal, validates all products, amounts and expiry.
 FOR v_json IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   v_product:=NULLIF(v_json->>'product_id','')::uuid;
   v_qty:=NULLIF(v_json->>'quantity','')::numeric;
   v_bonus:=COALESCE(NULLIF(v_json->>'bonus_quantity','')::numeric,0);
   v_net_usd:=NULLIF(v_json->>'purchase_price','')::numeric;
   v_sale_price:=NULLIF(v_json->>'sale_price','')::numeric;
   v_expiry:=NULLIF(v_json->>'expiry_date','')::date;
   IF v_product IS NULL OR v_qty IS NULL OR v_qty<0 OR v_bonus<0 OR v_qty+v_bonus<=0 OR v_net_usd IS NULL
      OR (v_qty>0 AND v_net_usd<=0) OR v_sale_price IS NULL OR v_sale_price<=0 OR v_expiry IS NULL THEN
     RAISE EXCEPTION 'بيانات صنف الشراء غير مكتملة أو غير صالحة'; END IF;
   IF v_product=ANY(v_seen) THEN RAISE EXCEPTION 'لا يمكن تكرار الدواء في نفس فاتورة المورد'; END IF;
   v_seen:=array_append(v_seen,v_product);
   IF v_expiry<CURRENT_DATE THEN RAISE EXCEPTION 'لا يمكن شراء دفعة منتهية الصلاحية'; END IF;
   SELECT sale_currency INTO v_sale_currency FROM public.products WHERE id=v_product AND COALESCE(active,true);
   IF NOT FOUND THEN RAISE EXCEPTION 'الدواء المحدد غير موجود أو غير فعّال'; END IF;
   v_sale_currency:=upper(COALESCE(NULLIF(v_json->>'sale_currency',''),v_sale_currency,'SYP'));
   IF v_sale_currency NOT IN ('SYP','USD') THEN RAISE EXCEPTION 'عملة سعر مبيع الصنف غير صالحة'; END IF;
   v_sum:=v_sum+v_qty*v_net_usd; v_count:=v_count+1;
 END LOOP;
 v_sum:=ROUND(v_sum,2);
 IF v_discount_type='percent' THEN v_discount:=ROUND(v_sum*v_discount_value/100,2);
 ELSIF v_discount_type='amount' THEN v_discount:=ROUND(v_discount_value,2); END IF;
 IF v_discount>v_sum THEN RAISE EXCEPTION 'الخصم يتجاوز إجمالي الفاتورة'; END IF;
 v_total:=ROUND(v_sum-v_discount,2); v_due:=v_total-v_paid;
 IF v_paid>v_total THEN RAISE EXCEPTION 'المدفوع أكبر من قيمة الفاتورة بالدولار'; END IF;
 v_factor:=CASE WHEN v_sum>0 THEN v_total/v_sum ELSE 1 END;
 v_invoice:=NULLIF(trim(COALESCE(p_invoice_number,'')),'');
 IF v_invoice IS NULL THEN v_invoice:='USD-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'); END IF;
 INSERT INTO public.purchases(id,supplier_id,invoice_number,invoice_date,notes,status,
   currency,fx_rate,subtotal,discount_type,discount_value,discount_amount,total,total_syp)
 VALUES(v_id,v_supplier,v_invoice,COALESCE(p_invoice_date,CURRENT_DATE),NULLIF(trim(COALESCE(p_notes,'')),''),
  'received','USD',v_fx,v_sum,v_discount_type,v_discount_value,v_discount,v_total,ROUND(v_total*v_fx,2));
 FOR v_json IN SELECT value FROM jsonb_array_elements(p_items) LOOP
   v_product:=(v_json->>'product_id')::uuid;
   v_qty:=(v_json->>'quantity')::numeric;
   v_bonus:=COALESCE(NULLIF(v_json->>'bonus_quantity','')::numeric,0);
   v_net_usd:=(v_json->>'purchase_price')::numeric;
   v_sale_price:=(v_json->>'sale_price')::numeric;
   v_expiry:=(v_json->>'expiry_date')::date;
   SELECT sale_currency INTO v_sale_currency FROM public.products WHERE id=v_product FOR UPDATE;
   v_sale_currency:=upper(COALESCE(NULLIF(v_json->>'sale_currency',''),v_sale_currency,'SYP'));
   -- Net paid inventory cost per item: after invoice discount, in SYP, rate frozen.
   v_cost_syp:=ROUND(v_net_usd*v_fx*v_factor,6);
   INSERT INTO public.purchase_items(purchase_id,product_id,quantity,bonus_quantity,purchase_price,
      expiry_date,sale_price,sale_price_currency,purchase_currency,purchase_fx_rate,purchase_price_syp)
   VALUES(v_id,v_product,v_qty,v_bonus,v_net_usd,v_expiry,v_sale_price,v_sale_currency,'USD',v_fx,v_cost_syp)
   RETURNING id INTO v_line;
   IF v_qty>0 THEN
   v_batch:=gen_random_uuid();
   INSERT INTO public.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,
     received_date,supplier_id,purchase_id,purchase_item_id,purchase_currency,purchase_fx_rate,original_purchase_price)
   VALUES(v_batch,v_product,'USD-'||substr(replace(v_line::text,'-',''),1,12),v_expiry,v_qty,v_cost_syp,
     COALESCE(p_invoice_date,CURRENT_DATE),v_supplier,v_id,v_line,'USD',v_fx,v_net_usd);
   UPDATE public.purchase_items SET batch_id=v_batch WHERE id=v_line;
   INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
   VALUES(v_product,v_batch,'purchase',v_qty,'فاتورة دولار '||v_invoice,auth.uid());
   END IF;
   IF v_bonus>0 THEN
     v_batch_bonus:=gen_random_uuid();
     INSERT INTO public.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,
       received_date,supplier_id,purchase_id,purchase_item_id,purchase_currency,purchase_fx_rate,original_purchase_price)
     VALUES(v_batch_bonus,v_product,'USD-'||substr(replace(v_line::text,'-',''),1,12)||'-BONUS',v_expiry,v_bonus,0,
       COALESCE(p_invoice_date,CURRENT_DATE),v_supplier,v_id,v_line,'USD',v_fx,0);
     INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
     VALUES(v_product,v_batch_bonus,'purchase_bonus',v_bonus,'بونص فاتورة دولار '||v_invoice,auth.uid());
   END IF;
   -- Existing sale prices change only when the invoice explicitly specifies sale_price.
   UPDATE public.products SET purchase_price=CASE WHEN v_qty>0 THEN v_cost_syp ELSE purchase_price END,sale_price=v_sale_price,
      sale_currency=v_sale_currency,updated_at=now() WHERE id=v_product;
 END LOOP;
 IF v_paid>0 THEN
   v_payment:=public.admin_record_supplier_payment_usd_v1(v_supplier,v_paid,v_id,p_payment_method,p_payment_notes);
 ELSE
   PERFORM public.admin_refresh_purchase_balance(v_id);
 END IF;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'create_purchase_usd','purchase',v_id,
 jsonb_build_object('invoice_number',v_invoice,'supplier_id',v_supplier,'subtotal_usd',v_sum,
 'discount_usd',v_discount,'total_usd',v_total,'paid_usd',v_paid,'fx_rate',v_fx,'total_syp',ROUND(v_total*v_fx,2)));
 RETURN jsonb_build_object('id',v_id,'public_code',v_invoice,'supplier_id',v_supplier,
  'supplier_name',v_supplier_name,'currency','USD','fx_rate',v_fx,'total',v_total,
  'total_syp',ROUND(v_total*v_fx,2),'paid_amount',v_paid,'due_amount',v_due,
  'discount_amount',v_discount,'payment',v_payment);
END;
$function$


CREATE OR REPLACE FUNCTION public.admin_create_purchase_syp_v1(p_supplier_id uuid, p_new_supplier jsonb, p_invoice_number text, p_invoice_date date, p_notes text, p_items jsonb, p_payment_amount numeric, p_payment_method text, p_payment_notes text, p_discount_type text, p_discount_value numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE v_result jsonb;v_purchase_id uuid;v_factor numeric;v_item jsonb;v_pid uuid;
 v_currency text;v_fx numeric;v_sale_price numeric;v_used uuid[]:=ARRAY[]::uuid[];
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN
  RAISE EXCEPTION 'فاتورة الشراء فارغة'; END IF;
 FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
  v_pid:=NULLIF(v_item->>'product_id','')::uuid;
  v_currency:=upper(COALESCE(NULLIF(v_item->>'sale_currency',''),'SYP'));
  v_sale_price:=NULLIF(v_item->>'sale_price','')::numeric;
  IF v_pid IS NULL OR v_pid=ANY(v_used) OR v_currency NOT IN ('USD','SYP') THEN
   RAISE EXCEPTION 'صنف مكرر أو عملة بيع غير صالحة'; END IF;
  IF v_sale_price IS NULL OR v_sale_price<=0 THEN RAISE EXCEPTION 'سعر البيع غير صالح'; END IF;
  v_used:=array_append(v_used,v_pid);
 END LOOP;
 SELECT usd_to_syp INTO v_fx FROM public.pharmacy_currency_settings WHERE id=1 FOR SHARE;
 IF v_fx IS NULL THEN RAISE EXCEPTION 'إعداد العملة غير موجود'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_items) x WHERE upper(COALESCE(NULLIF(x->>'sale_currency',''),'SYP'))='USD')
     AND v_fx<=1 THEN RAISE EXCEPTION 'سعر صرف الدولار غير مضبوط لتسعير البيع'; END IF;
 v_result:=public.admin_create_purchase_with_payment_discount(
  p_supplier_id,p_new_supplier,p_invoice_number,p_invoice_date,p_notes,p_items,
  p_payment_amount,p_payment_method,p_payment_notes,p_discount_type,p_discount_value);
 v_purchase_id:=(v_result->>'id')::uuid;
 IF v_purchase_id IS NULL THEN RAISE EXCEPTION 'لم يتم إرجاع رقم فاتورة الشراء'; END IF;
 SELECT CASE WHEN subtotal>0 THEN total/subtotal ELSE 1 END INTO v_factor
 FROM public.purchases WHERE id=v_purchase_id FOR UPDATE;
 IF v_factor<0 OR v_factor>1 THEN RAISE EXCEPTION 'نسبة خصم الفاتورة غير صالحة'; END IF;
 -- Only NEW invoice lines are updated, never existing stock batches.
 UPDATE public.batches b
 SET original_purchase_price=b.purchase_price,
     purchase_price=ROUND(b.purchase_price*v_factor,6),
     purchase_currency='SYP',purchase_fx_rate=1
 WHERE b.purchase_id=v_purchase_id AND b.purchase_price>0;
 UPDATE public.purchase_items pi
 SET purchase_price_syp=ROUND(pi.purchase_price*v_factor,6),
     purchase_currency='SYP',purchase_fx_rate=1,
     sale_price_currency=upper(COALESCE(NULLIF(x.item->>'sale_currency',''),'SYP'))
 FROM (SELECT value item FROM jsonb_array_elements(p_items)) x
 WHERE pi.purchase_id=v_purchase_id AND pi.product_id=(x.item->>'product_id')::uuid;
 UPDATE public.products pr SET
  purchase_price=CASE WHEN pi.quantity>0 THEN ROUND(pi.purchase_price*v_factor,6) ELSE pr.purchase_price END,
  sale_price=pi.sale_price,sale_currency=pi.sale_price_currency,
  updated_at=now()
 FROM public.purchase_items pi WHERE pi.purchase_id=v_purchase_id AND pi.product_id=pr.id;
 UPDATE public.purchases SET currency='SYP',fx_rate=1,total_syp=total WHERE id=v_purchase_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'purchase_syp_currency_aware','purchase',v_purchase_id,
    jsonb_build_object('cost_discount_factor',v_factor,'sale_currency_independent',true));
 RETURN v_result||jsonb_build_object('currency','SYP','fx_rate',1);
END;
$function$

