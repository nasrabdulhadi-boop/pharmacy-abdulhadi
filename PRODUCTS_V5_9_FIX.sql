-- Pharmacy Abdelhadi v5.9 - Pharmacy Products fixes
-- Safe product create/update/delete helpers + validation.

-- Compatibility: some existing databases were created without products.active.
-- Add it safely so product archive/delete logic and the pharmacy list can use it.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='products' AND column_name='active'
  ) THEN
    ALTER TABLE public.products ADD COLUMN active boolean NOT NULL DEFAULT true;
  END IF;
END $$;


CREATE OR REPLACE FUNCTION public.admin_save_pharmacy_product(
  p_product_id uuid DEFAULT NULL,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS public.products
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v public.products;
  v_name text;
  v_barcode text;
  v_ai text;
  v_strength text;
  v_dosage text;
  v_manufacturer text;
  v_category text;
  v_unit text;
  v_reorder numeric;
  v_purchase numeric;
  v_sale numeric;
  v_parts numeric;
  v_visible boolean;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح';
  END IF;

  v_name := NULLIF(trim(COALESCE(p_payload->>'name','')), '');
  IF v_name IS NULL THEN RAISE EXCEPTION 'اسم المنتج مطلوب'; END IF;

  v_barcode := NULLIF(trim(COALESCE(p_payload->>'barcode','')), '');
  v_ai := NULLIF(trim(COALESCE(p_payload->>'active_ingredient','')), '');
  v_strength := NULLIF(trim(COALESCE(p_payload->>'strength','')), '');
  v_dosage := NULLIF(trim(COALESCE(p_payload->>'dosage_form','')), '');
  v_manufacturer := NULLIF(trim(COALESCE(p_payload->>'manufacturer','')), '');
  v_category := NULLIF(trim(COALESCE(p_payload->>'category','')), '');
  v_unit := COALESCE(NULLIF(trim(COALESCE(p_payload->>'unit','')), ''), 'piece');
  v_reorder := GREATEST(0, COALESCE(NULLIF(p_payload->>'reorder_level','')::numeric, 1));
  v_purchase := GREATEST(0, COALESCE(NULLIF(p_payload->>'purchase_price','')::numeric, 0));
  v_sale := GREATEST(0, COALESCE(NULLIF(p_payload->>'sale_price','')::numeric, 0));
  v_parts := GREATEST(1, COALESCE(NULLIF(p_payload->>'parts_per_unit','')::numeric, 1));
  v_visible := COALESCE((p_payload->>'customer_visible')::boolean, true);

  IF p_product_id IS NULL THEN
    INSERT INTO public.products
      (name, barcode, active_ingredient, strength, dosage_form, manufacturer, category,
       unit, reorder_level, purchase_price, sale_price, parts_per_unit, customer_visible, active)
    VALUES
      (v_name, v_barcode, v_ai, v_strength, v_dosage, v_manufacturer, v_category,
       v_unit, v_reorder, v_purchase, v_sale, v_parts, v_visible, true)
    RETURNING * INTO v;
  ELSE
    UPDATE public.products
    SET name=v_name,
        barcode=v_barcode,
        active_ingredient=v_ai,
        strength=v_strength,
        dosage_form=v_dosage,
        manufacturer=v_manufacturer,
        category=v_category,
        unit=v_unit,
        reorder_level=v_reorder,
        purchase_price=v_purchase,
        sale_price=v_sale,
        parts_per_unit=v_parts,
        customer_visible=v_visible
    WHERE id=p_product_id
    RETURNING * INTO v;

    IF NOT FOUND THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;
  END IF;

  RETURN v;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_save_pharmacy_product(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_save_pharmacy_product(uuid, jsonb) TO authenticated;

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
    -- Keep historical sales/purchases intact. Products referenced by history
    -- cannot be physically deleted; archive them instead so they disappear
    -- from the active pharmacy-products list without corrupting accounting.
    UPDATE public.products
       SET active=false, customer_visible=false
     WHERE id=p_product_id;
    RETURN QUERY SELECT false, true, 'للمنتج سجلات مرتبطة بالمخزون أو المبيعات، لذلك تم أرشفته بدلاً من حذف السجل التاريخي';
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_pharmacy_product(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_pharmacy_product(uuid) TO authenticated;

-- Defensive constraints: prices cannot be negative and reorder level cannot be negative.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='products_purchase_price_nonnegative') THEN
    ALTER TABLE public.products ADD CONSTRAINT products_purchase_price_nonnegative CHECK (purchase_price >= 0) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='products_sale_price_nonnegative') THEN
    ALTER TABLE public.products ADD CONSTRAINT products_sale_price_nonnegative CHECK (sale_price >= 0) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='products_reorder_level_nonnegative') THEN
    ALTER TABLE public.products ADD CONSTRAINT products_reorder_level_nonnegative CHECK (reorder_level >= 0) NOT VALID;
  END IF;
END $$;
