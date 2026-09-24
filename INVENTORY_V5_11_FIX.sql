-- Pharmacy Abdelhadi v5.11 — Inventory fixes
-- Run once in Supabase SQL Editor.
BEGIN;

ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS details jsonb;

-- Ensure purchase-item traceability does not block a controlled batch deletion.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchase_items_batch_id_fkey') THEN
    ALTER TABLE public.purchase_items DROP CONSTRAINT purchase_items_batch_id_fkey;
  END IF;
  ALTER TABLE public.purchase_items
    ADD CONSTRAINT purchase_items_batch_id_fkey
    FOREIGN KEY (batch_id) REFERENCES public.batches(id) ON DELETE SET NULL;
END $$;

-- Controlled batch edit: quantity and expiry are changed from the material card only.
CREATE OR REPLACE FUNCTION public.admin_update_batch_details(
  p_batch_id uuid,
  p_quantity numeric,
  p_expiry_date date,
  p_purchase_price numeric DEFAULT NULL,
  p_sale_price numeric DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  b public.batches%rowtype;
  v_old numeric;
  v_new numeric;
  v_product_name text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_quantity IS NULL OR p_quantity < 0 THEN RAISE EXCEPTION 'الكمية يجب أن تكون صفراً أو أكبر'; END IF;
  IF p_expiry_date IS NULL THEN RAISE EXCEPTION 'تاريخ الصلاحية مطلوب'; END IF;
  IF p_purchase_price IS NOT NULL AND p_purchase_price < 0 THEN RAISE EXCEPTION 'سعر النت لا يمكن أن يكون سالباً'; END IF;
  IF p_sale_price IS NOT NULL AND p_sale_price < 0 THEN RAISE EXCEPTION 'سعر المبيع لا يمكن أن يكون سالباً'; END IF;

  SELECT * INTO b FROM public.batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الدفعة غير موجودة'; END IF;
  v_old:=COALESCE(b.quantity,0); v_new:=p_quantity;
  SELECT name INTO v_product_name FROM public.products WHERE id=b.product_id;

  UPDATE public.batches
  SET quantity=v_new,
      expiry_date=p_expiry_date,
      purchase_price=COALESCE(p_purchase_price,purchase_price)
  WHERE id=p_batch_id;

  IF v_new<>v_old THEN
    INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
    VALUES(b.product_id,b.id,'adjustment',v_new-v_old,'تعديل كمية من بطاقة المادة',auth.uid());
  END IF;

  IF p_purchase_price IS NOT NULL OR p_sale_price IS NOT NULL THEN
    UPDATE public.products
    SET purchase_price=COALESCE(p_purchase_price,purchase_price),
        sale_price=COALESCE(p_sale_price,sale_price),
        updated_at=now()
    WHERE id=b.product_id;
  END IF;

  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'adjust_stock','batch',b.id,jsonb_build_object(
    'product_id',b.product_id,
    'product_name',COALESCE(v_product_name,'—'),
    'old_quantity',v_old,
    'new_quantity',v_new,
    'delta',v_new-v_old,
    'old_expiry_date',b.expiry_date,
    'new_expiry_date',p_expiry_date,
    'old_purchase_price',b.purchase_price,
    'new_purchase_price',COALESCE(p_purchase_price,b.purchase_price),
    'new_sale_price',p_sale_price,
    'note','تعديل من بطاقة المادة'
  ));
  RETURN v_new;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_batch_details(uuid,numeric,date,numeric,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_batch_details(uuid,numeric,date,numeric,numeric) TO authenticated;

-- Rebuild adjust_stock with explicit before/after values in the security log.
CREATE OR REPLACE FUNCTION public.adjust_stock(
  p_batch_id uuid,
  p_delta numeric,
  p_note text DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  b public.batches%rowtype;
  old_qty numeric;
  new_qty numeric;
  product_name text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF COALESCE(p_delta,0)=0 THEN RAISE EXCEPTION 'Stock adjustment cannot be zero'; END IF;
  SELECT * INTO b FROM public.batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Batch not found'; END IF;
  old_qty:=COALESCE(b.quantity,0); new_qty:=old_qty+p_delta;
  IF new_qty<0 THEN RAISE EXCEPTION 'Insufficient stock: الكمية بعد التعديل لا يمكن أن تكون سالبة'; END IF;
  UPDATE public.batches SET quantity=new_qty WHERE id=p_batch_id;
  INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
  VALUES(b.product_id,b.id,'adjustment',p_delta,p_note,auth.uid());
  SELECT name INTO product_name FROM public.products WHERE id=b.product_id;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'adjust_stock','batch',b.id,jsonb_build_object(
    'product_id',b.product_id,'product_name',COALESCE(product_name,'—'),
    'old_quantity',old_qty,'new_quantity',new_qty,'delta',p_delta,'note',p_note
  ));
  RETURN new_qty;
END;
$$;
REVOKE ALL ON FUNCTION public.adjust_stock(uuid,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.adjust_stock(uuid,numeric,text) TO authenticated;

-- Safe batch deletion. Sales-linked batches remain protected; purchase trace is detached
-- with ON DELETE SET NULL so historical purchase invoices remain intact.
CREATE OR REPLACE FUNCTION public.admin_delete_batch(p_batch_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  b public.batches%rowtype;
  v_product_name text;
  v_purchase_items bigint;
  v_movements bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT * INTO b FROM public.batches WHERE id=p_batch_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  SELECT name INTO v_product_name FROM public.products WHERE id=b.product_id;
  IF EXISTS(SELECT 1 FROM public.sale_items WHERE batch_id=p_batch_id) THEN
    RAISE EXCEPTION 'لا يمكن حذف هذه الدفعة لأنها مرتبطة بمبيعات سابقة. للحفاظ على سجل المبيعات، عدّل الكمية بدلاً من حذفها.';
  END IF;
  SELECT count(*) INTO v_purchase_items FROM public.purchase_items WHERE batch_id=p_batch_id;
  SELECT count(*) INTO v_movements FROM public.stock_movements WHERE batch_id=p_batch_id;

  -- Preserve purchase invoices while removing the batch record.
  UPDATE public.purchase_items SET batch_id=NULL WHERE batch_id=p_batch_id;
  -- Open inventory-count snapshots may reference this batch; detach them safely.
  UPDATE public.inventory_count_items SET batch_id=NULL, product_id=COALESCE(product_id,b.product_id) WHERE batch_id=p_batch_id;
  DELETE FROM public.stock_movements WHERE batch_id=p_batch_id;
  DELETE FROM public.batches WHERE id=p_batch_id;

  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'admin_delete_batch','batch',p_batch_id,jsonb_build_object(
    'product_id',b.product_id,'product_name',COALESCE(v_product_name,'—'),
    'batch_number',COALESCE(b.batch_number,'—'),'quantity_before_delete',b.quantity,
    'purchase_items_detached',v_purchase_items,'stock_movements_removed',v_movements
  ));
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_delete_batch(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_batch(uuid) TO authenticated;

COMMIT;
