-- QA-only draft. Do not deploy to production until verified on an isolated schema-equivalent QA database.
-- Complements existing application audit entries, which may remain present for the same action.
-- Records field-level before/after for updates and delete snapshots, excluding sensitive customer details.
CREATE OR REPLACE FUNCTION public.ab_daily_change_audit_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $fn$
DECLARE old_data jsonb; new_data jsonb; changed_old jsonb:='{}'::jsonb; changed_new jsonb:='{}'::jsonb; k text; actor uuid;
BEGIN
 actor:=auth.uid();
 IF TG_OP='INSERT' THEN RETURN NEW; END IF;
 old_data:=to_jsonb(OLD)-'phone'-'address'-'notes'-'file_path'-'file_name'-'customer_phone'-'customer_name'-'payment_notes'-'updated_at'-'public_code'-'email'-'password'-'token';
 -- Exclude automatic updated_at churn and personal identifiers from snapshots.
 IF TG_OP='UPDATE' THEN
   new_data:=to_jsonb(NEW)-'phone'-'address'-'notes'-'file_path'-'file_name'-'customer_phone'-'customer_name'-'payment_notes'-'updated_at'-'public_code'-'email'-'password'-'token';
   FOR k IN SELECT jsonb_object_keys(old_data) LOOP
     IF old_data->k IS DISTINCT FROM new_data->k THEN
       changed_old:=changed_old||jsonb_build_object(k,old_data->k);
       changed_new:=changed_new||jsonb_build_object(k,new_data->k);
     END IF;
   END LOOP;
   IF changed_old='{}'::jsonb THEN RETURN NEW; END IF;
 ELSE
   changed_old:=old_data;
 END IF;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details,created_at)
 VALUES(actor,lower(TG_OP),TG_TABLE_NAME,OLD.id,
   jsonb_build_object('source','daily_change_audit_v1','operation',lower(TG_OP),'before',changed_old,'after',changed_new),clock_timestamp());
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION public.ab_daily_change_audit_v1() FROM PUBLIC;
-- Triggers fire under existing table write permissions; no new client-write access is granted.
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.products;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.products
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.sales;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.sales
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.sale_items;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.sale_items
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.purchases;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.purchases
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.purchase_items;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.purchase_items
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.batches;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.batches
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.returns;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.returns
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.cashbox_entries;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.cashbox_entries
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.supplier_payments;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.supplier_payments
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.debtor_transactions;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.debtor_transactions
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.stock_movements;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.stock_movements
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.inventory_counts;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.inventory_counts
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.inventory_count_items;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.inventory_count_items
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.orders;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.prescriptions;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.prescriptions
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.medicine_requests;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.medicine_requests
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.suppliers;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.suppliers
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
DROP TRIGGER IF EXISTS ab_daily_change_audit_v1 ON public.debtors;
CREATE TRIGGER ab_daily_change_audit_v1 AFTER UPDATE OR DELETE ON public.debtors
FOR EACH ROW EXECUTE FUNCTION public.ab_daily_change_audit_v1();
