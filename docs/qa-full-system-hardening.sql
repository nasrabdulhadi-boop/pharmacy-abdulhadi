REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pharmacy_supplier_stage FROM PUBLIC,anon,authenticated;
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT p.oid::regprocedure signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='pharmacy_supplier_stage' AND p.proname IN ('validate_sale_quantity','sync_purchase_payment_state','fefo_batches','set_updated_at')
 LOOP EXECUTE format('ALTER FUNCTION %s SET search_path=pharmacy_supplier_stage,auth',r.signature); END LOOP;
END $$;
