-- Pharmacy Abdelhadi v4.4.0
-- POS table + partial-box (part/blister) support.
-- Run once in Supabase SQL Editor.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS parts_per_unit numeric NOT NULL DEFAULT 1;

UPDATE public.products
SET parts_per_unit = 1
WHERE parts_per_unit IS NULL OR parts_per_unit <= 0;

ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_parts_per_unit_positive;

ALTER TABLE public.products
  ADD CONSTRAINT products_parts_per_unit_positive CHECK (parts_per_unit >= 1);

COMMENT ON COLUMN public.products.parts_per_unit IS 'Number of sellable parts/blisters/strips contained in one stock unit (box). Used by POS partial-unit sales.';

-- The existing complete_sale_atomic already accepts numeric quantities, so a part
-- sale such as 1/10 of a box is stored as 0.1 and consumed by FEFO normally.
-- No replacement of the sale function is required for this UI upgrade.
