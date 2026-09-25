-- Pharmacy Abdelhadi v5.16.1
-- Smart inventory: immediate, persistent result for full and single-product counts.
-- Run AFTER SMART_INVENTORY_V5_16_FIX.sql.
BEGIN;

-- Returns one normalized result row per product for a completed inventory count.
-- For a full count, multiple batch rows are aggregated into one product row.
-- For a single-product count, the single aggregate row is returned naturally.
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
      SUM(COALESCE(i.actual_quantity,0)) AS after_quantity,
      SUM(i.difference) AS difference,
      COUNT(*)::integer AS batch_count
    FROM public.inventory_count_items i
    LEFT JOIN public.batches b ON b.id=i.batch_id
    JOIN public.products pr ON pr.id=COALESCE(i.product_id,b.product_id)
    WHERE i.count_id=p_count_id
    GROUP BY COALESCE(i.product_id,b.product_id),pr.name,pr.barcode
  )
  SELECT
    COALESCE(jsonb_agg(
      jsonb_build_object(
        'product_id',g.product_id,
        'product_name',g.product_name,
        'barcode',g.barcode,
        'before_quantity',g.before_quantity,
        'after_quantity',g.after_quantity,
        'difference',g.difference,
        'result',CASE
          WHEN g.difference=0 THEN 'matched'
          WHEN g.difference<0 THEN 'shortage'
          ELSE 'surplus'
        END,
        'batch_count',g.batch_count
      ) ORDER BY g.product_name
    ),'[]'::jsonb),
    COUNT(*)::integer,
    COUNT(*) FILTER (WHERE g.difference=0)::integer,
    COUNT(*) FILTER (WHERE g.difference<0)::integer,
    COUNT(*) FILTER (WHERE g.difference>0)::integer,
    COALESCE(SUM(g.difference),0)
  INTO v_rows,v_total,v_matched,v_short,v_over,v_net
  FROM grouped g;

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

-- Fetch the latest completed count for display after page refresh/re-entry.
CREATE OR REPLACE FUNCTION public.admin_latest_inventory_count_result()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  SELECT id INTO v_id
  FROM public.inventory_counts
  WHERE status='completed'
  ORDER BY completed_at DESC NULLS LAST, started_at DESC
  LIMIT 1;

  IF v_id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN public.admin_inventory_count_result(v_id);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_latest_inventory_count_result() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_latest_inventory_count_result() TO authenticated;

COMMIT;
