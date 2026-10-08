-- Pharmacy Abdelhadi V6.4.15
-- NON-DESTRUCTIVE USD/SYP pricing + POS accounting compatibility repair.
-- IMPORTANT: This migration does NOT delete, truncate, rename, or bulk-convert existing product prices.
-- Existing products are explicitly treated as SYP (sale_currency='SYP'), preserving their numeric sale_price exactly.

BEGIN;

-- 1) Central exchange-rate storage + audit history.
CREATE TABLE IF NOT EXISTS public.pharmacy_currency_settings (
  id integer PRIMARY KEY CHECK (id = 1),
  usd_to_syp numeric NOT NULL CHECK (usd_to_syp > 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id)
);

CREATE TABLE IF NOT EXISTS public.pharmacy_currency_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usd_to_syp numeric NOT NULL CHECK (usd_to_syp > 0),
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by uuid REFERENCES auth.users(id),
  note text
);

INSERT INTO public.pharmacy_currency_settings(id, usd_to_syp)
VALUES (1, 1)
ON CONFLICT (id) DO NOTHING;

-- 2) Product sale currency. Existing values stay numerically unchanged.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS sale_currency text NOT NULL DEFAULT 'SYP';

UPDATE public.products
SET sale_currency = 'SYP'
WHERE sale_currency IS NULL OR sale_currency NOT IN ('SYP','USD');

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_sale_currency_check;
ALTER TABLE public.products
  ADD CONSTRAINT products_sale_currency_check CHECK (sale_currency IN ('SYP','USD'));

-- 3) Historical currency snapshots on sales/accounting. Existing rows are SYP snapshots only;
-- they are NOT revalued and their existing amount columns are untouched.
ALTER TABLE public.sales
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP',
  ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS total_syp numeric;

ALTER TABLE public.sale_items
  ADD COLUMN IF NOT EXISTS price_currency text NOT NULL DEFAULT 'SYP',
  ADD COLUMN IF NOT EXISTS price_fx_rate numeric NOT NULL DEFAULT 1;

ALTER TABLE public.cashbox_entries
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP',
  ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS amount_syp numeric;

ALTER TABLE public.debtor_transactions
  ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'SYP',
  ADD COLUMN IF NOT EXISTS fx_rate numeric NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS amount_syp numeric;

UPDATE public.sales SET total_syp = total WHERE total_syp IS NULL;
UPDATE public.cashbox_entries SET amount_syp = amount WHERE amount_syp IS NULL;
UPDATE public.debtor_transactions SET amount_syp = amount WHERE amount_syp IS NULL;

ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_currency_check;
ALTER TABLE public.sales ADD CONSTRAINT sales_currency_check CHECK (currency IN ('SYP','USD'));
ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_fx_rate_check;
ALTER TABLE public.sales ADD CONSTRAINT sales_fx_rate_check CHECK (fx_rate > 0);
ALTER TABLE public.sale_items DROP CONSTRAINT IF EXISTS sale_items_price_currency_check;
ALTER TABLE public.sale_items ADD CONSTRAINT sale_items_price_currency_check CHECK (price_currency IN ('SYP','USD'));
ALTER TABLE public.sale_items DROP CONSTRAINT IF EXISTS sale_items_price_fx_rate_check;
ALTER TABLE public.sale_items ADD CONSTRAINT sale_items_price_fx_rate_check CHECK (price_fx_rate > 0);
ALTER TABLE public.cashbox_entries DROP CONSTRAINT IF EXISTS cashbox_entries_currency_check;
ALTER TABLE public.cashbox_entries ADD CONSTRAINT cashbox_entries_currency_check CHECK (currency IN ('SYP','USD'));
ALTER TABLE public.cashbox_entries DROP CONSTRAINT IF EXISTS cashbox_entries_fx_rate_check;
ALTER TABLE public.cashbox_entries ADD CONSTRAINT cashbox_entries_fx_rate_check CHECK (fx_rate > 0);
ALTER TABLE public.debtor_transactions DROP CONSTRAINT IF EXISTS debtor_transactions_currency_check;
ALTER TABLE public.debtor_transactions ADD CONSTRAINT debtor_transactions_currency_check CHECK (currency IN ('SYP','USD'));
ALTER TABLE public.debtor_transactions DROP CONSTRAINT IF EXISTS debtor_transactions_fx_rate_check;
ALTER TABLE public.debtor_transactions ADD CONSTRAINT debtor_transactions_fx_rate_check CHECK (fx_rate > 0);

-- 4) Central settings RPCs.
CREATE OR REPLACE FUNCTION public.admin_get_currency_settings()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE r public.pharmacy_currency_settings;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT * INTO r FROM public.pharmacy_currency_settings WHERE id=1;
  RETURN jsonb_build_object('usd_to_syp',r.usd_to_syp,'updated_at',r.updated_at);
END; $$;
REVOKE ALL ON FUNCTION public.admin_get_currency_settings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_currency_settings() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_usd_to_syp_rate(p_rate numeric, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_rate IS NULL OR p_rate <= 0 THEN RAISE EXCEPTION 'سعر الصرف يجب أن يكون أكبر من صفر'; END IF;
  UPDATE public.pharmacy_currency_settings
  SET usd_to_syp=p_rate, updated_at=now(), updated_by=auth.uid()
  WHERE id=1;
  INSERT INTO public.pharmacy_currency_history(usd_to_syp,changed_by,note)
  VALUES(p_rate,auth.uid(),NULLIF(trim(COALESCE(p_note,'')),''));
  RETURN jsonb_build_object('usd_to_syp',p_rate,'updated_at',now());
END; $$;
REVOKE ALL ON FUNCTION public.admin_set_usd_to_syp_rate(numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_usd_to_syp_rate(numeric,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_currency_history()
RETURNS SETOF public.pharmacy_currency_history
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
  SELECT * FROM public.pharmacy_currency_history
  WHERE public.is_admin()
  ORDER BY changed_at DESC LIMIT 100;
$$;
REVOKE ALL ON FUNCTION public.admin_currency_history() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_currency_history() TO authenticated;

-- 5) Product save: same RPC/signature, now accepts sale_currency. Default remains SYP.
CREATE OR REPLACE FUNCTION public.admin_save_pharmacy_product(
  p_product_id uuid DEFAULT NULL,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS public.products
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE
  v public.products;
  v_name text; v_barcode text; v_ai text; v_strength text; v_dosage text; v_manufacturer text; v_category text; v_unit text;
  v_reorder numeric; v_purchase numeric; v_sale numeric; v_parts numeric; v_visible boolean; v_currency text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'غير مصرح'; END IF;
  v_name := NULLIF(trim(COALESCE(p_payload->>'name','')), '');
  IF v_name IS NULL THEN RAISE EXCEPTION 'اسم المنتج مطلوب'; END IF;
  v_barcode := NULLIF(trim(COALESCE(p_payload->>'barcode','')), '');
  v_ai := NULLIF(trim(COALESCE(p_payload->>'active_ingredient','')), '');
  v_strength := NULLIF(trim(COALESCE(p_payload->>'strength','')), '');
  v_dosage := NULLIF(trim(COALESCE(p_payload->>'dosage_form','')), '');
  v_manufacturer := NULLIF(trim(COALESCE(p_payload->>'manufacturer','')), '');
  v_category := NULLIF(trim(COALESCE(p_payload->>'category','')), '');
  v_unit := COALESCE(NULLIF(trim(COALESCE(p_payload->>'unit','')), ''), 'piece');
  v_reorder := GREATEST(0, COALESCE(NULLIF(p_payload->>'reorder_level','')::numeric,1));
  v_purchase := GREATEST(0, COALESCE(NULLIF(p_payload->>'purchase_price','')::numeric,0));
  v_sale := GREATEST(0, COALESCE(NULLIF(p_payload->>'sale_price','')::numeric,0));
  v_parts := GREATEST(1, COALESCE(NULLIF(p_payload->>'parts_per_unit','')::numeric,1));
  v_visible := COALESCE((p_payload->>'customer_visible')::boolean,true);
  v_currency := upper(COALESCE(NULLIF(trim(p_payload->>'sale_currency'),''),'SYP'));
  IF v_currency NOT IN ('SYP','USD') THEN RAISE EXCEPTION 'عملة سعر المبيع غير صحيحة'; END IF;

  IF p_product_id IS NULL THEN
    INSERT INTO public.products(name,barcode,active_ingredient,strength,dosage_form,manufacturer,category,unit,reorder_level,purchase_price,sale_price,parts_per_unit,customer_visible,active,sale_currency)
    VALUES(v_name,v_barcode,v_ai,v_strength,v_dosage,v_manufacturer,v_category,v_unit,v_reorder,v_purchase,v_sale,v_parts,v_visible,true,v_currency)
    RETURNING * INTO v;
  ELSE
    UPDATE public.products SET name=v_name,barcode=v_barcode,active_ingredient=v_ai,strength=v_strength,dosage_form=v_dosage,manufacturer=v_manufacturer,category=v_category,unit=v_unit,reorder_level=v_reorder,purchase_price=v_purchase,sale_price=v_sale,parts_per_unit=v_parts,customer_visible=v_visible,sale_currency=v_currency
    WHERE id=p_product_id RETURNING * INTO v;
    IF NOT FOUND THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;
  END IF;
  RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.admin_save_pharmacy_product(uuid,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_save_pharmacy_product(uuid,jsonb) TO authenticated;

-- 6) POS search: additive currency-aware RPC. The original admin_search_pos_products signature is NOT changed.
CREATE OR REPLACE FUNCTION public.admin_search_pos_products_currency(p_query text,p_limit integer DEFAULT 30)
RETURNS TABLE(id uuid,name text,barcode text,active_ingredient text,strength text,dosage_form text,unit text,sale_price numeric,purchase_price numeric,parts_per_unit numeric,stock numeric,expiry_date date,sale_currency text,current_fx_rate numeric,sale_price_syp numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
  SELECT p.id,p.name,p.barcode,p.active_ingredient,p.strength,p.dosage_form,p.unit,p.sale_price,p.purchase_price,p.parts_per_unit,
    COALESCE(SUM(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=CURRENT_DATE) THEN b.quantity ELSE 0 END),0),
    MIN(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=CURRENT_DATE) THEN b.expiry_date END),
    p.sale_currency,fx.usd_to_syp,
    CASE WHEN p.sale_currency='USD' THEN p.sale_price*fx.usd_to_syp ELSE p.sale_price END
  FROM public.products p CROSS JOIN public.pharmacy_currency_settings fx
  LEFT JOIN public.batches b ON b.product_id=p.id
  WHERE public.is_admin() AND (COALESCE(p.barcode,'') ILIKE p_query||'%' OR COALESCE(p.name,'') ILIKE '%'||p_query||'%' OR COALESCE(p.active_ingredient,'') ILIKE '%'||p_query||'%')
  GROUP BY p.id,fx.usd_to_syp
  ORDER BY CASE WHEN p.barcode=p_query THEN 0 WHEN lower(COALESCE(p.name,''))=lower(p_query) THEN 1 WHEN lower(COALESCE(p.name,'')) LIKE lower(p_query)||'%' THEN 2 WHEN COALESCE(p.active_ingredient,'') ILIKE '%'||p_query||'%' THEN 3 ELSE 4 END,
    MIN(CASE WHEN b.quantity>0 AND (b.expiry_date IS NULL OR b.expiry_date>=CURRENT_DATE) THEN b.expiry_date END) NULLS LAST,p.name
  LIMIT GREATEST(1,LEAST(COALESCE(p_limit,30),100));
$$;
REVOKE ALL ON FUNCTION public.admin_search_pos_products_currency(text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_pos_products_currency(text,integer) TO authenticated;

-- 7) The missing POS RPC. Signature intentionally matches the frontend error exactly.
CREATE OR REPLACE FUNCTION public.complete_sale_accounting_currency(
  p_currency text DEFAULT 'SYP',
  p_debtor_id uuid DEFAULT NULL,
  p_discount numeric DEFAULT 0,
  p_fx_rate numeric DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb,
  p_notes text DEFAULT NULL,
  p_payment_method text DEFAULT 'cash'
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE
  v_sale_id uuid:=gen_random_uuid(); it jsonb; b record; need numeric; take numeric; sub numeric:=0; v_total numeric:=0; v_paid numeric:=0; v_due numeric:=0;
  v_debtor_name text; v_product_id uuid; v_unit_price numeric; v_base_price numeric; v_product_currency text; v_item_fx numeric; v_stock numeric;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF upper(COALESCE(p_currency,'SYP')) NOT IN ('SYP','USD') THEN RAISE EXCEPTION 'عملة الفاتورة غير صحيحة'; END IF;
  IF jsonb_typeof(COALESCE(p_items,'[]'::jsonb))<>'array' OR jsonb_array_length(COALESCE(p_items,'[]'::jsonb))=0 THEN RAISE EXCEPTION 'Sale must contain items'; END IF;
  IF COALESCE(p_discount,0)<0 THEN RAISE EXCEPTION 'Invalid discount'; END IF;
  IF p_payment_method NOT IN ('cash','credit') THEN RAISE EXCEPTION 'Invalid payment method'; END IF;
  IF p_payment_method='credit' AND p_debtor_id IS NULL THEN RAISE EXCEPTION 'اختر ملف المتدين أولاً'; END IF;
  IF p_debtor_id IS NOT NULL THEN SELECT name INTO v_debtor_name FROM public.debtors WHERE id=p_debtor_id; IF NOT FOUND THEN RAISE EXCEPTION 'ملف المتدين غير موجود'; END IF; END IF;
  SELECT usd_to_syp INTO v_item_fx FROM public.pharmacy_currency_settings WHERE id=1;
  v_item_fx:=COALESCE(NULLIF(p_fx_rate,0),v_item_fx,1);
  INSERT INTO public.sales(id,customer_id,debtor_id,subtotal,discount,total,created_by,payment_method,paid_amount,due_amount,payment_notes,currency,fx_rate,total_syp)
  VALUES(v_sale_id,NULL,p_debtor_id,0,GREATEST(COALESCE(p_discount,0),0),0,auth.uid(),p_payment_method,0,0,p_notes,upper(COALESCE(p_currency,'SYP')),v_item_fx,0);

  FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id:=NULLIF(it->>'product_id','')::uuid;
    need:=COALESCE((it->>'quantity')::numeric,0);
    SELECT p.sale_price,p.sale_currency INTO v_base_price,v_product_currency FROM public.products p WHERE p.id=v_product_id AND COALESCE(p.active,true)=true;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid sale product'; END IF;
    IF need<=0 THEN RAISE EXCEPTION 'Invalid quantity'; END IF;
    v_product_currency:=upper(COALESCE(v_product_currency,'SYP'));
    IF v_product_currency='USD' THEN v_unit_price:=v_base_price*v_item_fx; ELSE v_unit_price:=v_base_price; END IF;
    IF it ? 'unit_price' AND (it->>'unit_price') IS NOT NULL THEN
      IF (it->>'unit_price')::numeric<0 THEN RAISE EXCEPTION 'سعر البيع لا يمكن أن يكون سالباً'; END IF;
      v_unit_price:=(it->>'unit_price')::numeric;
    END IF;
    FOR b IN SELECT bt.id,bt.quantity,bt.purchase_price,bt.expiry_date FROM public.batches bt WHERE bt.product_id=v_product_id AND bt.quantity>0 AND (bt.expiry_date IS NULL OR bt.expiry_date>=CURRENT_DATE) ORDER BY bt.expiry_date NULLS LAST,bt.received_date NULLS FIRST,bt.batch_number NULLS LAST,bt.id FOR UPDATE OF bt LOOP
      EXIT WHEN need<=0; take:=LEAST(need,b.quantity); UPDATE public.batches bt SET quantity=bt.quantity-take WHERE bt.id=b.id;
      INSERT INTO public.sale_items(sale_id,product_id,batch_id,quantity,unit_price,unit_cost,base_unit_price,price_currency,price_fx_rate)
      VALUES(v_sale_id,v_product_id,b.id,take,v_unit_price,b.purchase_price,v_base_price,v_product_currency,v_item_fx);
      INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,created_by) VALUES(v_product_id,b.id,'sale',-take,v_sale_id,auth.uid());
      sub:=sub+take*v_unit_price; need:=need-take;
    END LOOP;
    IF need>0 THEN RAISE EXCEPTION 'Insufficient non-expired stock for product %',v_product_id; END IF;
  END LOOP;
  v_total:=GREATEST(sub-GREATEST(COALESCE(p_discount,0),0),0);
  IF p_payment_method='cash' THEN v_paid:=v_total; v_due:=0; ELSE v_paid:=0; v_due:=v_total; END IF;
  UPDATE public.sales SET subtotal=sub,total=v_total,paid_amount=v_paid,due_amount=v_due,total_syp=v_total WHERE id=v_sale_id;
  IF p_payment_method='credit' THEN
    INSERT INTO public.debtor_transactions(debtor_id,transaction_type,sale_id,amount,debit,credit,payment_method,notes,created_by,currency,fx_rate,amount_syp)
    VALUES(p_debtor_id,'sale',v_sale_id,v_total,v_total,0,'credit',p_notes,auth.uid(),'SYP',v_item_fx,v_total);
  ELSE
    INSERT INTO public.cashbox_entries(entry_type,amount,description,sale_id,created_by,currency,fx_rate,amount_syp)
    VALUES('sale_cash',v_total,'بيع نقدي',v_sale_id,auth.uid(),'SYP',v_item_fx,v_total);
  END IF;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'complete_sale','sale',v_sale_id,jsonb_build_object('currency',upper(COALESCE(p_currency,'SYP')),'fx_rate',v_item_fx,'subtotal',sub,'discount',p_discount,'total',v_total,'payment_method',p_payment_method,'debtor_id',p_debtor_id,'debtor_name',v_debtor_name,'notes',p_notes));
  RETURN jsonb_build_object('sale_id',v_sale_id,'total',v_total,'currency','SYP','fx_rate',v_item_fx,'payment_method',p_payment_method,'debtor_id',p_debtor_id,'paid_amount',v_paid,'due_amount',v_due);
EXCEPTION WHEN OTHERS THEN
  RAISE;
END; $$;
REVOKE ALL ON FUNCTION public.complete_sale_accounting_currency(text,uuid,numeric,numeric,jsonb,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_sale_accounting_currency(text,uuid,numeric,numeric,jsonb,text,text) TO authenticated;

-- 8) Keep the old RPC intact and executable; the new currency RPC is additive.
REVOKE ALL ON FUNCTION public.complete_sale_accounting(jsonb,numeric,text,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_sale_accounting(jsonb,numeric,text,uuid,text) TO authenticated;

CREATE INDEX IF NOT EXISTS idx_products_sale_currency ON public.products(sale_currency);
CREATE INDEX IF NOT EXISTS idx_currency_history_changed_at ON public.pharmacy_currency_history(changed_at DESC);

COMMIT;
