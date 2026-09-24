-- Pharmacy Abdelhadi v5.10 combined fix
-- Run once in Supabase SQL Editor.

-- 1) Compatibility for products.active used by pharmacy product archive/delete logic.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='products' AND column_name='active'
  ) THEN
    ALTER TABLE public.products ADD COLUMN active boolean NOT NULL DEFAULT true;
  END IF;
END $$;

-- 2) Ensure all existing products are active unless intentionally archived later.
UPDATE public.products SET active = true WHERE active IS NULL;

-- 3) Recreate the admin product delete/archive helper after the compatibility column exists.
CREATE OR REPLACE FUNCTION public.admin_delete_pharmacy_product(p_product_id uuid)
RETURNS TABLE(deleted boolean, archived boolean, message text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'غير مصرح'; END IF;

  BEGIN
    DELETE FROM public.products WHERE id=p_product_id;
    IF NOT FOUND THEN
      RETURN QUERY SELECT false, false, 'المنتج غير موجود';
      RETURN;
    END IF;
    RETURN QUERY SELECT true, false, 'تم حذف المنتج نهائياً';
  EXCEPTION WHEN foreign_key_violation THEN
    UPDATE public.products
       SET active=false, customer_visible=false
     WHERE id=p_product_id;
    RETURN QUERY SELECT false, true, 'للمنتج سجلات مرتبطة بالمخزون أو المبيعات، لذلك تم أرشفته بدلاً من حذف السجل التاريخي';
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_pharmacy_product(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_pharmacy_product(uuid) TO authenticated;
