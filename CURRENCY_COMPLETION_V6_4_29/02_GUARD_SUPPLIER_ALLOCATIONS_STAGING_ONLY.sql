-- Review and run on staging ONLY after 01_SCHEMA_REVIEW_ONLY.sql.
-- Replaces only the known existing trigger function. Historic rows untouched.
-- Enforces payment supplier, payment/invoice currency agreement and both amount limits.
BEGIN;
CREATE OR REPLACE FUNCTION public.validate_supplier_payment_allocation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','auth'
AS $fn$
DECLARE v_supplier uuid; v_purchase_supplier uuid; v_invoice_currency text;
        v_payment_currency text; v_invoice_total numeric; v_payment_total numeric;
        v_already_invoice numeric; v_already_payment numeric; v_payment_fx numeric;
BEGIN
  SELECT supplier_id, currency, amount, fx_rate INTO v_supplier,v_payment_currency,v_payment_total,v_payment_fx
    FROM public.supplier_payments WHERE id=NEW.payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'دفعة المورد غير موجودة'; END IF;
  SELECT supplier_id,currency,total INTO v_purchase_supplier,v_invoice_currency,v_invoice_total
    FROM public.purchases WHERE id=NEW.purchase_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة الشراء غير موجودة'; END IF;
  IF v_supplier IS DISTINCT FROM v_purchase_supplier THEN
    RAISE EXCEPTION 'لا يمكن تخصيص دفعة لمورد مختلف'; END IF;
  IF v_payment_currency IS DISTINCT FROM v_invoice_currency THEN
    RAISE EXCEPTION 'لا يمكن تخصيص دفعة بعملة مختلفة عن عملة الفاتورة'; END IF;
  IF NEW.currency IS DISTINCT FROM v_invoice_currency THEN
    RAISE EXCEPTION 'عملة التوزيع لا تطابق عملة الفاتورة'; END IF;
  IF NEW.amount IS NULL OR NEW.amount<=0 THEN RAISE EXCEPTION 'مبلغ التوزيع غير صالح'; END IF;
  IF NEW.fx_rate IS DISTINCT FROM v_payment_fx THEN
    RAISE EXCEPTION 'سعر صرف التخصيص لا يطابق سعر صرف الدفعة'; END IF;
  IF v_payment_currency='USD' AND
     (NEW.amount_syp IS NULL OR NEW.amount_syp IS DISTINCT FROM ROUND(NEW.amount*v_payment_fx,2)) THEN
    RAISE EXCEPTION 'قيمة تحويل تخصيص الدولار إلى الليرة غير صحيحة'; END IF;
  IF v_payment_currency='SYP' AND NEW.amount_syp IS NOT NULL AND
     NEW.amount_syp IS DISTINCT FROM NEW.amount THEN
    RAISE EXCEPTION 'تخصيص الليرة يحتوي مقابلاً غير مطابق بالليرة'; END IF;

  SELECT COALESCE(SUM(amount),0) INTO v_already_invoice
    FROM public.supplier_payment_allocations
    WHERE purchase_id=NEW.purchase_id AND id IS DISTINCT FROM NEW.id;
  SELECT COALESCE(SUM(amount),0) INTO v_already_payment
    FROM public.supplier_payment_allocations
    WHERE payment_id=NEW.payment_id AND id IS DISTINCT FROM NEW.id;
  IF v_already_invoice+NEW.amount>v_invoice_total+0.0000001 THEN
    RAISE EXCEPTION 'التوزيع يتجاوز قيمة الفاتورة'; END IF;
  IF v_already_payment+NEW.amount>v_payment_total+0.0000001 THEN
    RAISE EXCEPTION 'التوزيع يتجاوز قيمة الدفعة'; END IF;
  RETURN NEW;
END;
$fn$;
-- The historic allocation trigger fires on INSERT and UPDATE of amount, payment and
-- purchase IDs. Cover direct changes to metadata without dropping the old trigger.
DO $guard$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.supplier_payment_allocations'::regclass
   AND tgname='trg_ab_allocation_metadata_guard_v1' AND NOT tgisinternal) THEN
   CREATE TRIGGER trg_ab_allocation_metadata_guard_v1
    BEFORE UPDATE OF currency, fx_rate, amount_syp ON public.supplier_payment_allocations
    FOR EACH ROW EXECUTE FUNCTION public.validate_supplier_payment_allocation();
 END IF;
END;
$guard$;
COMMIT;
