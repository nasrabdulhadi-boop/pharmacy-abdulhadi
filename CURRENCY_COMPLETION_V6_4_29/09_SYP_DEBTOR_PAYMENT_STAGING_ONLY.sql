-- PHARMACY ABDULHADI / STAGE 3 / FUNCTION CODE / NOT EXECUTED
-- For review on a *staging* copy ONLY. Never run blindly on production.
-- Safeguards: no DROP/TRUNCATE/DELETE; no INSERT/UPDATE except when a user calls
-- the created business functions. Running CREATE OR REPLACE changes definitions.
-- All amounts for existing customer debt payments remain SYP only.
-- Requires public.is_admin(), audit_logs, debtor_transactions and cashbox_entries.
BEGIN;

CREATE OR REPLACE FUNCTION public.admin_record_debtor_payment(
  p_debtor_id uuid,
  p_amount numeric,
  p_notes text DEFAULT NULL::text,
  p_payment_method text DEFAULT 'cash'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','auth'
AS $function$
DECLARE
  v_balance numeric;
  v_tx uuid;
  v_name text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin authorization required';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'مبلغ الدفعة يجب أن يكون أكبر من صفر';
  END IF;
  IF p_payment_method NOT IN ('cash','other') THEN
    RAISE EXCEPTION 'طريقة الدفع غير صالحة';
  END IF;

  -- The existing receivables ledger is SYP-denominated. Prevent mixed currencies
  -- from silently entering a single debtor balance until full USD debtor migration.
  IF EXISTS (
    SELECT 1 FROM public.debtor_transactions t
    WHERE t.debtor_id=p_debtor_id AND t.currency <> 'SYP'
  ) THEN
    RAISE EXCEPTION 'لا يمكن قبض دين متعدد العملات عبر دالة تحصيل الليرة';
  END IF;

  SELECT d.name,
         COALESCE((SELECT SUM(t.debit-t.credit)
                   FROM public.debtor_transactions t
                   WHERE t.debtor_id=d.id),0)
    INTO v_name,v_balance
  FROM public.debtors d
  WHERE d.id=p_debtor_id
  FOR UPDATE OF d;
  IF NOT FOUND THEN RAISE EXCEPTION 'المتدين غير موجود'; END IF;
  IF p_amount > v_balance THEN
    RAISE EXCEPTION 'الدفعة أكبر من الدين الحالي';
  END IF;

  INSERT INTO public.debtor_transactions
    (debtor_id,transaction_type,amount,debit,credit,payment_method,notes,
     created_by,currency,fx_rate,amount_syp)
  VALUES
    (p_debtor_id,'payment',p_amount,0,p_amount,p_payment_method,p_notes,
     auth.uid(),'SYP',1,p_amount)
  RETURNING id INTO v_tx;

  IF p_payment_method='cash' THEN
    INSERT INTO public.cashbox_entries
      (entry_type,amount,description,debtor_transaction_id,created_by,
       currency,fx_rate,amount_syp)
    VALUES
      ('debtor_payment',p_amount,'تحصيل دفعة من المتدين: '||v_name,v_tx,
       auth.uid(),'SYP',1,p_amount);
  END IF;

  INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
  VALUES(auth.uid(),'debtor_payment','debtor',p_debtor_id,
         jsonb_build_object('name',v_name,'amount',p_amount,'currency','SYP',
                            'payment_method',p_payment_method,'notes',p_notes,
                            'previous_balance',v_balance,'new_balance',v_balance-p_amount));

  RETURN jsonb_build_object('transaction_id',v_tx,
                            'previous_balance',v_balance,
                            'new_balance',v_balance-p_amount,
                            'currency','SYP');
END;
$function$;

COMMIT;
