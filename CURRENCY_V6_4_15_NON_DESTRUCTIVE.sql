-- Pharmacy Abdelhadi V6.4.15 — Dual currency / USD-SYP foundation
-- NON-DESTRUCTIVE migration. No DROP TABLE, TRUNCATE, DELETE, or mass price conversion.
-- Existing product prices are preserved and default to SYP.
BEGIN;

-- 1) Central FX settings + immutable-ish history
CREATE TABLE IF NOT EXISTS public.pharmacy_currency_settings(
  id smallint PRIMARY KEY DEFAULT 1 CHECK(id=1),
  usd_to_syp numeric NOT NULL CHECK(usd_to_syp>0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id)
);
INSERT INTO public.pharmacy_currency_settings(id,usd_to_syp)
VALUES(1,15000)
ON CONFLICT(id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.pharmacy_currency_rate_history(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usd_to_syp numeric NOT NULL CHECK(usd_to_syp>0),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid REFERENCES auth.users(id)
);

ALTER TABLE public.pharmacy_currency_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pharmacy_currency_rate_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin currency settings" ON public.pharmacy_currency_settings;
DROP POLICY IF EXISTS "admin currency history" ON public.pharmacy_currency_rate_history;
CREATE POLICY "admin currency settings" ON public.pharmacy_currency_settings FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());
CREATE POLICY "admin currency history" ON public.pharmacy_currency_rate_history FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());

CREATE OR REPLACE FUNCTION public.admin_get_currency_settings()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
  SELECT jsonb_build_object(
    'usd_to_syp',s.usd_to_syp,
    'updated_at',s.updated_at,
    'history',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',h.id,'usd_to_syp',h.usd_to_syp,'changed_at',h.changed_at) ORDER BY h.changed_at DESC) FROM public.pharmacy_currency_rate_history h),'[]'::jsonb)
  ) FROM public.pharmacy_currency_settings s WHERE public.is_admin() AND s.id=1;
$$;
REVOKE ALL ON FUNCTION public.admin_get_currency_settings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_currency_settings() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_usd_rate(p_usd_to_syp numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_old numeric; v_new numeric:=ROUND(p_usd_to_syp,4);
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF v_new IS NULL OR v_new<=0 THEN RAISE EXCEPTION 'سعر الدولار يجب أن يكون أكبر من صفر'; END IF;
 SELECT usd_to_syp INTO v_old FROM public.pharmacy_currency_settings WHERE id=1 FOR UPDATE;
 UPDATE public.pharmacy_currency_settings SET usd_to_syp=v_new,updated_at=now(),updated_by=auth.uid() WHERE id=1;
 IF v_old IS DISTINCT FROM v_new THEN
   INSERT INTO public.pharmacy_currency_rate_history(usd_to_syp,changed_by) VALUES(v_new,auth.uid());
 END IF;
 INSERT INTO public.audit_logs(user_id,action,entity_type,details) VALUES(auth.uid(),'currency_rate_update','currency',jsonb_build_object('old_rate',v_old,'new_rate',v_new));
 RETURN jsonb_build_object('usd_to_syp',v_new,'old_rate',v_old);
END; $$;
REVOKE ALL ON FUNCTION public.admin_set_usd_rate(numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_usd_rate(numeric) TO authenticated;

-- 2) Currency metadata. Existing rows remain numerically unchanged.
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS sale_currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS purchase_price_currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS purchase_price_syp numeric;
UPDATE public.products SET sale_currency='SYP' WHERE sale_currency IS NULL OR sale_currency='';
UPDATE public.products SET purchase_price_currency='SYP' WHERE purchase_price_currency IS NULL OR purchase_price_currency='';
UPDATE public.products SET purchase_price_syp=purchase_price WHERE purchase_price_syp IS NULL;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_sale_currency_check;
ALTER TABLE public.products ADD CONSTRAINT products_sale_currency_check CHECK(sale_currency IN ('SYP','USD'));
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_purchase_price_currency_check;
ALTER TABLE public.products ADD CONSTRAINT products_purchase_price_currency_check CHECK(purchase_price_currency IN ('SYP','USD'));

ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS subtotal_syp numeric;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS discount_amount_syp numeric;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS total_syp numeric;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS subtotal_original numeric;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS discount_amount_original numeric;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS total_original numeric;
ALTER TABLE public.purchases DROP CONSTRAINT IF EXISTS purchases_currency_check;
ALTER TABLE public.purchases ADD CONSTRAINT purchases_currency_check CHECK(currency IN ('SYP','USD'));
ALTER TABLE public.purchases DROP CONSTRAINT IF EXISTS purchases_fx_rate_positive_check;
ALTER TABLE public.purchases ADD CONSTRAINT purchases_fx_rate_positive_check CHECK(fx_rate>0);
UPDATE public.purchases SET currency='SYP',fx_rate=1,subtotal_syp=COALESCE(subtotal,total),discount_amount_syp=COALESCE(discount_amount,0),total_syp=COALESCE(total,0),subtotal_original=COALESCE(subtotal,total),discount_amount_original=COALESCE(discount_amount,0),total_original=COALESCE(total,0) WHERE currency IS NULL OR currency='' OR fx_rate IS NULL OR subtotal_syp IS NULL OR total_syp IS NULL;

ALTER TABLE public.purchase_items ADD COLUMN IF NOT EXISTS purchase_price_currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.purchase_items ADD COLUMN IF NOT EXISTS purchase_price_syp numeric;
ALTER TABLE public.purchase_items ADD COLUMN IF NOT EXISTS sale_price_currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.purchase_items ADD COLUMN IF NOT EXISTS sale_price_syp numeric;
ALTER TABLE public.purchase_items DROP CONSTRAINT IF EXISTS purchase_items_purchase_currency_check;
ALTER TABLE public.purchase_items ADD CONSTRAINT purchase_items_purchase_currency_check CHECK(purchase_price_currency IN ('SYP','USD'));
ALTER TABLE public.purchase_items DROP CONSTRAINT IF EXISTS purchase_items_sale_currency_check;
ALTER TABLE public.purchase_items ADD CONSTRAINT purchase_items_sale_currency_check CHECK(sale_price_currency IN ('SYP','USD'));
UPDATE public.purchase_items SET purchase_price_syp=purchase_price, sale_price_syp=sale_price WHERE purchase_price_syp IS NULL OR sale_price_syp IS NULL;

ALTER TABLE public.batches ADD COLUMN IF NOT EXISTS purchase_price_currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.batches ADD COLUMN IF NOT EXISTS purchase_price_original numeric;
ALTER TABLE public.batches ADD COLUMN IF NOT EXISTS purchase_fx_rate numeric NOT NULL DEFAULT 1;
ALTER TABLE public.batches DROP CONSTRAINT IF EXISTS batches_purchase_currency_check;
ALTER TABLE public.batches ADD CONSTRAINT batches_purchase_currency_check CHECK(purchase_price_currency IN ('SYP','USD'));
ALTER TABLE public.batches DROP CONSTRAINT IF EXISTS batches_purchase_fx_rate_check;
ALTER TABLE public.batches ADD CONSTRAINT batches_purchase_fx_rate_check CHECK(purchase_fx_rate>0);
UPDATE public.batches SET purchase_price_original=purchase_price WHERE purchase_price_original IS NULL;

ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1;
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS subtotal_syp numeric;
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS discount_syp numeric;
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS total_syp numeric;
ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_currency_check;
ALTER TABLE public.sales ADD CONSTRAINT sales_currency_check CHECK(currency IN ('SYP','USD'));
ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_fx_rate_positive_check;
ALTER TABLE public.sales ADD CONSTRAINT sales_fx_rate_positive_check CHECK(fx_rate>0);
UPDATE public.sales SET currency='SYP',fx_rate=1,subtotal_syp=COALESCE(subtotal,total),discount_syp=COALESCE(discount,0),total_syp=COALESCE(total,0) WHERE currency IS NULL OR currency='' OR fx_rate IS NULL OR subtotal_syp IS NULL OR total_syp IS NULL;

ALTER TABLE public.sale_items ADD COLUMN IF NOT EXISTS original_unit_price numeric;
ALTER TABLE public.sale_items ADD COLUMN IF NOT EXISTS original_currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.sale_items ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1;
ALTER TABLE public.sale_items ADD COLUMN IF NOT EXISTS unit_price_syp numeric;
ALTER TABLE public.sale_items DROP CONSTRAINT IF EXISTS sale_items_currency_check;
ALTER TABLE public.sale_items ADD CONSTRAINT sale_items_currency_check CHECK(original_currency IN ('SYP','USD'));
ALTER TABLE public.sale_items DROP CONSTRAINT IF EXISTS sale_items_fx_rate_positive_check;
ALTER TABLE public.sale_items ADD CONSTRAINT sale_items_fx_rate_positive_check CHECK(fx_rate>0);
UPDATE public.sale_items SET original_unit_price=unit_price,unit_price_syp=unit_price WHERE original_unit_price IS NULL OR unit_price_syp IS NULL;

ALTER TABLE public.cashbox_entries ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.cashbox_entries ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1;
ALTER TABLE public.cashbox_entries ADD COLUMN IF NOT EXISTS amount_syp numeric;
ALTER TABLE public.cashbox_entries DROP CONSTRAINT IF EXISTS cashbox_currency_check;
ALTER TABLE public.cashbox_entries ADD CONSTRAINT cashbox_currency_check CHECK(currency IN ('SYP','USD'));
ALTER TABLE public.cashbox_entries DROP CONSTRAINT IF EXISTS cashbox_fx_rate_positive_check;
ALTER TABLE public.cashbox_entries ADD CONSTRAINT cashbox_fx_rate_positive_check CHECK(fx_rate>0);
UPDATE public.cashbox_entries SET amount_syp=amount WHERE amount_syp IS NULL;

ALTER TABLE public.debtor_transactions ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.debtor_transactions ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1;
ALTER TABLE public.debtor_transactions ADD COLUMN IF NOT EXISTS amount_syp numeric;
ALTER TABLE public.debtor_transactions DROP CONSTRAINT IF EXISTS debtor_tx_currency_check;
ALTER TABLE public.debtor_transactions ADD CONSTRAINT debtor_tx_currency_check CHECK(currency IN ('SYP','USD'));
ALTER TABLE public.debtor_transactions DROP CONSTRAINT IF EXISTS debtor_tx_fx_rate_positive_check;
ALTER TABLE public.debtor_transactions ADD CONSTRAINT debtor_tx_fx_rate_positive_check CHECK(fx_rate>0);
UPDATE public.debtor_transactions SET amount_syp=amount WHERE amount_syp IS NULL;

ALTER TABLE public.supplier_payments ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.supplier_payments ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1;
ALTER TABLE public.supplier_payments ADD COLUMN IF NOT EXISTS amount_syp numeric;
ALTER TABLE public.supplier_payments DROP CONSTRAINT IF EXISTS supplier_payments_currency_check;
ALTER TABLE public.supplier_payments ADD CONSTRAINT supplier_payments_currency_check CHECK(currency IN ('SYP','USD'));
ALTER TABLE public.supplier_payments DROP CONSTRAINT IF EXISTS supplier_payments_fx_rate_positive_check;
ALTER TABLE public.supplier_payments ADD CONSTRAINT supplier_payments_fx_rate_positive_check CHECK(fx_rate>0);
UPDATE public.supplier_payments SET amount_syp=amount WHERE amount_syp IS NULL;

ALTER TABLE public.returns ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP';
ALTER TABLE public.returns ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1;
ALTER TABLE public.returns ADD COLUMN IF NOT EXISTS amount_syp numeric;
ALTER TABLE public.returns DROP CONSTRAINT IF EXISTS returns_currency_check;
ALTER TABLE public.returns ADD CONSTRAINT returns_currency_check CHECK(currency IN ('SYP','USD'));
ALTER TABLE public.returns DROP CONSTRAINT IF EXISTS returns_fx_rate_positive_check;
ALTER TABLE public.returns ADD CONSTRAINT returns_fx_rate_positive_check CHECK(fx_rate>0);
UPDATE public.returns SET amount_syp=amount WHERE amount_syp IS NULL;

-- 3) Safe product save: adds sale_currency while retaining old API.
CREATE OR REPLACE FUNCTION public.admin_save_pharmacy_product(p_product_id uuid DEFAULT NULL,p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS public.products LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v public.products; v_currency text:=COALESCE(NULLIF(upper(trim(p_payload->>'sale_currency')),''),'SYP'); v_purchase_currency text:=COALESCE(NULLIF(upper(trim(p_payload->>'purchase_price_currency')),''),'SYP');
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'غير مصرح'; END IF;
 IF NULLIF(trim(COALESCE(p_payload->>'name','')),'') IS NULL THEN RAISE EXCEPTION 'اسم المنتج مطلوب'; END IF;
 IF v_currency NOT IN ('SYP','USD') THEN RAISE EXCEPTION 'عملة سعر المبيع غير صالحة'; END IF;
 IF v_purchase_currency NOT IN ('SYP','USD') THEN RAISE EXCEPTION 'عملة سعر الشراء غير صالحة'; END IF;
 IF p_product_id IS NULL THEN
  INSERT INTO public.products(name,barcode,active_ingredient,strength,dosage_form,manufacturer,category,unit,reorder_level,purchase_price,sale_price,parts_per_unit,customer_visible,active,sale_currency,purchase_price_currency,purchase_price_syp)
  VALUES(NULLIF(trim(p_payload->>'name'),''),NULLIF(trim(p_payload->>'barcode'),''),NULLIF(trim(p_payload->>'active_ingredient'),''),NULLIF(trim(p_payload->>'strength'),''),NULLIF(trim(p_payload->>'dosage_form'),''),NULLIF(trim(p_payload->>'manufacturer'),''),NULLIF(trim(p_payload->>'category'),''),COALESCE(NULLIF(trim(p_payload->>'unit'),''),'piece'),GREATEST(0,COALESCE(NULLIF(p_payload->>'reorder_level','')::numeric,1)),GREATEST(0,COALESCE(NULLIF(p_payload->>'purchase_price','')::numeric,0)),GREATEST(0,COALESCE(NULLIF(p_payload->>'sale_price','')::numeric,0)),GREATEST(1,COALESCE(NULLIF(p_payload->>'parts_per_unit','')::numeric,1)),COALESCE((p_payload->>'customer_visible')::boolean,true),true,v_currency,v_purchase_currency,GREATEST(0,COALESCE(NULLIF(p_payload->>'purchase_price_syp','')::numeric,NULLIF(p_payload->>'purchase_price','')::numeric,0))) RETURNING * INTO v;
 ELSE
  UPDATE public.products SET name=NULLIF(trim(p_payload->>'name'),''),barcode=NULLIF(trim(p_payload->>'barcode'),''),active_ingredient=NULLIF(trim(p_payload->>'active_ingredient'),''),strength=NULLIF(trim(p_payload->>'strength'),''),dosage_form=NULLIF(trim(p_payload->>'dosage_form'),''),manufacturer=NULLIF(trim(p_payload->>'manufacturer'),''),category=NULLIF(trim(p_payload->>'category'),''),unit=COALESCE(NULLIF(trim(p_payload->>'unit'),''),'piece'),reorder_level=GREATEST(0,COALESCE(NULLIF(p_payload->>'reorder_level','')::numeric,0)),purchase_price=GREATEST(0,COALESCE(NULLIF(p_payload->>'purchase_price','')::numeric,0)),sale_price=GREATEST(0,COALESCE(NULLIF(p_payload->>'sale_price','')::numeric,0)),parts_per_unit=GREATEST(1,COALESCE(NULLIF(p_payload->>'parts_per_unit','')::numeric,1)),customer_visible=COALESCE((p_payload->>'customer_visible')::boolean,true),sale_currency=v_currency,purchase_price_currency=v_purchase_currency,purchase_price_syp=GREATEST(0,COALESCE(NULLIF(p_payload->>'purchase_price_syp','')::numeric,NULLIF(p_payload->>'purchase_price','')::numeric,0)),updated_at=now() WHERE id=p_product_id RETURNING * INTO v;
  IF NOT FOUND THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;
 END IF; RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.admin_save_pharmacy_product(uuid,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_save_pharmacy_product(uuid,jsonb) TO authenticated;

-- 4a) Product catalog keeps the same RPC signature but exposes currency metadata.
DROP FUNCTION IF EXISTS public.admin_product_catalog(text,text,text,text,boolean,integer,integer,text,boolean);
CREATE OR REPLACE FUNCTION public.admin_product_catalog(p_query text DEFAULT NULL,p_manufacturer text DEFAULT NULL,p_dosage_form text DEFAULT NULL,p_category text DEFAULT NULL,p_customer_visible boolean DEFAULT NULL,p_limit integer DEFAULT 100,p_offset integer DEFAULT 0,p_sort text DEFAULT 'name',p_desc boolean DEFAULT false)
RETURNS TABLE(id uuid,name text,barcode text,active_ingredient text,strength text,dosage_form text,manufacturer text,category text,unit text,reorder_level numeric,purchase_price numeric,sale_price numeric,parts_per_unit numeric,customer_visible boolean,active boolean,sale_currency text,purchase_price_currency text,total_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 WITH filtered AS (SELECT p.* FROM public.products p WHERE public.is_admin() AND COALESCE(p.active,true)=true AND (p_customer_visible IS NULL OR p.customer_visible=p_customer_visible) AND (NULLIF(trim(COALESCE(p_query,'')),'') IS NULL OR p.name ILIKE '%'||trim(p_query)||'%' OR COALESCE(p.barcode,'') ILIKE '%'||trim(p_query)||'%' OR COALESCE(p.active_ingredient,'') ILIKE '%'||trim(p_query)||'%' OR COALESCE(p.strength,'') ILIKE '%'||trim(p_query)||'%' OR COALESCE(p.manufacturer,'') ILIKE '%'||trim(p_query)||'%' OR COALESCE(p.dosage_form,'') ILIKE '%'||trim(p_query)||'%') AND (NULLIF(trim(COALESCE(p_manufacturer,'')),'') IS NULL OR COALESCE(p.manufacturer,'')=trim(p_manufacturer)) AND (NULLIF(trim(COALESCE(p_dosage_form,'')),'') IS NULL OR COALESCE(p.dosage_form,'')=trim(p_dosage_form)) AND (NULLIF(trim(COALESCE(p_category,'')),'') IS NULL OR COALESCE(p.category,'')=trim(p_category)))
 SELECT f.id,f.name,f.barcode,f.active_ingredient,f.strength,f.dosage_form,f.manufacturer,f.category,f.unit,f.reorder_level,f.purchase_price,f.sale_price,f.parts_per_unit,f.customer_visible,f.active,f.sale_currency,f.purchase_price_currency,COUNT(*) OVER() FROM filtered f
 ORDER BY CASE WHEN p_sort='name' AND NOT p_desc THEN lower(COALESCE(f.name,'')) END ASC,CASE WHEN p_sort='name' AND p_desc THEN lower(COALESCE(f.name,'')) END DESC,CASE WHEN p_sort='manufacturer' AND NOT p_desc THEN lower(COALESCE(f.manufacturer,'')) END ASC,CASE WHEN p_sort='manufacturer' AND p_desc THEN lower(COALESCE(f.manufacturer,'')) END DESC,CASE WHEN p_sort='dosage_form' AND NOT p_desc THEN lower(COALESCE(f.dosage_form,'')) END ASC,CASE WHEN p_sort='dosage_form' AND p_desc THEN lower(COALESCE(f.dosage_form,'')) END DESC,CASE WHEN p_sort='active_ingredient' AND NOT p_desc THEN lower(COALESCE(f.active_ingredient,'')) END ASC,CASE WHEN p_sort='active_ingredient' AND p_desc THEN lower(COALESCE(f.active_ingredient,'')) END DESC,CASE WHEN p_sort='category' AND NOT p_desc THEN lower(COALESCE(f.category,'')) END ASC,CASE WHEN p_sort='category' AND p_desc THEN lower(COALESCE(f.category,'')) END DESC,CASE WHEN p_sort='sale_price' AND NOT p_desc THEN f.sale_price END ASC,CASE WHEN p_sort='sale_price' AND p_desc THEN f.sale_price END DESC,CASE WHEN p_sort='purchase_price' AND NOT p_desc THEN f.purchase_price END ASC,CASE WHEN p_sort='purchase_price' AND p_desc THEN f.purchase_price END DESC,lower(COALESCE(f.name,'')) ASC OFFSET GREATEST(COALESCE(p_offset,0),0) LIMIT GREATEST(1,LEAST(COALESCE(p_limit,100),500));
$$;
REVOKE ALL ON FUNCTION public.admin_product_catalog(text,text,text,text,boolean,integer,integer,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_product_catalog(text,text,text,text,boolean,integer,integer,text,boolean) TO authenticated;

-- 4) POS search returns dynamic current SYP price without rewriting product.sale_price.
DROP FUNCTION IF EXISTS public.admin_search_pos_products(text,integer);
CREATE OR REPLACE FUNCTION public.admin_search_pos_products(p_query text,p_limit integer DEFAULT 30)
RETURNS TABLE(id uuid,name text,barcode text,active_ingredient text,strength text,dosage_form text,unit text,sale_price numeric,purchase_price numeric,parts_per_unit numeric,stock numeric,expiry_date date,sale_currency text,sale_price_syp numeric,usd_to_syp numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT p.id,p.name,p.barcode,p.active_ingredient,p.strength,p.dosage_form,p.unit,p.sale_price,p.purchase_price,p.parts_per_unit,
 COALESCE(SUM(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=CURRENT_DATE) THEN b.quantity ELSE 0 END),0),
 MIN(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=CURRENT_DATE) THEN b.expiry_date END),
 p.sale_currency,CASE WHEN p.sale_currency='USD' THEN p.sale_price*s.usd_to_syp ELSE p.sale_price END,s.usd_to_syp
 FROM public.products p CROSS JOIN public.pharmacy_currency_settings s LEFT JOIN public.batches b ON b.product_id=p.id
 WHERE public.is_admin() AND (COALESCE(p.barcode,'') ILIKE p_query||'%' OR COALESCE(p.name,'') ILIKE '%'||p_query||'%' OR COALESCE(p.active_ingredient,'') ILIKE '%'||p_query||'%')
 GROUP BY p.id,s.usd_to_syp ORDER BY CASE WHEN p.barcode=p_query THEN 0 WHEN lower(COALESCE(p.name,''))=lower(p_query) THEN 1 WHEN lower(COALESCE(p.name,'')) LIKE lower(p_query)||'%' THEN 2 WHEN COALESCE(p.active_ingredient,'') ILIKE '%'||p_query||'%' THEN 3 ELSE 4 END,MIN(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=CURRENT_DATE) THEN b.expiry_date END) NULLS LAST,p.name LIMIT GREATEST(1,LEAST(COALESCE(p_limit,30),100));
$$;
REVOKE ALL ON FUNCTION public.admin_search_pos_products(text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_pos_products(text,integer) TO authenticated;

-- 5) Purchase with currency snapshot. Existing purchase RPC remains intact.
CREATE OR REPLACE FUNCTION public.admin_create_purchase_with_payment_discount_currency(
 p_supplier_id uuid DEFAULT NULL,p_new_supplier jsonb DEFAULT NULL,p_invoice_number text DEFAULT NULL,p_invoice_date date DEFAULT CURRENT_DATE,p_notes text DEFAULT NULL,p_items jsonb DEFAULT '[]'::jsonb,p_payment_amount numeric DEFAULT 0,p_payment_method text DEFAULT 'cash',p_payment_notes text DEFAULT NULL,p_discount_type text DEFAULT 'none',p_discount_value numeric DEFAULT 0,p_currency text DEFAULT 'SYP',p_fx_rate numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_rate numeric; v_purchase jsonb; v_id uuid; v_sub numeric; v_disc numeric; v_total numeric; v_paid numeric:=GREATEST(COALESCE(p_payment_amount,0),0); v_items jsonb; v_item jsonb; v_pc text;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF upper(p_currency) NOT IN ('SYP','USD') THEN RAISE EXCEPTION 'عملة الفاتورة غير صالحة'; END IF;
 SELECT CASE WHEN upper(p_currency)='USD' THEN COALESCE(p_fx_rate,s.usd_to_syp) ELSE 1 END INTO v_rate FROM public.pharmacy_currency_settings s WHERE s.id=1;
 IF v_rate IS NULL OR v_rate<=0 THEN RAISE EXCEPTION 'سعر الصرف غير صالح'; END IF;
 -- Existing engine records stock and supplier relations. For USD, its numeric purchase/batch amounts are recorded as SYP equivalents below.
 v_items:='[]'::jsonb;
 FOR v_item IN SELECT value FROM jsonb_array_elements(COALESCE(p_items,'[]'::jsonb)) LOOP
   v_items:=v_items||jsonb_build_array(jsonb_build_object('product_id',v_item->>'product_id','quantity',(v_item->>'quantity')::numeric,'bonus_quantity',COALESCE((v_item->>'bonus_quantity')::numeric,0),'purchase_price',CASE WHEN upper(p_currency)='USD' THEN (v_item->>'purchase_price')::numeric*v_rate ELSE (v_item->>'purchase_price')::numeric END,'sale_price',(v_item->>'sale_price')::numeric,'expiry_date',v_item->>'expiry_date'));
 END LOOP;
 -- JSONB array construction above produces nested arrays; flatten them safely.
 SELECT COALESCE(jsonb_agg(value),'[]'::jsonb) INTO v_items FROM jsonb_array_elements(v_items) a CROSS JOIN LATERAL jsonb_array_elements(a.value) b(value);
 v_purchase:=public.admin_create_purchase(p_supplier_id,p_invoice_number,COALESCE(p_invoice_date,CURRENT_DATE),p_notes,v_items);
 v_id:=(v_purchase->>'id')::uuid; v_sub:=ROUND(COALESCE((v_purchase->>'total')::numeric,0),2);
 IF COALESCE(p_discount_type,'none')='percent' THEN v_disc:=ROUND(v_sub*GREATEST(COALESCE(p_discount_value,0),0)/100,2); ELSIF COALESCE(p_discount_type,'none')='amount' THEN v_disc:=ROUND(GREATEST(COALESCE(p_discount_value,0),0)*CASE WHEN upper(p_currency)='USD' THEN v_rate ELSE 1 END,2); ELSE v_disc:=0; END IF;
 v_disc:=LEAST(v_disc,v_sub); v_total:=ROUND(v_sub-v_disc,2);
 UPDATE public.purchases SET currency=upper(p_currency),fx_rate=v_rate,subtotal_syp=v_sub,discount_amount_syp=v_disc,total_syp=v_total,subtotal=v_sub,discount_amount=v_disc,total=v_total,subtotal_original=CASE WHEN upper(p_currency)='USD' THEN ROUND(v_sub/v_rate,2) ELSE v_sub END,discount_amount_original=CASE WHEN upper(p_currency)='USD' THEN ROUND(v_disc/v_rate,2) ELSE v_disc END,total_original=CASE WHEN upper(p_currency)='USD' THEN ROUND(v_total/v_rate,2) ELSE v_total END,discount_type=COALESCE(p_discount_type,'none'),discount_value=GREATEST(COALESCE(p_discount_value,0),0) WHERE id=v_id;
 -- historical metadata for each purchase item and its batch
 UPDATE public.purchase_items pi SET purchase_price_currency=upper(p_currency),purchase_price_syp=CASE WHEN upper(p_currency)='USD' THEN purchase_price ELSE purchase_price END,sale_price_currency=COALESCE((SELECT pr.sale_currency FROM public.products pr WHERE pr.id=pi.product_id),'SYP'),sale_price_syp=pi.sale_price FROM public.purchases p WHERE pi.purchase_id=v_id AND p.id=v_id;
 UPDATE public.batches b SET purchase_price_currency=upper(p_currency),purchase_price_original=CASE WHEN upper(p_currency)='USD' THEN ROUND(b.purchase_price/v_rate,6) ELSE b.purchase_price END,purchase_fx_rate=v_rate WHERE b.purchase_id=v_id;
 IF v_paid>0 THEN
   IF upper(p_currency)='USD' THEN PERFORM public.admin_record_supplier_payment(p_supplier_id,ROUND(v_paid*v_rate,2),v_id,p_payment_method,p_payment_notes); ELSE PERFORM public.admin_record_supplier_payment(p_supplier_id,v_paid,v_id,p_payment_method,p_payment_notes); END IF;
 ELSE PERFORM public.admin_refresh_purchase_balance(v_id); END IF;
 RETURN jsonb_build_object('id',v_id,'public_code',v_purchase->>'public_code','currency',upper(p_currency),'fx_rate',v_rate,'subtotal_original',CASE WHEN upper(p_currency)='USD' THEN ROUND(v_sub/v_rate,2) ELSE v_sub END,'subtotal_syp',v_sub,'discount_amount_original',GREATEST(COALESCE(p_discount_value,0),0),'discount_amount_syp',v_disc,'total_original',CASE WHEN upper(p_currency)='USD' THEN ROUND(v_total/v_rate,2) ELSE v_total END,'total_syp',v_total,'paid_original',CASE WHEN upper(p_currency)='USD' THEN ROUND(v_paid,2) ELSE v_paid END,'due_original',CASE WHEN upper(p_currency)='USD' THEN ROUND(GREATEST(v_total-v_paid*v_rate,0)/v_rate,2) ELSE GREATEST(v_total-v_paid,0) END);
END; $$;
REVOKE ALL ON FUNCTION public.admin_create_purchase_with_payment_discount_currency(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric,text,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_purchase_with_payment_discount_currency(uuid,jsonb,text,date,text,jsonb,numeric,text,text,text,numeric,text,numeric) TO authenticated;

-- 6) Currency-aware sale. Old complete_sale_accounting remains available.
CREATE OR REPLACE FUNCTION public.complete_sale_accounting_currency(p_items jsonb,p_discount numeric DEFAULT 0,p_payment_method text DEFAULT 'cash',p_debtor_id uuid DEFAULT NULL,p_notes text DEFAULT NULL,p_currency text DEFAULT 'SYP',p_fx_rate numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE r numeric; it jsonb; conv jsonb:='[]'::jsonb; price numeric; item_currency text; rate numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT CASE WHEN upper(p_currency)='USD' THEN COALESCE(p_fx_rate,s.usd_to_syp) ELSE 1 END INTO r FROM public.pharmacy_currency_settings s WHERE s.id=1;
 IF r IS NULL OR r<=0 THEN RAISE EXCEPTION 'سعر الصرف غير صالح'; END IF;
 FOR it IN SELECT value FROM jsonb_array_elements(COALESCE(p_items,'[]'::jsonb)) LOOP
   item_currency:=COALESCE(NULLIF(upper(it->>'currency'),''),upper(p_currency));
   IF item_currency NOT IN ('SYP','USD') THEN RAISE EXCEPTION 'عملة سعر البيع غير صالحة'; END IF;
   rate:=CASE WHEN item_currency='USD' THEN r ELSE 1 END;
   price:=GREATEST(COALESCE((it->>'unit_price')::numeric,0),0);
   conv:=conv||jsonb_build_object('product_id',it->>'product_id','quantity',(it->>'quantity')::numeric,'unit_price',ROUND(price*rate,2),'base_unit_price',ROUND(COALESCE((it->>'base_unit_price')::numeric,price)*rate,2),'original_unit_price',price,'currency',item_currency,'fx_rate',rate);
 END LOOP;
 RETURN public.complete_sale_accounting_currency_impl(conv,p_discount,p_payment_method,p_debtor_id,p_notes,upper(p_currency),r,p_items);
END; $$;

CREATE OR REPLACE FUNCTION public.complete_sale_accounting_currency_impl(p_items_syp jsonb,p_discount numeric,p_payment_method text,p_debtor_id uuid,p_notes text,p_currency text,p_rate numeric,p_original_items jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v jsonb; sid uuid; orig jsonb; si record;
BEGIN
 v:=public.complete_sale_accounting(p_items_syp,p_discount,p_payment_method,p_debtor_id,p_notes); sid:=(v->>'sale_id')::uuid;
 UPDATE public.sales SET currency=p_currency,fx_rate=p_rate,subtotal_syp=subtotal,discount_syp=discount,total_syp=total WHERE id=sid;
 FOR si IN SELECT * FROM jsonb_array_elements(COALESCE(p_original_items,'[]'::jsonb)) LOOP
   UPDATE public.sale_items SET original_unit_price=COALESCE((si.value->>'unit_price')::numeric,unit_price),original_currency=COALESCE(NULLIF(upper(si.value->>'currency'),''),p_currency),fx_rate=CASE WHEN COALESCE(NULLIF(upper(si.value->>'currency'),''),p_currency)='USD' THEN p_rate ELSE 1 END,unit_price_syp=unit_price WHERE sale_id=sid AND product_id=(si.value->>'product_id')::uuid;
 END LOOP;
 IF p_currency='USD' THEN
   -- The accounting sale was recorded in SYP, so the cash/debt snapshot is already historical and exact.
   NULL;
 END IF;
 RETURN v||jsonb_build_object('currency',p_currency,'fx_rate',p_rate,'total_syp',v->>'total');
END; $$;
REVOKE ALL ON FUNCTION public.complete_sale_accounting_currency(jsonb,numeric,text,uuid,text,text,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_sale_accounting_currency(jsonb,numeric,text,uuid,text,text,numeric) TO authenticated;
REVOKE ALL ON FUNCTION public.complete_sale_accounting_currency_impl(jsonb,numeric,text,uuid,text,text,numeric,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_sale_accounting_currency_impl(jsonb,numeric,text,uuid,text,text,numeric,jsonb) TO authenticated;

-- 7) Separate cashbox balances + historical SYP equivalent. Existing amount column stays untouched.
CREATE OR REPLACE FUNCTION public.admin_cashbox_currency_summary()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT jsonb_build_object('syp_balance',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE currency='SYP'),0),'usd_balance',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE currency='USD'),0),'usd_to_syp',(SELECT usd_to_syp FROM public.pharmacy_currency_settings WHERE id=1));
$$;
REVOKE ALL ON FUNCTION public.admin_cashbox_currency_summary() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cashbox_currency_summary() TO authenticated;

-- 8) Audit-friendly helper for current product SYP display.
CREATE OR REPLACE FUNCTION public.admin_product_current_price_syp(p_product_id uuid)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT CASE WHEN p.sale_currency='USD' THEN p.sale_price*s.usd_to_syp ELSE p.sale_price END FROM public.products p CROSS JOIN public.pharmacy_currency_settings s WHERE public.is_admin() AND p.id=p_product_id;
$$;
REVOKE ALL ON FUNCTION public.admin_product_current_price_syp(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_product_current_price_syp(uuid) TO authenticated;

CREATE INDEX IF NOT EXISTS idx_products_sale_currency ON public.products(sale_currency);
CREATE INDEX IF NOT EXISTS idx_currency_history_changed_at ON public.pharmacy_currency_rate_history(changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_purchases_currency_created ON public.purchases(currency,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_currency_created ON public.sales(currency,created_at DESC);

COMMIT;
