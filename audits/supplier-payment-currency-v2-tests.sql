-- Run only on isolated QA. All test changes roll back.
BEGIN;
DO $$
DECLARE
 v_admin uuid;v_session uuid;v_req uuid:=gen_random_uuid();v_result jsonb;v_repeat jsonb;
 v_supplier uuid:='11111111-1111-4111-8111-111111111111';v_n integer;v_failed boolean;v_before numeric;
 v_claims text;v_invoice uuid;
BEGIN
 SELECT u.id,s.id INTO v_admin,v_session FROM auth.users u JOIN auth.sessions s ON s.user_id=u.id
 WHERE u.raw_app_meta_data->>'system_role'='system_admin' AND (s.not_after IS NULL OR s.not_after>now())
 ORDER BY s.created_at DESC LIMIT 1;
 IF v_admin IS NULL THEN RAISE EXCEPTION 'QA test needs an existing admin session'; END IF;
 v_claims:=jsonb_build_object('sub',v_admin,'session_id',v_session,'role','authenticated')::text;
 PERFORM set_config('request.jwt.claims',v_claims,true);
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'QA admin assertion failed'; END IF;
 SELECT id INTO v_invoice FROM supplier_currency_qa.purchases WHERE invoice_number='QA-USD-1';
 v_result:=public.qa_supplier_payment_currency_v2(v_supplier,10,'USD','USD',140,v_req,v_invoice,'cash','رقم وصل الاستلام: QA-1');
 v_repeat:=public.qa_supplier_payment_currency_v2(v_supplier,10,'USD','USD',140,v_req,v_invoice,'cash','رقم وصل الاستلام: QA-1');
 IF (v_repeat->>'duplicate')::boolean IS DISTINCT FROM true OR v_repeat->>'payment_id'<>v_result->>'payment_id' THEN RAISE EXCEPTION 'Retry duplicated payment'; END IF;
 PERFORM public.qa_supplier_payment_currency_v2(v_supplier,1400,'USD','SYP',140,gen_random_uuid(),NULL,'cash','رقم وصل الاستلام: QA-2');
 PERFORM public.qa_supplier_payment_currency_v2(v_supplier,10,'SYP','USD',140,gen_random_uuid(),NULL,'cash','رقم وصل الاستلام: QA-3');
 PERFORM public.qa_supplier_payment_currency_v2(v_supplier,140,'SYP','SYP',140,gen_random_uuid(),NULL,'cash','رقم وصل الاستلام: QA-4');
 IF (SELECT sum(due_amount) FROM supplier_currency_qa.purchases WHERE currency='USD')<>130 THEN RAISE EXCEPTION 'USD debt incorrect'; END IF;
 IF (SELECT sum(due_amount) FROM supplier_currency_qa.purchases WHERE currency='SYP')<>12460 THEN RAISE EXCEPTION 'SYP debt incorrect'; END IF;
 IF (SELECT sum(amount) FROM supplier_currency_qa.cashbox_entries WHERE currency='USD')<>-20 THEN RAISE EXCEPTION 'USD cash incorrect'; END IF;
 IF (SELECT sum(amount) FROM supplier_currency_qa.cashbox_entries WHERE currency='SYP')<>-1540 THEN RAISE EXCEPTION 'SYP cash incorrect'; END IF;
 IF (SELECT sum(amount_syp) FROM supplier_currency_qa.cashbox_entries)<>-4340 THEN RAISE EXCEPTION 'Cash report incorrect'; END IF;
 PERFORM public.qa_supplier_payment_currency_v2(v_supplier,5,'USD','USD',150,gen_random_uuid(),NULL,'other','رقم وصل الاستلام: QA-5');
 IF (SELECT count(*) FROM supplier_currency_qa.cashbox_entries)<>4 THEN RAISE EXCEPTION 'Noncash touched cashbox'; END IF;
 -- Allocation across oldest invoices: USD remaining now 125, spend 100.
 PERFORM public.qa_supplier_payment_currency_v2(v_supplier,14000,'USD','SYP',140,gen_random_uuid(),NULL,'cash','رقم وصل الاستلام: QA-6');
 IF (SELECT count(*) FROM supplier_currency_qa.supplier_payment_allocations WHERE payment_id=(SELECT id FROM supplier_currency_qa.supplier_payments WHERE notes='رقم وصل الاستلام: QA-6'))<>2 THEN RAISE EXCEPTION 'Oldest invoice allocation failed'; END IF;
 IF (SELECT sum(due_amount) FROM supplier_currency_qa.purchases WHERE currency='USD')<>25 THEN RAISE EXCEPTION 'Allocation debt mismatch'; END IF;
 -- Reject excess, missing receipt, bad rate, nonfinite, wrong supplier/invoice, changed retries.
 FOR v_n IN 1..8 LOOP
  v_failed:=false;
  BEGIN
   CASE v_n
    WHEN 1 THEN PERFORM public.qa_supplier_payment_currency_v2(v_supplier,99999,'USD','USD',140,gen_random_uuid(),NULL,'cash','رقم وصل الاستلام: BAD');
    WHEN 2 THEN PERFORM public.qa_supplier_payment_currency_v2(v_supplier,1,'USD','USD',140,gen_random_uuid(),NULL,'cash','');
    WHEN 3 THEN PERFORM public.qa_supplier_payment_currency_v2(v_supplier,1,'USD','SYP',0,gen_random_uuid(),NULL,'cash','رقم وصل الاستلام: BAD');
    WHEN 4 THEN PERFORM public.qa_supplier_payment_currency_v2(v_supplier,'NaN'::numeric,'USD','USD',140,gen_random_uuid(),NULL,'cash','رقم وصل الاستلام: BAD');
    WHEN 5 THEN PERFORM public.qa_supplier_payment_currency_v2(v_supplier,1,'SYP','USD',140,gen_random_uuid(),v_invoice,'cash','رقم وصل الاستلام: BAD');
    WHEN 6 THEN PERFORM public.qa_supplier_payment_currency_v2(v_supplier,11,'USD','USD',140,v_req,v_invoice,'cash','رقم وصل الاستلام: QA-1');
    WHEN 7 THEN PERFORM public.qa_supplier_payment_currency_v2(v_supplier,0.001,'USD','USD',140,gen_random_uuid(),NULL,'cash','رقم وصل الاستلام: BAD');
    WHEN 8 THEN PERFORM public.qa_supplier_payment_currency_v2(v_supplier,1,'EUR','USD',140,gen_random_uuid(),NULL,'cash','رقم وصل الاستلام: BAD');
   END CASE;
  EXCEPTION WHEN OTHERS THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Invalid case % accepted',v_n; END IF;
 END LOOP;
 IF (SELECT count(*) FROM supplier_currency_qa.supplier_payments)<>6 THEN RAISE EXCEPTION 'Invalid request wrote rows'; END IF;
 IF EXISTS(SELECT 1 FROM supplier_currency_qa.supplier_payments p WHERE amount<>(SELECT sum(amount) FROM supplier_currency_qa.supplier_payment_allocations a WHERE a.payment_id=p.id)) THEN RAISE EXCEPTION 'Allocation sum mismatch'; END IF;
 IF (SELECT jsonb_array_length(public.qa_supplier_currency_ledger_v2(v_supplier,'USD')->'payments'))<>4 THEN RAISE EXCEPTION 'Ledger missing payments'; END IF;
 -- Employee and missing/revoked sessions must fail despite forged admin JWT claims.
 FOR v_n IN 1..3 LOOP
  PERFORM set_config('request.jwt.claims',CASE WHEN v_n=1 THEN '{}' ELSE jsonb_build_object('sub',v_admin,'session_id',gen_random_uuid(),'role','authenticated','system_role','system_admin')::text END,true);
  IF v_n=3 THEN
   SELECT jsonb_build_object('sub',u.id,'session_id',s.id,'role','authenticated','system_role','system_admin')::text INTO v_claims
    FROM auth.users u JOIN auth.sessions s ON s.user_id=u.id WHERE u.raw_app_meta_data->>'system_role'='employee' LIMIT 1;
   PERFORM set_config('request.jwt.claims',v_claims,true);
  END IF;
  v_failed:=false;
  BEGIN PERFORM public.qa_supplier_payment_currency_v2(v_supplier,1,'USD','USD',140,gen_random_uuid(),NULL,'cash','رقم وصل الاستلام: DENIED'); EXCEPTION WHEN OTHERS THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Unauthorized payment accepted'; END IF;
  v_failed:=false;
  BEGIN PERFORM public.qa_supplier_currency_list_v2(); EXCEPTION WHEN OTHERS THEN v_failed:=true; END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Unauthorized ledger readable'; END IF;
 END LOOP;
END $$;
SELECT 'PASS: four currency combinations; invoice selection; oldest allocation; idempotency; 8 invalid cases; cash and ledger reconciliation; noncash; missing/revoked/employee sessions' test_result;
ROLLBACK;
