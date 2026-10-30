SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90s';

CREATE TEMP TABLE ab_supplier_advance_guard(table_name text PRIMARY KEY,row_count bigint,fingerprint text) ON COMMIT DROP;
DO $guard$
DECLARE r record;v_count bigint;v_hash text;
BEGIN
 FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='public' LOOP
  EXECUTE format('SELECT count(*),md5(COALESCE(string_agg(h,''''
   ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(t)::text) h FROM public.%I t)x',r.tablename) INTO v_count,v_hash;
  INSERT INTO ab_supplier_advance_guard VALUES(r.tablename,v_count,v_hash);
 END LOOP;
END $guard$;

-- Additive only. No historical payment, invoice or inventory rows are rewritten.
CREATE TABLE public.supplier_advance_lots(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),supplier_id uuid NOT NULL REFERENCES public.suppliers(id) ON DELETE RESTRICT,
 origin_purchase_id uuid REFERENCES public.purchases(id) ON DELETE RESTRICT,
 payment_id uuid NOT NULL UNIQUE REFERENCES public.supplier_payments(id) ON DELETE RESTRICT,
 currency text NOT NULL CHECK(currency IN ('USD','SYP')),amount numeric NOT NULL CHECK(amount>0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
 created_at timestamptz NOT NULL DEFAULT now(),created_by uuid NOT NULL);
CREATE INDEX supplier_advance_lots_supplier_currency ON public.supplier_advance_lots(supplier_id,currency,created_at,id);
CREATE TABLE public.supplier_advance_applications(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),lot_id uuid NOT NULL REFERENCES public.supplier_advance_lots(id) ON DELETE RESTRICT,
 purchase_id uuid NOT NULL REFERENCES public.purchases(id) ON DELETE RESTRICT,
 amount numeric NOT NULL CHECK(amount>0 AND amount::text NOT IN ('NaN','Infinity','-Infinity')),
 created_at timestamptz NOT NULL DEFAULT now(),created_by uuid NOT NULL);
CREATE INDEX supplier_advance_applications_lot ON public.supplier_advance_applications(lot_id);
CREATE INDEX supplier_advance_applications_purchase ON public.supplier_advance_applications(purchase_id);
CREATE TABLE public.supplier_purchase_requests(
 request_id uuid PRIMARY KEY,purchase_id uuid REFERENCES public.purchases(id) ON DELETE SET NULL,
 payload_hash text NOT NULL,result jsonb NOT NULL,created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE public.supplier_advance_lots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_advance_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_purchase_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.supplier_advance_lots,public.supplier_advance_applications,public.supplier_purchase_requests FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.supplier_advance_lots,public.supplier_advance_applications TO authenticated;
CREATE POLICY supplier_advance_lots_admin_read ON public.supplier_advance_lots FOR SELECT TO authenticated USING(public.is_admin());
CREATE POLICY supplier_advance_applications_admin_read ON public.supplier_advance_applications FOR SELECT TO authenticated USING(public.is_admin());

CREATE FUNCTION public.supplier_advance_remaining_v1(p_lot_id uuid) RETURNS numeric LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT l.amount-coalesce((SELECT sum(a.amount) FROM public.supplier_advance_applications a WHERE a.lot_id=l.id),0)
 FROM public.supplier_advance_lots l WHERE l.id=p_lot_id
$$;
REVOKE ALL ON FUNCTION public.supplier_advance_remaining_v1(uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.admin_supplier_advance_summary_v1(p_supplier_id uuid,p_currency text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_amount numeric;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.is_admin(),false) THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_currency IS NULL OR p_currency NOT IN ('USD','SYP') THEN RAISE EXCEPTION 'عملة غير صالحة'; END IF;
 SELECT coalesce(sum(public.supplier_advance_remaining_v1(l.id)),0) INTO v_amount FROM public.supplier_advance_lots l
 WHERE l.supplier_id=p_supplier_id AND l.currency=p_currency;
 RETURN jsonb_build_object('supplier_id',p_supplier_id,'currency',p_currency,'advance_credit',v_amount);
END $$;
REVOKE ALL ON FUNCTION public.admin_supplier_advance_summary_v1(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admin_supplier_advance_summary_v1(uuid,text) TO authenticated;

CREATE FUNCTION public.apply_supplier_advances_to_purchase_v1(p_purchase_id uuid) RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_supplier uuid;v_currency text;v_due numeric;v_available numeric;v_part numeric;v_used numeric:=0;r record;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.is_admin(),false) THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT supplier_id,currency INTO v_supplier,v_currency FROM public.purchases WHERE id=p_purchase_id;
 IF NOT FOUND OR v_supplier IS NULL THEN RAISE EXCEPTION 'فاتورة المورد غير موجودة'; END IF;
 PERFORM 1 FROM public.suppliers WHERE id=v_supplier FOR UPDATE;
 SELECT due_amount INTO v_due FROM public.purchases WHERE id=p_purchase_id FOR UPDATE;
 FOR r IN SELECT l.id,l.payment_id,sp.fx_rate FROM public.supplier_advance_lots l
  JOIN public.supplier_payments sp ON sp.id=l.payment_id WHERE l.supplier_id=v_supplier AND l.currency=v_currency
  ORDER BY l.created_at,l.id FOR UPDATE OF l
 LOOP
  EXIT WHEN v_due<=0;
  v_available:=public.supplier_advance_remaining_v1(r.id);v_part:=least(v_due,v_available);
  IF v_part<=0 THEN CONTINUE; END IF;
  INSERT INTO public.supplier_payment_allocations(payment_id,purchase_id,amount,currency,fx_rate,amount_syp)
  VALUES(r.payment_id,p_purchase_id,v_part,v_currency,r.fx_rate,CASE WHEN v_currency='USD' THEN round(v_part*r.fx_rate,2) ELSE v_part END)
  ON CONFLICT(payment_id,purchase_id) DO UPDATE SET amount=public.supplier_payment_allocations.amount+excluded.amount,
   amount_syp=CASE WHEN v_currency='USD' THEN round((public.supplier_payment_allocations.amount+excluded.amount)*r.fx_rate,2) ELSE public.supplier_payment_allocations.amount+excluded.amount END;
  INSERT INTO public.supplier_advance_applications(lot_id,purchase_id,amount,created_by) VALUES(r.id,p_purchase_id,v_part,auth.uid());
  PERFORM public.admin_refresh_purchase_balance(p_purchase_id);
  v_used:=v_used+v_part;v_due:=v_due-v_part;
 END LOOP;
 IF v_used>0 THEN INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'supplier_advance_applied','purchase',p_purchase_id,jsonb_build_object('supplier_id',v_supplier,'currency',v_currency,'amount',v_used,'cash_movement',false)); END IF;
 RETURN v_used;
END $$;
REVOKE ALL ON FUNCTION public.apply_supplier_advances_to_purchase_v1(uuid) FROM PUBLIC,anon,authenticated;

DO $guard$
DECLARE r record;v_count bigint;v_hash text;
BEGIN
 FOR r IN SELECT * FROM ab_supplier_advance_guard LOOP
  EXECUTE format('SELECT count(*),md5(COALESCE(string_agg(h,''''
   ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(t)::text) h FROM public.%I t)x',r.table_name) INTO v_count,v_hash;
  IF v_count IS DISTINCT FROM r.row_count OR v_hash IS DISTINCT FROM r.fingerprint THEN RAISE EXCEPTION 'Data preservation guard failed for %; migration aborted',r.table_name; END IF;
 END LOOP;
END $guard$;

NOTIFY pgrst,'reload schema';

