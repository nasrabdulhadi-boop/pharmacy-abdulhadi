SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90s';

CREATE TEMP TABLE ab_supplier_advance_guard(table_name text PRIMARY KEY,row_count bigint,fingerprint text) ON COMMIT DROP;
DO $guard$
DECLARE r record;v_count bigint;v_hash text;
BEGIN
 FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
  EXECUTE format('SELECT count(*),md5(COALESCE(string_agg(h,''''
   ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(t)::text) h FROM public.%I t)x',r.tablename) INTO v_count,v_hash;
  INSERT INTO ab_supplier_advance_guard VALUES(r.tablename,v_count,v_hash);
 END LOOP;
END $guard$;

CREATE OR REPLACE FUNCTION public._ab_create_purchase_usd_core_v1(p_supplier_id uuid, p_new_supplier jsonb, p_invoice_number text, p_invoice_date date, p_notes text, p_items jsonb, p_payment_amount numeric, p_payment_method text, p_payment_notes text, p_discount_type text, p_discount_value numeric)
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
   IF v_product IS NULL OR v_qty IS NULL OR v_qty<=0 OR v_bonus<0 OR v_net_usd IS NULL
      OR v_net_usd<=0 OR v_sale_price IS NULL OR v_sale_price<=0 OR v_expiry IS NULL THEN
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
   v_batch:=gen_random_uuid();
   INSERT INTO public.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,
     received_date,supplier_id,purchase_id,purchase_item_id,purchase_currency,purchase_fx_rate,original_purchase_price)
   VALUES(v_batch,v_product,'USD-'||substr(replace(v_line::text,'-',''),1,12),v_expiry,v_qty,v_cost_syp,
     COALESCE(p_invoice_date,CURRENT_DATE),v_supplier,v_id,v_line,'USD',v_fx,v_net_usd);
   UPDATE public.purchase_items SET batch_id=v_batch WHERE id=v_line;
   INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
   VALUES(v_product,v_batch,'purchase',v_qty,'فاتورة دولار '||v_invoice,auth.uid());
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
   UPDATE public.products SET purchase_price=v_cost_syp,sale_price=v_sale_price,
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
$function$;
REVOKE ALL ON FUNCTION public._ab_create_purchase_usd_core_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public._ab_create_purchase_syp_core_v1(p_supplier_id uuid, p_new_supplier jsonb, p_invoice_number text, p_invoice_date date, p_notes text, p_items jsonb, p_payment_amount numeric, p_payment_method text, p_payment_notes text, p_discount_type text, p_discount_value numeric)
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
  purchase_price=ROUND(pi.purchase_price*v_factor,6),
  sale_price=pi.sale_price,sale_currency=pi.sale_price_currency,
  updated_at=now()
 FROM public.purchase_items pi WHERE pi.purchase_id=v_purchase_id AND pi.product_id=pr.id;
 UPDATE public.purchases SET currency='SYP',fx_rate=1,total_syp=total WHERE id=v_purchase_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'purchase_syp_currency_aware','purchase',v_purchase_id,
    jsonb_build_object('cost_discount_factor',v_factor,'sale_currency_independent',true));
 RETURN v_result||jsonb_build_object('currency','SYP','fx_rate',1);
END;
$function$;
REVOKE ALL ON FUNCTION public._ab_create_purchase_syp_core_v1(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric) FROM PUBLIC,anon,authenticated;



CREATE OR REPLACE FUNCTION public.admin_record_supplier_payment_advance_v3(p_supplier_id uuid, p_amount numeric, p_debt_currency text, p_tender_currency text, p_fx_rate numeric, p_request_id uuid, p_purchase_id uuid DEFAULT NULL::uuid, p_payment_method text DEFAULT 'cash'::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_settled numeric; v_before numeric; v_after numeric; v_left numeric; v_part numeric;
 v_id uuid:=gen_random_uuid(); v_cash uuid; v_name text; v_rate numeric;
 v_syp numeric; v_existing public.supplier_payments; r record;
BEGIN
 IF auth.uid() IS NULL OR NOT COALESCE(public.is_admin(),false) THEN
  RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_debt_currency IS NULL OR p_tender_currency IS NULL OR
    p_debt_currency NOT IN ('USD','SYP') OR p_tender_currency NOT IN ('USD','SYP') THEN
  RAISE EXCEPTION 'عملة الدين أو الدفع غير صالحة'; END IF;
 IF p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount<=0 OR p_amount<>round(p_amount,2) THEN
  RAISE EXCEPTION 'أدخل مبلغاً موجباً بمنزلتين عشريتين كحد أقصى'; END IF;
 IF p_fx_rate IS NULL OR p_fx_rate::text IN ('NaN','Infinity','-Infinity') OR p_fx_rate<=0 THEN
  RAISE EXCEPTION 'سعر الصرف غير صالح'; END IF;
 IF p_request_id IS NULL OR p_payment_method IS NULL OR p_payment_method NOT IN ('cash','other') THEN
  RAISE EXCEPTION 'بيانات الدفعة غير مكتملة'; END IF;
 IF p_notes IS NULL OR p_notes !~ E'(^|\n)رقم وصل الاستلام: [^[:space:]]' THEN
  RAISE EXCEPTION 'رقم وصل الاستلام إجباري'; END IF;
 -- Serialize retries even when the supplier changes; then serialize supplier settlements.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_request_id::text,0));
 SELECT * INTO v_existing FROM public.supplier_payments WHERE payment_request_id=p_request_id;
 IF FOUND THEN
  IF v_existing.created_by IS DISTINCT FROM auth.uid() OR v_existing.supplier_id IS DISTINCT FROM p_supplier_id
   OR v_existing.tender_amount IS DISTINCT FROM p_amount OR v_existing.currency IS DISTINCT FROM p_debt_currency
   OR v_existing.tender_currency IS DISTINCT FROM p_tender_currency OR v_existing.tender_fx_rate IS DISTINCT FROM p_fx_rate
   OR v_existing.payment_method IS DISTINCT FROM p_payment_method OR v_existing.notes IS DISTINCT FROM p_notes
   OR (SELECT details->>'purchase_id' FROM public.audit_logs WHERE entity_id=v_existing.id
       AND action IN ('supplier_payment_currency_v2','supplier_payment_advance_v3') LIMIT 1) IS DISTINCT FROM p_purchase_id::text THEN
   RAISE EXCEPTION 'معرّف الدفعة مستخدم لعملية أخرى'; END IF;
  RETURN jsonb_build_object('payment_id',v_existing.id,'duplicate',true,'cashbox_entry_id',v_existing.cashbox_entry_id,'settled_amount',coalesce((SELECT sum(a.amount) FROM public.supplier_payment_allocations a WHERE a.payment_id=v_existing.id),0),'advance_amount',coalesce((SELECT l.amount FROM public.supplier_advance_lots l WHERE l.payment_id=v_existing.id),0));
 END IF;
 SELECT name INTO v_name FROM public.suppliers WHERE id=p_supplier_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
 -- The selected exchange rate is a snapshot; changing settings never revalues this payment.
 v_rate:=CASE WHEN p_debt_currency='USD' THEN p_fx_rate ELSE 1 END;
 v_settled:=CASE WHEN p_debt_currency=p_tender_currency THEN p_amount
  WHEN p_debt_currency='USD' THEN round(p_amount/p_fx_rate,6)
  ELSE round(p_amount*p_fx_rate,6) END;
 IF v_settled<=0 THEN RAISE EXCEPTION 'الدفعة أصغر من دقة التسوية'; END IF;
 v_syp:=CASE WHEN p_tender_currency='SYP' THEN p_amount ELSE round(p_amount*p_fx_rate,2) END;
 SELECT COALESCE(sum(due_amount),0) INTO v_before FROM public.purchases
  WHERE supplier_id=p_supplier_id AND currency=p_debt_currency;
 
 IF p_purchase_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.purchases
  WHERE id=p_purchase_id AND supplier_id=p_supplier_id AND currency=p_debt_currency ) THEN
  RAISE EXCEPTION 'الفاتورة لا تطابق المورد أو العملة أو المتبقي'; END IF;
 INSERT INTO public.supplier_payments(id,supplier_id,amount,currency,fx_rate,amount_syp,
  payment_method,notes,created_by,tender_currency,tender_amount,tender_fx_rate,payment_request_id)
 VALUES(v_id,p_supplier_id,v_settled,p_debt_currency,v_rate,
  CASE WHEN p_debt_currency='USD' THEN round(v_settled*v_rate,2) ELSE v_settled END,
  p_payment_method,p_notes,auth.uid(),p_tender_currency,p_amount,p_fx_rate,p_request_id);
 v_left:=v_settled;
 FOR r IN SELECT id,due_amount FROM public.purchases
  WHERE supplier_id=p_supplier_id AND currency=p_debt_currency AND due_amount>0
   AND (p_purchase_id IS NULL OR id=p_purchase_id)
  ORDER BY COALESCE(invoice_date,created_at::date),created_at,id FOR UPDATE
 LOOP
  EXIT WHEN v_left=0;
  v_part:=least(v_left,r.due_amount);
  INSERT INTO public.supplier_payment_allocations(payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
   VALUES(v_id,r.id,v_part,p_debt_currency,v_rate,
    CASE WHEN p_debt_currency='USD' THEN round(v_part*v_rate,2) ELSE v_part END);
  PERFORM public.admin_refresh_purchase_balance(r.id);
  v_left:=v_left-v_part;
 END LOOP;
 IF v_left>0 THEN INSERT INTO public.supplier_advance_lots(supplier_id,payment_id,origin_purchase_id,currency,amount,created_by) VALUES(p_supplier_id,v_id,p_purchase_id,p_debt_currency,v_left,auth.uid()); END IF;
 IF p_payment_method='cash' THEN
  INSERT INTO public.cashbox_entries(entry_type,amount,currency,fx_rate,amount_syp,description,
   purchase_id,supplier_payment_id,created_by)
  VALUES('purchase_payment',-p_amount,p_tender_currency,
   CASE WHEN p_tender_currency='USD' THEN p_fx_rate ELSE 1 END,-v_syp,
   'دفعة للمورد: '||v_name||' — دفع '||p_amount||' '||p_tender_currency||
    ' — تسديد '||(v_settled-v_left)||' '||p_debt_currency||' — رصيد مقدم '||v_left||' '||p_debt_currency||' — '||p_notes,
   p_purchase_id,v_id,auth.uid()) RETURNING id INTO v_cash;
  UPDATE public.supplier_payments SET cashbox_entry_id=v_cash WHERE id=v_id;
 END IF;
 SELECT COALESCE(sum(due_amount),0) INTO v_after FROM public.purchases
  WHERE supplier_id=p_supplier_id AND currency=p_debt_currency;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'supplier_payment_advance_v3','supplier_payment',v_id,
  jsonb_build_object('supplier_id',p_supplier_id,'purchase_id',p_purchase_id,'debt_currency',p_debt_currency,
   'settled_amount',v_settled-v_left,'advance_amount',v_left,'account_amount',v_settled,'tender_currency',p_tender_currency,'tender_amount',p_amount,
   'fx_rate',p_fx_rate,'actual_amount_syp',v_syp,'previous_debt',v_before,'new_debt',v_after,
   'cashbox_entry_id',v_cash,'request_id',p_request_id));
 RETURN jsonb_build_object('payment_id',v_id,'cashbox_entry_id',v_cash,'settled_amount',v_settled-v_left,'advance_amount',v_left,'account_amount',v_settled,
  'tender_amount',p_amount,'tender_currency',p_tender_currency,'previous_debt',v_before,'new_debt',v_after);
END $function$
;
REVOKE ALL ON FUNCTION public.admin_record_supplier_payment_advance_v3(uuid,numeric,text,text,numeric,uuid,uuid,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_record_supplier_payment_advance_v3(uuid,numeric,text,text,numeric,uuid,uuid,text,text) TO authenticated;



CREATE FUNCTION public.admin_create_purchase_with_advance_v3(
 p_currency text,p_supplier_id uuid,p_new_supplier jsonb,p_invoice_number text,p_invoice_date date,p_notes text,p_items jsonb,
 p_payment_amount numeric,p_payment_method text,p_payment_notes text,p_discount_type text,p_discount_value numeric,p_request_id uuid,p_expected_advance numeric DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_base jsonb;v_payment jsonb;v_id uuid;v_supplier uuid;v_used numeric;v_rate numeric;v_result jsonb;
 v_payload jsonb;v_hash text;v_old public.supplier_purchase_requests;v_credit jsonb;r record;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.is_admin(),false) THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_currency IS NULL OR p_currency NOT IN ('USD','SYP') OR p_request_id IS NULL THEN RAISE EXCEPTION 'بيانات فاتورة غير مكتملة'; END IF;
 IF p_payment_amount IS NULL OR p_payment_amount<0 OR p_payment_amount::text IN ('NaN','Infinity','-Infinity') OR p_payment_amount<>round(p_payment_amount,2) THEN RAISE EXCEPTION 'المبلغ المدفوع غير صالح'; END IF;
 IF p_payment_method IS NULL OR p_payment_method NOT IN ('cash','other') THEN RAISE EXCEPTION 'طريقة الدفع غير صالحة'; END IF;
 v_payload:=jsonb_build_object('currency',p_currency,'supplier_id',p_supplier_id,'new_supplier',p_new_supplier,'invoice_number',p_invoice_number,'invoice_date',p_invoice_date,'notes',p_notes,'items',p_items,'payment_amount',p_payment_amount,'payment_method',p_payment_method,'payment_notes',p_payment_notes,'discount_type',p_discount_type,'discount_value',p_discount_value,'expected_advance',p_expected_advance);
 v_hash:=md5(v_payload::text);
 PERFORM pg_advisory_xact_lock(hashtextextended('purchase-advance:'||p_request_id::text,0));
 SELECT * INTO v_old FROM public.supplier_purchase_requests WHERE request_id=p_request_id;
 IF FOUND THEN
  IF v_old.created_by IS DISTINCT FROM auth.uid() OR v_old.payload_hash<>v_hash THEN RAISE EXCEPTION 'معرّف حفظ الفاتورة مستخدم لطلب مختلف'; END IF;
  IF v_old.purchase_id IS NULL THEN RAISE EXCEPTION 'الفاتورة الخاصة بهذا الطلب حُذفت؛ افتح فاتورة جديدة'; END IF;
  RETURN v_old.result||jsonb_build_object('duplicate',true);
 END IF;
 IF p_supplier_id IS NOT NULL THEN
  PERFORM 1 FROM public.suppliers WHERE id=p_supplier_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'المورد غير موجود'; END IF;
  IF p_expected_advance IS NOT NULL AND p_expected_advance IS DISTINCT FROM (public.admin_supplier_advance_summary_v1(p_supplier_id,p_currency)->>'advance_credit')::numeric THEN RAISE EXCEPTION 'رصيد المورد تغيّر؛ حدّث بيانات الفاتورة قبل الحفظ'; END IF;
 END IF;
 IF p_currency='USD' THEN v_base:=public._ab_create_purchase_usd_core_v1(p_supplier_id,p_new_supplier,p_invoice_number,p_invoice_date,p_notes,p_items,0,p_payment_method,NULL,p_discount_type,p_discount_value);
 ELSE v_base:=public._ab_create_purchase_syp_core_v1(p_supplier_id,p_new_supplier,p_invoice_number,p_invoice_date,p_notes,p_items,0,p_payment_method,NULL,p_discount_type,p_discount_value); END IF;
 v_id:=(v_base->>'id')::uuid;
 SELECT supplier_id,fx_rate INTO v_supplier,v_rate FROM public.purchases WHERE id=v_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'تعذر تأكيد إنشاء الفاتورة'; END IF;
 v_used:=public.apply_supplier_advances_to_purchase_v1(v_id);
 IF p_payment_amount>0 THEN
  v_payment:=public.admin_record_supplier_payment_advance_v3(v_supplier,p_payment_amount,p_currency,p_currency,v_rate,v_id,v_id,p_payment_method,p_payment_notes);
 END IF;
 SELECT * INTO r FROM public.purchases WHERE id=v_id;
 v_credit:=public.admin_supplier_advance_summary_v1(v_supplier,p_currency);
 v_result:=v_base||jsonb_build_object('paid_amount',r.paid_amount,'due_amount',r.due_amount,'payment',v_payment,
  'applied_advance',v_used,'advance_created',coalesce((v_payment->>'advance_amount')::numeric,0),'advance_balance',(v_credit->>'advance_credit')::numeric);
 INSERT INTO public.supplier_purchase_requests(request_id,purchase_id,payload_hash,result,created_by) VALUES(p_request_id,v_id,v_hash,v_result,auth.uid());
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'purchase_with_supplier_advance','purchase',v_id,jsonb_build_object('supplier_id',v_supplier,'currency',p_currency,'applied_advance',v_used,'advance_created',coalesce((v_payment->>'advance_amount')::numeric,0),'actual_payment',p_payment_amount,'request_id',p_request_id));
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.admin_create_purchase_with_advance_v3(text,uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric,uuid,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_create_purchase_with_advance_v3(text,uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric,uuid,numeric) TO authenticated;


CREATE OR REPLACE FUNCTION public.admin_create_purchase_usd_v1(p_supplier_id uuid, p_new_supplier jsonb, p_invoice_number text, p_invoice_date date, p_notes text, p_items jsonb, p_payment_amount numeric, p_payment_method text, p_payment_notes text, p_discount_type text, p_discount_value numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$ BEGIN RETURN public.admin_create_purchase_with_advance_v3('USD',p_supplier_id,p_new_supplier,p_invoice_number,p_invoice_date,p_notes,p_items,p_payment_amount,p_payment_method,p_payment_notes,p_discount_type,p_discount_value,gen_random_uuid()); END; $function$;
CREATE OR REPLACE FUNCTION public.admin_create_purchase_syp_v1(p_supplier_id uuid, p_new_supplier jsonb, p_invoice_number text, p_invoice_date date, p_notes text, p_items jsonb, p_payment_amount numeric, p_payment_method text, p_payment_notes text, p_discount_type text, p_discount_value numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$ BEGIN RETURN public.admin_create_purchase_with_advance_v3('SYP',p_supplier_id,p_new_supplier,p_invoice_number,p_invoice_date,p_notes,p_items,p_payment_amount,p_payment_method,p_payment_notes,p_discount_type,p_discount_value,gen_random_uuid()); END; $function$;


DO $guard$
DECLARE r record;v_count bigint;v_hash text;
BEGIN
 FOR r IN SELECT * FROM ab_supplier_advance_guard LOOP
  EXECUTE format('SELECT count(*),md5(COALESCE(string_agg(h,''''
   ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(t)::text) h FROM public.%I t)x',r.table_name) INTO v_count,v_hash;
  IF v_count IS DISTINCT FROM r.row_count OR v_hash IS DISTINCT FROM r.fingerprint THEN RAISE EXCEPTION 'Data preservation guard failed for %; migration aborted',r.table_name; END IF;
 END LOOP;
END $guard$;

NOTIFY pgrst,'reload schema';

