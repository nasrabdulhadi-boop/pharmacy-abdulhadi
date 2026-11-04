-- QA first. Apply to production only after review and backup.
-- Persistent invoice numbering, never reuses a number after deletion.
CREATE SEQUENCE IF NOT EXISTS public.sale_invoice_number_seq START 1;
CREATE TABLE IF NOT EXISTS public.sale_invoice_numbers (
 sale_id uuid PRIMARY KEY,
 invoice_no bigint NOT NULL UNIQUE DEFAULT nextval('public.sale_invoice_number_seq'),
 assigned_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON public.sale_invoice_numbers FROM anon,authenticated;
CREATE OR REPLACE FUNCTION public.ab_assign_sale_invoice_number_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $fn$
BEGIN
 INSERT INTO public.sale_invoice_numbers(sale_id) VALUES(NEW.id)
 ON CONFLICT(sale_id) DO NOTHING;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION public.ab_assign_sale_invoice_number_v1() FROM PUBLIC;
-- Historical backfill must be executed once in chronological order, before enabling the trigger.
DO $backfill$
DECLARE x record;
BEGIN
 PERFORM pg_advisory_xact_lock(84117921);
 FOR x IN SELECT id FROM public.sales ORDER BY created_at,id LOOP
   INSERT INTO public.sale_invoice_numbers(sale_id) VALUES(x.id) ON CONFLICT DO NOTHING;
 END LOOP;
END;$backfill$;
DROP TRIGGER IF EXISTS ab_assign_sale_invoice_number_v1 ON public.sales;
CREATE TRIGGER ab_assign_sale_invoice_number_v1 AFTER INSERT ON public.sales
FOR EACH ROW EXECUTE FUNCTION public.ab_assign_sale_invoice_number_v1();
CREATE OR REPLACE FUNCTION public.admin_get_sale_invoice_number_v1(p_sale_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $fn$
DECLARE v_no bigint;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT invoice_no INTO v_no FROM public.sale_invoice_numbers WHERE sale_id=p_sale_id;
 RETURN CASE WHEN v_no IS NULL THEN NULL ELSE lpad(v_no::text,2,'0') END;
END;$fn$;
REVOKE ALL ON FUNCTION public.admin_get_sale_invoice_number_v1(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_sale_invoice_number_v1(uuid) TO authenticated;
