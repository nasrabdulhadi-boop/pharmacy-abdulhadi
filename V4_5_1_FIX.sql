-- Pharmacy Abdelhadi v4.5.1 — immediate fix
-- Fix audit_logs column mismatch and safely replace purchase RPC.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_create_purchase(
  p_supplier_id uuid,
  p_invoice_number text DEFAULT NULL,
  p_invoice_date date DEFAULT CURRENT_DATE,
  p_notes text DEFAULT NULL,
  p_items jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_purchase_id uuid := gen_random_uuid();
  v_item jsonb; v_item_id uuid; v_batch_id uuid;
  v_total numeric := 0; v_qty numeric; v_purchase_price numeric; v_sale_price numeric;
  v_product_id uuid; v_expiry date; v_invoice text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_supplier_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.suppliers WHERE id=p_supplier_id) THEN RAISE EXCEPTION 'Supplier not found'; END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items)=0 THEN RAISE EXCEPTION 'Purchase invoice must contain at least one item'; END IF;
  v_invoice := NULLIF(trim(COALESCE(p_invoice_number,'')), '');
  IF v_invoice IS NULL THEN v_invoice := 'PUR-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS'); END IF;

  INSERT INTO public.purchases(supplier_id,invoice_number,invoice_date,notes,status,total)
  VALUES(p_supplier_id,v_invoice,COALESCE(p_invoice_date,CURRENT_DATE),NULLIF(trim(COALESCE(p_notes,'')),''),'received',0)
  RETURNING id INTO v_purchase_id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    v_product_id := NULLIF(v_item->>'product_id','')::uuid;
    v_qty := COALESCE((v_item->>'quantity')::numeric,0);
    v_purchase_price := COALESCE((v_item->>'purchase_price')::numeric,0);
    v_sale_price := COALESCE((v_item->>'sale_price')::numeric,0);
    v_expiry := NULLIF(v_item->>'expiry_date','')::date;
    IF v_product_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.products WHERE id=v_product_id) THEN RAISE EXCEPTION 'Invalid product in purchase invoice'; END IF;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Purchase quantity must be greater than zero'; END IF;
    IF v_expiry IS NULL THEN RAISE EXCEPTION 'Expiry date is required for every purchase item'; END IF;
    IF v_purchase_price < 0 OR v_sale_price < 0 THEN RAISE EXCEPTION 'Prices cannot be negative'; END IF;

    INSERT INTO public.purchase_items(purchase_id,product_id,quantity,purchase_price,expiry_date,sale_price)
    VALUES(v_purchase_id,v_product_id,v_qty,v_purchase_price,v_expiry,v_sale_price) RETURNING id INTO v_item_id;
    v_batch_id := gen_random_uuid();
    INSERT INTO public.batches(id,product_id,batch_number,expiry_date,quantity,purchase_price,received_date,supplier_id,purchase_id,purchase_item_id)
    VALUES(v_batch_id,v_product_id,'AUTO-'||substr(replace(v_item_id::text,'-',''),1,12),v_expiry,v_qty,v_purchase_price,COALESCE(p_invoice_date,CURRENT_DATE),p_supplier_id,v_purchase_id,v_item_id);
    UPDATE public.purchase_items SET batch_id=v_batch_id WHERE id=v_item_id;
    UPDATE public.products SET purchase_price=v_purchase_price,sale_price=CASE WHEN v_sale_price>0 THEN v_sale_price ELSE sale_price END,updated_at=now() WHERE id=v_product_id;
    INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
    VALUES(v_product_id,v_batch_id,'purchase',v_qty,'استلام فاتورة شراء '||v_invoice,auth.uid());
    v_total := v_total + (v_qty*v_purchase_price);
  END LOOP;
  UPDATE public.purchases SET total=v_total WHERE id=v_purchase_id;
  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'admin_create_purchase','purchase',v_purchase_id,jsonb_build_object('supplier_id',p_supplier_id,'invoice_number',v_invoice,'total',v_total,'items_count',jsonb_array_length(p_items)));
  RETURN jsonb_build_object('id',v_purchase_id,'public_code',v_invoice,'total',v_total);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_purchase(uuid,text,date,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_purchase(uuid,text,date,text,jsonb) TO authenticated;
COMMIT;
