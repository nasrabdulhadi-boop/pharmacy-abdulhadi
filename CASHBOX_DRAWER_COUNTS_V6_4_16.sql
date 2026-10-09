-- Pharmacy Abdelhadi V6.4.16 — persistent physical cash-count audit
-- Additive migration only: does not update or delete existing accounting records.
BEGIN;

CREATE TABLE IF NOT EXISTS public.cashbox_counts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  expected_balance numeric NOT NULL,
  actual_amount numeric NOT NULL CHECK (actual_amount >= 0),
  difference numeric NOT NULL,
  note text,
  counted_by uuid REFERENCES auth.users(id),
  counted_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.cashbox_counts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cashbox_counts_admin_select ON public.cashbox_counts;
CREATE POLICY cashbox_counts_admin_select ON public.cashbox_counts
  FOR SELECT TO authenticated USING (public.is_admin());
GRANT SELECT ON public.cashbox_counts TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.cashbox_counts FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin_record_cashbox_count(
  p_actual_amount numeric,
  p_note text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_expected numeric;
  v_difference numeric;
  v_id uuid;
  v_at timestamptz;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_actual_amount IS NULL OR p_actual_amount < 0 THEN
    RAISE EXCEPTION 'قيمة النقد الفعلي يجب أن تكون صفراً أو أكثر';
  END IF;

  -- Snapshot the ledger at count time; do not create an adjustment entry.
  SELECT COALESCE(SUM(amount), 0) INTO v_expected FROM public.cashbox_entries;
  v_difference := p_actual_amount - v_expected;

  INSERT INTO public.cashbox_counts(expected_balance, actual_amount, difference, note, counted_by)
  VALUES (v_expected, p_actual_amount, v_difference, NULLIF(trim(COALESCE(p_note, '')), ''), auth.uid())
  RETURNING id, counted_at INTO v_id, v_at;

  INSERT INTO public.audit_logs(user_id, action, entity_type, entity_id, details)
  VALUES (auth.uid(), 'cashbox_count', 'cashbox', v_id,
    jsonb_build_object('expected_balance', v_expected, 'actual_amount', p_actual_amount,
      'difference', v_difference, 'note', p_note, 'counted_at', v_at));

  RETURN jsonb_build_object('id', v_id, 'expected_balance', v_expected,
    'actual_amount', p_actual_amount, 'difference', v_difference, 'counted_at', v_at);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_record_cashbox_count(numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_record_cashbox_count(numeric, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_cashbox_count_history(p_limit integer DEFAULT 10)
RETURNS SETOF jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  RETURN QUERY
    SELECT jsonb_build_object('id', c.id, 'expected_balance', c.expected_balance,
      'actual_amount', c.actual_amount, 'difference', c.difference,
      'note', c.note, 'counted_at', c.counted_at)
    FROM public.cashbox_counts c
    ORDER BY c.counted_at DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 10), 1), 100);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_cashbox_count_history(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cashbox_count_history(integer) TO authenticated;

COMMIT;
