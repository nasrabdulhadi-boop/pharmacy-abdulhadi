-- Pharmacy Abdelhadi v5.16.3
-- Fix: Smart Inventory result disappearing after completion/refresh.
-- Reason: the frontend was calling admin_latest_inventory_count_result(),
-- but v5.16.2 only created admin_inventory_count_result(count_id).
-- This patch adds a safe latest-result RPC and keeps the complete result data.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_latest_inventory_count_result()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public,auth
AS $$
DECLARE
  v_count_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;

  SELECT id
    INTO v_count_id
  FROM public.inventory_counts
  WHERE status='completed'
  ORDER BY completed_at DESC NULLS LAST, started_at DESC
  LIMIT 1;

  IF v_count_id IS NULL THEN
    RETURN NULL;
  END IF;

  RETURN public.admin_inventory_count_result(v_count_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_latest_inventory_count_result() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_latest_inventory_count_result() TO authenticated;

COMMIT;
