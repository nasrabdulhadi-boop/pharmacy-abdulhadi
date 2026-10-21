-- صيدلية عبدالهادي — تصحيح دوال الصندوق اليدوي فقط (غير منفذ)
-- إضافة حقول SYP بوضوح إلى الحركات اليدوية الجديدة، دون تغيير أي سجل سابق.
-- Version: currency-stage2 / 2026-10-20
-- NOTICE: Apply only after reviewing on staging. This script has not been run on production.
-- This patch includes ONLY CREATE OR REPLACE FUNCTION; no destructive DDL or data updates.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_cashbox_entry(
  p_type text, p_amount numeric, p_description text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','auth'
AS $function$
DECLARE v_id uuid; v_amount numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_amount IS NULL OR p_amount=0 THEN RAISE EXCEPTION 'المبلغ لا يمكن أن يكون صفراً'; END IF;
 IF p_type NOT IN ('expense','income','withdrawal','deposit','adjustment') THEN RAISE EXCEPTION 'نوع حركة صندوق غير صالح'; END IF;
 v_amount:=CASE WHEN p_type IN ('expense','withdrawal') THEN -abs(p_amount) ELSE abs(p_amount) END;
 INSERT INTO public.cashbox_entries(entry_type,amount,description,created_by,currency,fx_rate,amount_syp)
 VALUES(p_type,v_amount,p_description,auth.uid(),'SYP',1,v_amount) RETURNING id INTO v_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'cashbox_entry','cashbox',v_id,
 jsonb_build_object('type',p_type,'amount',p_amount,'signed_amount',v_amount,'currency','SYP','description',p_description));
 RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_cashbox_manual_entry(
  p_type text, p_amount numeric, p_description text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','auth'
AS $function$
DECLARE v_id uuid; v_amount numeric;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_type NOT IN ('expense','income','withdrawal','deposit','adjustment') THEN RAISE EXCEPTION 'نوع حركة صندوق غير صالح'; END IF;
 IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر'; END IF;
 v_amount:=CASE WHEN p_type IN ('expense','withdrawal') THEN -abs(p_amount) ELSE abs(p_amount) END;
 INSERT INTO public.cashbox_entries(entry_type,amount,description,created_by,currency,fx_rate,amount_syp)
 VALUES(p_type,v_amount,NULLIF(trim(COALESCE(p_description,'')),''),auth.uid(),'SYP',1,v_amount)
 RETURNING id INTO v_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'cashbox_entry','cashbox',v_id,
 jsonb_build_object('type',p_type,'amount',abs(p_amount),'signed_amount',v_amount,'currency','SYP','description',p_description));
 RETURN jsonb_build_object('id',v_id,'type',p_type,'amount',v_amount);
END;
$function$;

COMMIT;
