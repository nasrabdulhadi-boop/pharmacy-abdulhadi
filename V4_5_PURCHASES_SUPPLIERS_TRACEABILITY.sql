-- Pharmacy Abdelhadi v4.5
-- Supplier -> purchase invoice -> purchase items -> batches -> inventory traceability
-- Run this once in Supabase SQL Editor while logged in as project owner.

BEGIN;

-- Existing tables are retained. We only add traceability fields.
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS supplier_id uuid;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS invoice_number text;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS invoice_date date DEFAULT CURRENT_DATE;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS notes text;
ALTER TABLE public.purchases ADD COLUMN IF NOT EXISTS status text DEFAULT 'received';

ALTER TABLE public.purchase_items ADD COLUMN IF NOT EXISTS batch_id uuid;
ALTER TABLE public.purchase_items ADD COLUMN IF NOT EXISTS expiry_date date;
ALTER TABLE public.purchase_items ADD COLUMN IF NOT EXISTS sale_price numeric DEFAULT 0;

ALTER TABLE public.batches ADD COLUMN IF NOT EXISTS supplier_id uuid;
ALTER TABLE public.batches ADD COLUMN IF NOT EXISTS purchase_id uuid;
ALTER TABLE public.batches ADD COLUMN IF NOT EXISTS purchase_item_id uuid;

-- Useful indexes.
CREATE INDEX IF NOT EXISTS idx_purchases_supplier_id ON public.purchases(supplier_id);
CREATE INDEX IF NOT EXISTS idx_purchases_invoice_number ON public.purchases(invoice_number);
CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase_id ON public.purchase_items(purchase_id);
CREATE INDEX IF NOT EXISTS idx_purchase_items_batch_id ON public.purchase_items(batch_id);
CREATE INDEX IF NOT EXISTS idx_batches_supplier_id ON public.batches(supplier_id);
CREATE INDEX IF NOT EXISTS idx_batches_purchase_id ON public.batches(purchase_id);
CREATE INDEX IF NOT EXISTS idx_batches_purchase_item_id ON public.batches(purchase_item_id);

-- Foreign keys are intentionally added only when absent. Existing data is preserved.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchases_supplier_id_fkey') THEN
    ALTER TABLE public.purchases ADD CONSTRAINT purchases_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='purchase_items_batch_id_fkey') THEN
    ALTER TABLE public.purchase_items ADD CONSTRAINT purchase_items_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.batches(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='batches_supplier_id_fkey') THEN
    ALTER TABLE public.batches ADD CONSTRAINT batches_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='batches_purchase_id_fkey') THEN
    ALTER TABLE public.batches ADD CONSTRAINT batches_purchase_id_fkey FOREIGN KEY (purchase_id) REFERENCES public.purchases(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='batches_purchase_item_id_fkey') THEN
    ALTER TABLE public.batches ADD CONSTRAINT batches_purchase_item_id_fkey FOREIGN KEY (purchase_item_id) REFERENCES public.purchase_items(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Backfill supplier/purchase linkage where old purchases already have supplier_id.
UPDATE public.batches b
SET supplier_id = p.supplier_id,
    purchase_id = COALESCE(b.purchase_id, pi.purchase_id),
    purchase_item_id = COALESCE(b.purchase_item_id, pi.id)
FROM public.purchase_items pi
JOIN public.purchases p ON p.id = pi.purchase_id
WHERE pi.batch_id = b.id
  AND (b.supplier_id IS NULL OR b.purchase_id IS NULL OR b.purchase_item_id IS NULL);

-- Admin: create a complete purchase atomically.
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
  v_item jsonb;
  v_item_id uuid;
  v_batch_id uuid;
  v_total numeric := 0;
  v_qty numeric;
  v_purchase_price numeric;
  v_sale_price numeric;
  v_product_id uuid;
  v_expiry date;
  v_invoice text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  IF p_supplier_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.suppliers WHERE id=p_supplier_id) THEN
    RAISE EXCEPTION 'Supplier not found';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items)=0 THEN
    RAISE EXCEPTION 'Purchase invoice must contain at least one item';
  END IF;

  v_invoice := NULLIF(trim(COALESCE(p_invoice_number,'')), '');
  IF v_invoice IS NULL THEN
    v_invoice := 'PUR-' || to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  END IF;

  INSERT INTO public.purchases(supplier_id, invoice_number, invoice_date, notes, status, total)
  VALUES(p_supplier_id, v_invoice, COALESCE(p_invoice_date,CURRENT_DATE), NULLIF(trim(COALESCE(p_notes,'')),''), 'received', 0)
  RETURNING id INTO v_purchase_id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    v_product_id := NULLIF(v_item->>'product_id','')::uuid;
    v_qty := COALESCE((v_item->>'quantity')::numeric,0);
    v_purchase_price := COALESCE((v_item->>'purchase_price')::numeric,0);
    v_sale_price := COALESCE((v_item->>'sale_price')::numeric,0);
    v_expiry := NULLIF(v_item->>'expiry_date','')::date;

    IF v_product_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.products WHERE id=v_product_id) THEN RAISE EXCEPTION 'Invalid product in purchase invoice'; END IF;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Purchase quantity must be greater than zero'; END IF;
    IF v_expiry IS NULL THEN RAISE EXCEPTION 'Expiry date is required for every purchase item'; END IF;
    IF v_purchase_price < 0 OR v_sale_price < 0 THEN RAISE EXCEPTION 'Prices cannot be negative'; END IF;

    INSERT INTO public.purchase_items(purchase_id, product_id, quantity, purchase_price, expiry_date, sale_price)
    VALUES(v_purchase_id, v_product_id, v_qty, v_purchase_price, v_expiry, v_sale_price)
    RETURNING id INTO v_item_id;

    v_batch_id := gen_random_uuid();
    INSERT INTO public.batches(id, product_id, batch_number, expiry_date, quantity, purchase_price, received_date, supplier_id, purchase_id, purchase_item_id)
    VALUES(v_batch_id, v_product_id, 'AUTO-' || substr(replace(v_item_id::text,'-',''),1,12), v_expiry, v_qty, v_purchase_price, COALESCE(p_invoice_date,CURRENT_DATE), p_supplier_id, v_purchase_id, v_item_id);

    UPDATE public.purchase_items SET batch_id=v_batch_id WHERE id=v_item_id;
    UPDATE public.products
      SET purchase_price=v_purchase_price,
          sale_price=CASE WHEN v_sale_price > 0 THEN v_sale_price ELSE sale_price END,
          updated_at=now()
    WHERE id=v_product_id;

    INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,note,created_by)
    VALUES(v_product_id,v_batch_id,'purchase',v_qty,'استلام فاتورة شراء '||v_invoice,auth.uid());

    v_total := v_total + (v_qty * v_purchase_price);
  END LOOP;

  UPDATE public.purchases SET total=v_total WHERE id=v_purchase_id;

  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'admin_create_purchase','purchase',v_purchase_id,jsonb_build_object('supplier_id',p_supplier_id,'invoice_number',v_invoice,'total',v_total,'items_count',jsonb_array_length(p_items)));

  RETURN jsonb_build_object('id',v_purchase_id,'public_code',v_invoice,'total',v_total);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_create_purchase(uuid,text,date,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_purchase(uuid,text,date,text,jsonb) TO authenticated;

-- Purchase list.
CREATE OR REPLACE FUNCTION public.admin_list_purchases()
RETURNS TABLE(id uuid, supplier_id uuid, supplier_name text, invoice_number text, invoice_date date, total numeric, status text, notes text, created_at timestamptz, item_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
  SELECT p.id,p.supplier_id,s.name,p.invoice_number,p.invoice_date,p.total,p.status,p.notes,p.created_at,COUNT(pi.id)::bigint
  FROM public.purchases p
  LEFT JOIN public.suppliers s ON s.id=p.supplier_id
  LEFT JOIN public.purchase_items pi ON pi.purchase_id=p.id
  WHERE public.is_admin()
  GROUP BY p.id,s.name
  ORDER BY COALESCE(p.invoice_date,p.created_at::date) DESC,p.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.admin_list_purchases() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_purchases() TO authenticated;

-- Purchase detail including exact batch created by receipt.
CREATE OR REPLACE FUNCTION public.admin_get_purchase_detail(p_purchase_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
DECLARE v jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
  SELECT jsonb_build_object(
    'id',p.id,'supplier_id',p.supplier_id,'supplier_name',s.name,'invoice_number',p.invoice_number,
    'invoice_date',p.invoice_date,'total',p.total,'status',p.status,'notes',p.notes,'created_at',p.created_at,
    'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',pi.id,'product_id',pi.product_id,'product_name',pr.name,'barcode',pr.barcode,
      'quantity',pi.quantity,'purchase_price',pi.purchase_price,'sale_price',pi.sale_price,
      'expiry_date',pi.expiry_date,'batch_id',pi.batch_id
    ) ORDER BY pi.id) FROM public.purchase_items pi JOIN public.products pr ON pr.id=pi.product_id WHERE pi.purchase_id=p.id),'[]'::jsonb)
  ) INTO v
  FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id
  WHERE p.id=p_purchase_id;
  RETURN v;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_get_purchase_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_purchase_detail(uuid) TO authenticated;

-- Supplier purchase history.
CREATE OR REPLACE FUNCTION public.admin_supplier_purchase_history(p_supplier_id uuid)
RETURNS TABLE(id uuid, invoice_number text, invoice_date date, total numeric, status text, created_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
  SELECT p.id,p.invoice_number,p.invoice_date,p.total,p.status,p.created_at
  FROM public.purchases p
  WHERE public.is_admin() AND p.supplier_id=p_supplier_id
  ORDER BY COALESCE(p.invoice_date,p.created_at::date) DESC,p.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.admin_supplier_purchase_history(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_supplier_purchase_history(uuid) TO authenticated;

-- Admin reads for traceability in inventory/card views.
CREATE OR REPLACE FUNCTION public.admin_batch_trace(p_batch_id uuid)
RETURNS TABLE(batch_id uuid, supplier_id uuid, supplier_name text, purchase_id uuid, invoice_number text, invoice_date date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth
AS $$
  SELECT b.id,b.supplier_id,s.name,b.purchase_id,p.invoice_number,p.invoice_date
  FROM public.batches b
  LEFT JOIN public.suppliers s ON s.id=b.supplier_id
  LEFT JOIN public.purchases p ON p.id=b.purchase_id
  WHERE public.is_admin() AND b.id=p_batch_id;
$$;
REVOKE ALL ON FUNCTION public.admin_batch_trace(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_batch_trace(uuid) TO authenticated;

COMMIT;
