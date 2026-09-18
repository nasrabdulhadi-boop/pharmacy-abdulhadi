-- Pharmacy Abdelhadi v4.3.6
-- Run in Supabase SQL Editor.
-- Fixes POS ambiguous b.id and keeps audit/security improvements.

-- Pharmacy Abdelhadi v4.3.5
-- Fix batch deletion locking error + audit details for batch additions and sales.

ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS details jsonb;

-- IMPORTANT: lock the batch itself BEFORE reading the product. Do not use
-- FOR UPDATE on a LEFT JOIN nullable side.
CREATE OR REPLACE FUNCTION public.admin_delete_batch(p_batch_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_product_id uuid;
  v_batch_number text;
  v_quantity numeric;
  v_product_name text;
  v_sales_count bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  SELECT b.product_id, b.batch_number, b.quantity
  INTO v_product_id, v_batch_number, v_quantity
  FROM public.batches b
  WHERE v_batch.id = p_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN RETURN false; END IF;

  SELECT p.name INTO v_product_name
  FROM public.products p
  WHERE p.id = v_product_id;

  SELECT count(*) INTO v_sales_count
  FROM public.sale_items si
  WHERE si.batch_id = p_batch_id;

  IF v_sales_count > 0 THEN
    RAISE EXCEPTION 'لا يمكن حذف هذه الدفعة لأنها مرتبطة بمبيعات سابقة. للحفاظ على سجل المبيعات، عدّل الكمية بدلاً من حذفها.';
  END IF;

  DELETE FROM public.stock_movements WHERE batch_id = p_batch_id;
  DELETE FROM public.batches WHERE id = p_batch_id;

  INSERT INTO public.audit_logs(user_id, action, entity_type, entity_id, details)
  VALUES (auth.uid(),'admin_delete_batch','batch',p_batch_id,
    jsonb_build_object('product_id',v_product_id,'product_name',COALESCE(v_product_name,'—'),
      'batch_number',COALESCE(v_batch_number,'—'),'quantity_before_delete',v_quantity));
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_delete_batch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_batch(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.audit_batch_insert()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE v_product_name text;
BEGIN
  SELECT p.name INTO v_product_name FROM public.products p WHERE p.id=NEW.product_id;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'admin_create_batch','batch',NEW.id,
    jsonb_build_object('product_id',NEW.product_id,'product_name',COALESCE(v_product_name,'—'),
      'batch_number',COALESCE(NEW.batch_number,'—'),'expiry_date',NEW.expiry_date,
      'quantity',NEW.quantity,'purchase_price',NEW.purchase_price,'received_date',NEW.received_date));
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_audit_batch_insert ON public.batches;
CREATE TRIGGER trg_audit_batch_insert AFTER INSERT ON public.batches
FOR EACH ROW EXECUTE FUNCTION public.audit_batch_insert();

-- Rebuild sale audit so every sold item contains product name, batch number and quantity.
CREATE OR REPLACE FUNCTION public.complete_sale_atomic(
  p_items jsonb,
  p_discount numeric DEFAULT 0,
  p_customer_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  sale_id uuid := gen_random_uuid(); it jsonb; v_batch record; need numeric; take numeric;
  sub numeric := 0; v_total numeric; v_product_id uuid; v_unit_price numeric; v_sale_details jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array' OR jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 THEN RAISE EXCEPTION 'Sale must contain items'; END IF;
  IF coalesce(p_discount,0)<0 THEN RAISE EXCEPTION 'Invalid discount'; END IF;
  INSERT INTO public.sales(id,customer_id,subtotal,discount,total,created_by)
  VALUES(sale_id,p_customer_id,0,greatest(coalesce(p_discount,0),0),0,auth.uid());
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_product_id:=nullif(it->>'product_id','')::uuid; need:=coalesce((it->>'quantity')::numeric,0); v_unit_price:=coalesce((it->>'unit_price')::numeric,0);
    IF v_product_id IS NULL OR need<=0 OR v_unit_price<0 THEN RAISE EXCEPTION 'Invalid sale item'; END IF;
    FOR v_batch IN SELECT bt.id,bt.quantity,bt.purchase_price,bt.expiry_date FROM public.batches AS bt WHERE bt.product_id=v_product_id AND bt.quantity>0 AND (bt.expiry_date IS NULL OR bt.expiry_date>=current_date) ORDER BY bt.expiry_date NULLS LAST,bt.received_date NULLS FIRST,bt.id FOR UPDATE OF bt LOOP
      EXIT WHEN need<=0; take:=least(need,v_batch.quantity);
      UPDATE public.batches SET quantity=quantity-take WHERE id=v_batch.id;
      INSERT INTO public.sale_items(sale_id,product_id,batch_id,quantity,unit_price,unit_cost) VALUES(sale_id,v_product_id,v_batch.id,take,v_unit_price,v_batch.purchase_price);
      INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,created_by) VALUES(v_product_id,v_batch.id,'sale',-take,sale_id,auth.uid());
      sub:=sub+take*v_unit_price; need:=need-take;
    END LOOP;
    IF need>0 THEN RAISE EXCEPTION 'Insufficient non-expired stock for product %',v_product_id; END IF;
  END LOOP;
  v_total:=greatest(sub-greatest(coalesce(p_discount,0),0),0);
  UPDATE public.sales SET subtotal=sub,total=v_total WHERE id=sale_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('product_name',COALESCE(p.name,'—'),'batch_number',COALESCE(b.batch_number,'—'),'quantity',si.quantity) ORDER BY p.name,b.batch_number),'[]'::jsonb)
  INTO v_sale_details
  FROM public.sale_items si LEFT JOIN public.products p ON p.id=si.product_id LEFT JOIN public.batches b ON b.id=si.batch_id
  WHERE si.sale_id=sale_id;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'complete_sale','sale',sale_id,jsonb_build_object('subtotal',sub,'discount',p_discount,'total',v_total,'items',v_sale_details));
  RETURN sale_id;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_sale_atomic(jsonb,numeric,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_sale_atomic(jsonb,numeric,uuid) TO authenticated;
