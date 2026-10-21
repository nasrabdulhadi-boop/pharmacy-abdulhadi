-- Do not silently record a USD supplier refund as SYP through the legacy return RPC.
-- This temporary guard preserves data correctness until the USD supplier credit-note workflow is implemented.
-- STAGING ONLY. Existing return data unchanged.
BEGIN;
CREATE OR REPLACE FUNCTION public.guard_usd_supplier_return_currency_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v_invoice_currency text;
BEGIN
 IF NEW.return_type='supplier' AND NEW.purchase_id IS NOT NULL THEN
  SELECT currency INTO v_invoice_currency FROM public.purchases WHERE id=NEW.purchase_id;
  IF v_invoice_currency='USD' THEN
   RAISE EXCEPTION 'مرتجع مورد بالدولار غير مفعّل حالياً: يجب تسجيل إشعار دائن بالدولار أولاً، ولم يتم تغيير المخزون';
  END IF;
 END IF;
 RETURN NEW;
END;
$fn$;
DO $guard$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='trg_guard_usd_supplier_return_currency_v1'
  AND tgrelid='public.returns'::regclass) THEN
 CREATE TRIGGER trg_guard_usd_supplier_return_currency_v1
 BEFORE INSERT ON public.returns FOR EACH ROW
 EXECUTE FUNCTION public.guard_usd_supplier_return_currency_v1();
 END IF;
END;
$guard$;
COMMIT;
