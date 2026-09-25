-- Pharmacy Abdelhadi v5.16.2
-- Smart inventory: add sales during the inventory-count period to the result.
-- Run AFTER SMART_INVENTORY_V5_16_FIX.sql and SMART_INVENTORY_V5_16_1_RESULT.sql.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_inventory_count_result(p_count_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE
  v_count public.inventory_counts%ROWTYPE;
  v_rows jsonb;
  v_mode text;
  v_total integer;
  v_matched integer;
  v_short integer;
  v_over integer;
  v_net numeric;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  SELECT * INTO v_count
  FROM public.inventory_counts
  WHERE id=p_count_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'جرد المخزون غير موجود';
  END IF;

  IF v_count.status <> 'completed' THEN
    RAISE EXCEPTION 'نتيجة الجرد متاحة بعد اعتماد الجرد';
  END IF;

  v_mode := CASE
    WHEN EXISTS (
      SELECT 1 FROM public.inventory_count_items i
      WHERE i.count_id=p_count_id AND i.product_id IS NOT NULL
    ) THEN 'single_product'
    ELSE 'full'
  END;

  WITH grouped AS (
    SELECT
      COALESCE(i.product_id,b.product_id) AS product_id,
      pr.name AS product_name,
      pr.barcode,
      SUM(i.expected_quantity) AS before_quantity,
      SUM(COALESCE(i.actual_quantity,0)) AS actual_quantity,
      COUNT(*)::integer AS batch_count,
      COALESCE((
        SELECT SUM(-sm.quantity)
        FROM public.stock_movements sm
        WHERE sm.product_id=COALESCE(i.product_id,b.product_id)
          AND sm.movement_type='sale'
          AND sm.quantity<0
          AND sm.created_at >= v_count.started_at
          AND sm.created_at <= COALESCE(v_count.completed_at,now())
      ),0) AS sold_quantity
    FROM public.inventory_count_items i
    LEFT JOIN public.batches b ON b.id=i.batch_id
    JOIN public.products pr ON pr.id=COALESCE(i.product_id,b.product_id)
    WHERE i.count_id=p_count_id
    GROUP BY COALESCE(i.product_id,b.product_id),pr.name,pr.barcode
  ), normalized AS (
    SELECT *,
      GREATEST(before_quantity - sold_quantity,0) AS expected_after_sales,
      actual_quantity - GREATEST(before_quantity - sold_quantity,0) AS difference
    FROM grouped
  )
  SELECT
    COALESCE(jsonb_agg(
      jsonb_build_object(
        'product_id',n.product_id,
        'product_name',n.product_name,
        'barcode',n.barcode,
        'before_quantity',n.before_quantity,
        'sold_quantity',n.sold_quantity,
        'expected_after_sales',n.expected_after_sales,
        'after_quantity',n.actual_quantity,
        'difference',n.difference,
        'result',CASE
          WHEN n.difference=0 THEN 'matched'
          WHEN n.difference<0 THEN 'shortage'
          ELSE 'surplus'
        END,
        'batch_count',n.batch_count
      ) ORDER BY n.product_name
    ),'[]'::jsonb),
    COUNT(*)::integer,
    COUNT(*) FILTER (WHERE n.difference=0)::integer,
    COUNT(*) FILTER (WHERE n.difference<0)::integer,
    COUNT(*) FILTER (WHERE n.difference>0)::integer,
    COALESCE(SUM(n.difference),0)
  INTO v_rows,v_total,v_matched,v_short,v_over,v_net
  FROM normalized n;

  RETURN jsonb_build_object(
    'count_id',p_count_id,
    'mode',v_mode,
    'status',v_count.status,
    'started_at',v_count.started_at,
    'completed_at',v_count.completed_at,
    'notes',v_count.notes,
    'summary',jsonb_build_object(
      'total',v_total,
      'matched',v_matched,
      'shortage',v_short,
      'surplus',v_over,
      'net_difference',v_net
    ),
    'rows',v_rows
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_inventory_count_result(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_inventory_count_result(uuid) TO authenticated;

COMMIT;
