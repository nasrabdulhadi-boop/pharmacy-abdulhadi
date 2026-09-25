-- صيدلية عبدالهادي — V5.16 Smart Inventory hardening
-- Run once in Supabase SQL Editor after the existing V5.15 database scripts.
-- This patch is intentionally additive/idempotent and does not use CASCADE.
BEGIN;

-- 1) The smart inventory approval records a dedicated movement type.
-- Preserve every movement type already present and explicitly allow inventory_count.
DO $$
DECLARE vals text;
BEGIN
  SELECT string_agg(format('%L', v), ', ' ORDER BY v)
  INTO vals
  FROM (
    SELECT DISTINCT movement_type AS v
    FROM public.stock_movements
    WHERE movement_type IS NOT NULL
    UNION SELECT 'inventory_count'
  ) q;

  ALTER TABLE public.stock_movements
    DROP CONSTRAINT IF EXISTS stock_movements_movement_type_check;

  EXECUTE format(
    'ALTER TABLE public.stock_movements ADD CONSTRAINT stock_movements_movement_type_check CHECK (movement_type IN (%s))',
    vals
  );
END $$;

-- 2) Keep product search useful for name + active ingredient + barcode.
-- Exact barcode matches are naturally first; the UI can then select the product immediately.
CREATE OR REPLACE FUNCTION public.admin_search_inventory_products(p_query text DEFAULT NULL)
RETURNS TABLE(
  id uuid,
  name text,
  barcode text,
  active_ingredient text,
  stock numeric,
  total_received numeric,
  total_sold numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
  SELECT
    p.id,
    p.name,
    p.barcode,
    p.active_ingredient,
    COALESCE((SELECT SUM(b.quantity) FROM public.batches b WHERE b.product_id=p.id),0),
    COALESCE((SELECT SUM(sm.quantity) FROM public.stock_movements sm WHERE sm.product_id=p.id AND sm.movement_type='purchase' AND sm.quantity>0),0),
    COALESCE((SELECT SUM(-sm.quantity) FROM public.stock_movements sm WHERE sm.product_id=p.id AND sm.movement_type='sale' AND sm.quantity<0),0)
  FROM public.products p
  WHERE public.is_admin()
    AND (
      NULLIF(trim(COALESCE(p_query,'')),'') IS NULL
      OR p.name ILIKE '%'||trim(p_query)||'%'
      OR COALESCE(p.active_ingredient,'') ILIKE '%'||trim(p_query)||'%'
      OR COALESCE(p.barcode,'')=trim(p_query)
    )
  ORDER BY
    CASE
      WHEN COALESCE(p.barcode,'')=trim(COALESCE(p_query,'')) THEN 0
      WHEN lower(p.name)=lower(trim(COALESCE(p_query,''))) THEN 1
      WHEN lower(p.name) LIKE lower(trim(COALESCE(p_query,'')))||'%' THEN 2
      ELSE 3
    END,
    p.name
  LIMIT 30;
$$;
REVOKE ALL ON FUNCTION public.admin_search_inventory_products(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_inventory_products(text) TO authenticated;

-- 3) Replace the aggregate-product approval with a safe multi-batch reconciliation.
-- If the physical total is lower, quantities are removed across batches without ever making a batch negative.
-- If it is higher, the difference is added to the earliest-expiry existing batch.
-- Every affected batch gets its own stock-movement audit record.
CREATE OR REPLACE FUNCTION public.admin_complete_inventory_count(p_count_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth
AS $$
DECLARE
  r record;
  b record;
  v_diff numeric := 0;
  v_changes integer := 0;
  v_remaining numeric;
  v_take numeric;
  v_current numeric;
  v_target numeric;
  v_product uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.inventory_counts WHERE id=p_count_id) THEN
    RAISE EXCEPTION 'جرد المخزون غير موجود';
  END IF;
  IF EXISTS (SELECT 1 FROM public.inventory_counts WHERE id=p_count_id AND status<>'open') THEN
    RAISE EXCEPTION 'Inventory count is not open';
  END IF;
  IF EXISTS (SELECT 1 FROM public.inventory_count_items WHERE count_id=p_count_id AND actual_quantity IS NULL) THEN
    RAISE EXCEPTION 'أدخل الكمية الفعلية لكل منتج';
  END IF;

  FOR r IN SELECT * FROM public.inventory_count_items WHERE count_id=p_count_id ORDER BY id LOOP
    IF r.product_id IS NOT NULL THEN
      v_product := r.product_id;
      v_target := GREATEST(0, r.actual_quantity);
      SELECT COALESCE(SUM(quantity),0) INTO v_current
      FROM public.batches
      WHERE product_id=v_product;

      IF v_target <> v_current THEN
        IF v_target > v_current THEN
          SELECT id INTO b
          FROM public.batches
          WHERE product_id=v_product
          ORDER BY expiry_date NULLS LAST, received_date NULLS LAST, id
          LIMIT 1
          FOR UPDATE;

          IF b.id IS NULL THEN
            RAISE EXCEPTION 'لا توجد دفعة موجودة للمنتج لإضافة الكمية. أضف دفعة أولاً ثم أعد الجرد.';
          END IF;

          v_take := v_target-v_current;
          UPDATE public.batches SET quantity=quantity+v_take WHERE id=b.id;
          INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
          VALUES(v_product,b.id,'inventory_count',v_take,'تسوية جرد إجمالي للمنتج',auth.uid());
          v_changes := v_changes+1;
        ELSE
          v_remaining := v_current-v_target;
          FOR b IN
            SELECT id,quantity
            FROM public.batches
            WHERE product_id=v_product AND quantity>0
            ORDER BY expiry_date DESC NULLS LAST, received_date DESC NULLS LAST, id DESC
            FOR UPDATE
          LOOP
            EXIT WHEN v_remaining<=0;
            v_take := LEAST(b.quantity,v_remaining);
            UPDATE public.batches SET quantity=quantity-v_take WHERE id=b.id;
            INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
            VALUES(v_product,b.id,'inventory_count',-v_take,'تسوية جرد إجمالي للمنتج',auth.uid());
            v_remaining := v_remaining-v_take;
            v_changes := v_changes+1;
          END LOOP;
        END IF;
        v_diff := v_diff + (v_target-v_current);
      END IF;
    ELSE
      IF r.difference<>0 THEN
        UPDATE public.batches SET quantity=GREATEST(0,r.actual_quantity) WHERE id=r.batch_id;
        SELECT product_id INTO v_product FROM public.batches WHERE id=r.batch_id;
        INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
        VALUES(v_product,r.batch_id,'inventory_count',r.difference,'تسوية جرد v5.16',auth.uid());
        v_diff := v_diff+r.difference;
        v_changes := v_changes+1;
      END IF;
    END IF;
  END LOOP;

  UPDATE public.inventory_counts
  SET status='completed', completed_at=now()
  WHERE id=p_count_id;

  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(
    auth.uid(),
    'inventory_count_complete',
    'inventory_count',
    p_count_id,
    jsonb_build_object('changes',v_changes,'net_difference',v_diff,'mode','aggregate_product_v5_16')
  );

  RETURN jsonb_build_object('id',p_count_id,'changes',v_changes,'net_difference',v_diff);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_complete_inventory_count(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_complete_inventory_count(uuid) TO authenticated;

COMMIT;
