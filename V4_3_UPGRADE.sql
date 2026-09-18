-- Pharmacy Abdelhadi v4.3
-- 1) Robust supplier management RPCs (avoid UI failures caused by direct RLS writes).
-- 2) Secure atomic POS sale function for admin.

ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS notes text;

CREATE OR REPLACE FUNCTION public.admin_create_supplier(
  p_name text,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.suppliers
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE v public.suppliers;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF nullif(trim(coalesce(p_name,'')), '') IS NULL THEN RAISE EXCEPTION 'Supplier name is required'; END IF;
  INSERT INTO public.suppliers(name, phone, address, notes)
  VALUES (trim(p_name), nullif(trim(coalesce(p_phone,'')),''), nullif(trim(coalesce(p_address,'')),''), nullif(trim(coalesce(p_notes,'')),''))
  RETURNING * INTO v;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_create_supplier(text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_supplier(text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_supplier(
  p_id uuid,
  p_name text,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.suppliers
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE v public.suppliers;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF nullif(trim(coalesce(p_name,'')), '') IS NULL THEN RAISE EXCEPTION 'Supplier name is required'; END IF;
  UPDATE public.suppliers SET name=trim(p_name), phone=nullif(trim(coalesce(p_phone,'')),''), address=nullif(trim(coalesce(p_address,'')),''), notes=nullif(trim(coalesce(p_notes,'')),'') WHERE id=p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Supplier not found'; END IF;
  SELECT * INTO v FROM public.suppliers WHERE id=p_id;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_supplier(uuid,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_supplier(uuid,text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_delete_supplier(p_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  DELETE FROM public.suppliers WHERE id=p_id;
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_delete_supplier(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_supplier(uuid) TO authenticated;



-- Supplier list: use a SECURITY DEFINER RPC so admin supplier records are
-- readable even when the base table has restrictive RLS policies.
CREATE OR REPLACE FUNCTION public.admin_list_suppliers()
RETURNS TABLE(
  id uuid,
  name text,
  phone text,
  address text,
  notes text,
  created_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;
  RETURN QUERY
  SELECT s.id, s.name, s.phone, s.address, s.notes, s.created_at
  FROM public.suppliers s
  ORDER BY s.name ASC, s.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_suppliers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_suppliers() TO authenticated;

-- Replace the POS function with a SECURITY DEFINER implementation so the
-- transaction can safely touch batches/stock_movements while still requiring admin auth.
CREATE OR REPLACE FUNCTION public.complete_sale_atomic(
  p_items jsonb,
  p_discount numeric DEFAULT 0,
  p_customer_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  sale_id uuid := gen_random_uuid();
  it jsonb;
  b record;
  need numeric;
  take numeric;
  sub numeric := 0;
  v_total numeric;
  v_product_id uuid;
  v_unit_price numeric;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array' OR jsonb_array_length(coalesce(p_items,'[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'Sale must contain items';
  END IF;
  IF coalesce(p_discount,0) < 0 THEN RAISE EXCEPTION 'Invalid discount'; END IF;

  INSERT INTO public.sales(id,customer_id,subtotal,discount,total,created_by)
  VALUES(sale_id,p_customer_id,0,greatest(coalesce(p_discount,0),0),0,auth.uid());

  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_product_id := nullif(it->>'product_id','')::uuid;
    need := coalesce((it->>'quantity')::numeric,0);
    v_unit_price := coalesce((it->>'unit_price')::numeric,0);
    IF v_product_id IS NULL OR need <= 0 OR v_unit_price < 0 THEN RAISE EXCEPTION 'Invalid sale item'; END IF;

    FOR b IN
      SELECT id,quantity,purchase_price,expiry_date
      FROM public.batches
      WHERE product_id=v_product_id
        AND quantity>0
        AND (expiry_date IS NULL OR expiry_date>=current_date)
      ORDER BY expiry_date NULLS LAST, received_date NULLS FIRST, id
      FOR UPDATE
    LOOP
      EXIT WHEN need<=0;
      take := least(need,b.quantity);
      UPDATE public.batches SET quantity=quantity-take WHERE id=b.id;
      INSERT INTO public.sale_items(sale_id,product_id,batch_id,quantity,unit_price,unit_cost)
      VALUES(sale_id,v_product_id,b.id,take,v_unit_price,b.purchase_price);
      INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,created_by)
      VALUES(v_product_id,b.id,'sale',-take,sale_id,auth.uid());
      sub := sub + take*v_unit_price;
      need := need-take;
    END LOOP;

    IF need>0 THEN RAISE EXCEPTION 'Insufficient non-expired stock for product %', v_product_id; END IF;
  END LOOP;

  v_total := greatest(sub-greatest(coalesce(p_discount,0),0),0);
  UPDATE public.sales SET subtotal=sub,total=v_total WHERE id=sale_id;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'complete_sale','sale',sale_id,jsonb_build_object('subtotal',sub,'discount',p_discount,'total',v_total));
  RETURN sale_id;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_sale_atomic(jsonb,numeric,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_sale_atomic(jsonb,numeric,uuid) TO authenticated;

-- Helpful verification query (run separately if desired):
-- SELECT to_regprocedure('public.admin_create_supplier(text,text,text,text)'),
--        to_regprocedure('public.complete_sale_atomic(jsonb,numeric,uuid)');
