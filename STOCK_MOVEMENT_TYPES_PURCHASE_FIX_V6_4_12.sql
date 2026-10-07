-- Pharmacy Abdelhadi V6.4.12
-- FIX: stock_movements_movement_type_check blocking purchase invoices.
-- Safe/non-destructive: does NOT delete or modify existing stock movements,
-- purchases, batches, products, suppliers, or invoices.
-- Run ONCE in Supabase SQL Editor.

BEGIN;

DO $$
DECLARE
  vals text;
BEGIN
  -- Preserve every movement type already present, while explicitly allowing
  -- every movement type used by the current Pharmacy Abdelhadi system.
  SELECT string_agg(format('%L', v), ', ' ORDER BY v)
    INTO vals
  FROM (
    SELECT DISTINCT sm.movement_type AS v
    FROM public.stock_movements sm
    WHERE sm.movement_type IS NOT NULL

    UNION
    SELECT unnest(ARRAY[
      'purchase',
      'purchase_bonus',
      'sale',
      'customer_return',
      'supplier_return',
      'inventory_count',
      'disposal',
      'adjustment'
    ]::text[])
  ) q;

  IF vals IS NULL OR vals = '' THEN
    RAISE EXCEPTION 'Unable to build stock movement type constraint';
  END IF;

  ALTER TABLE public.stock_movements
    DROP CONSTRAINT IF EXISTS stock_movements_movement_type_check;

  EXECUTE format(
    'ALTER TABLE public.stock_movements ADD CONSTRAINT stock_movements_movement_type_check CHECK (movement_type IN (%s))',
    vals
  );
END $$;

COMMIT;

-- Verification (read-only):
-- SELECT pg_get_constraintdef(oid)
-- FROM pg_constraint
-- WHERE conrelid='public.stock_movements'::regclass
--   AND conname='stock_movements_movement_type_check';
