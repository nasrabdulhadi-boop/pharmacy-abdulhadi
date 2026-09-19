-- Pharmacy Abdelhadi v4.4.2
-- Products + Inventory separation and purchase/net price
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS purchase_price numeric NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.products.purchase_price IS 'Default purchase/net price for the product. Actual batch purchase price remains in batches.purchase_price.';

-- Keep the admin product workflow compatible with existing RLS.
-- Existing admin INSERT/UPDATE policies on products continue to apply.

-- Backfill the product-level default net price from the latest received batch when available.
UPDATE public.products p
SET purchase_price = src.purchase_price
FROM (
  SELECT DISTINCT ON (product_id) product_id, COALESCE(purchase_price,0) AS purchase_price
  FROM public.batches
  ORDER BY product_id, received_date DESC NULLS LAST, created_at DESC NULLS LAST
) src
WHERE p.id = src.product_id AND COALESCE(p.purchase_price,0) = 0;
