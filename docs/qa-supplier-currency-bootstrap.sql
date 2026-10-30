-- QA ONLY. Private schema, synthetic data; no production data copied.
CREATE SCHEMA IF NOT EXISTS supplier_currency_qa;
REVOKE ALL ON SCHEMA supplier_currency_qa FROM PUBLIC,anon,authenticated;
CREATE TABLE supplier_currency_qa.suppliers(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),name text NOT NULL,phone text,address text);
CREATE TABLE supplier_currency_qa.purchases(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),supplier_id uuid REFERENCES supplier_currency_qa.suppliers,
 invoice_number text,invoice_date date DEFAULT current_date,created_at timestamptz DEFAULT now(),
 total numeric(14,2) NOT NULL CHECK(total>=0),paid_amount numeric NOT NULL DEFAULT 0,
 due_amount numeric NOT NULL,credit_amount numeric NOT NULL DEFAULT 0,payment_status text DEFAULT 'unpaid',
 currency text NOT NULL CHECK(currency IN ('USD','SYP')),fx_rate numeric NOT NULL DEFAULT 1,
 total_syp numeric,notes text);
CREATE TABLE supplier_currency_qa.supplier_payments(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),supplier_id uuid NOT NULL REFERENCES supplier_currency_qa.suppliers,
 amount numeric NOT NULL CHECK(amount>0),currency text NOT NULL CHECK(currency IN ('USD','SYP')),
 fx_rate numeric NOT NULL CHECK(fx_rate>0),amount_syp numeric,payment_method text NOT NULL,
 notes text,created_by uuid,created_at timestamptz NOT NULL DEFAULT now(),cashbox_entry_id uuid);
CREATE TABLE supplier_currency_qa.supplier_payment_allocations(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),payment_id uuid NOT NULL REFERENCES supplier_currency_qa.supplier_payments,
 purchase_id uuid NOT NULL REFERENCES supplier_currency_qa.purchases,amount numeric NOT NULL CHECK(amount>0),
 currency text NOT NULL,fx_rate numeric NOT NULL CHECK(fx_rate>0),amount_syp numeric,
 created_at timestamptz DEFAULT now(),UNIQUE(payment_id,purchase_id));
CREATE TABLE supplier_currency_qa.cashbox_entries(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),entry_type text NOT NULL,
 amount numeric NOT NULL CHECK(amount<>0),currency text NOT NULL CHECK(currency IN ('USD','SYP')),
 fx_rate numeric NOT NULL CHECK(fx_rate>0),amount_syp numeric,description text,
 purchase_id uuid REFERENCES supplier_currency_qa.purchases,
 supplier_payment_id uuid REFERENCES supplier_currency_qa.supplier_payments,
 created_by uuid,created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE supplier_currency_qa.supplier_payments ADD FOREIGN KEY(cashbox_entry_id) REFERENCES supplier_currency_qa.cashbox_entries;
CREATE TABLE supplier_currency_qa.audit_logs(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid,
 action text NOT NULL,entity_type text,entity_id uuid,details jsonb,created_at timestamptz DEFAULT now());
ALTER TABLE supplier_currency_qa.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_currency_qa.purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_currency_qa.supplier_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_currency_qa.supplier_payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_currency_qa.cashbox_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_currency_qa.audit_logs ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION supplier_currency_qa.admin_refresh_purchase_balance(p_purchase_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_paid numeric;
BEGIN
 IF NOT coalesce(public.is_admin(),false) THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT coalesce(sum(amount),0) INTO v_paid FROM supplier_currency_qa.supplier_payment_allocations WHERE purchase_id=p_purchase_id;
 UPDATE supplier_currency_qa.purchases SET paid_amount=v_paid,due_amount=greatest(total-v_paid-credit_amount,0),
 payment_status=CASE WHEN v_paid+credit_amount>=total THEN 'paid' WHEN v_paid+credit_amount>0 THEN 'partial' ELSE 'unpaid' END WHERE id=p_purchase_id;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA supplier_currency_qa FROM PUBLIC,anon,authenticated;
INSERT INTO supplier_currency_qa.suppliers(id,name) VALUES('11111111-1111-4111-8111-111111111111','مورد تجريبي — بيانات وهمية');
INSERT INTO supplier_currency_qa.purchases(supplier_id,invoice_number,total,due_amount,currency,fx_rate,total_syp)
 VALUES('11111111-1111-4111-8111-111111111111','QA-USD-1',100,100,'USD',140,14000),
 ('11111111-1111-4111-8111-111111111111','QA-USD-2',50,50,'USD',140,7000),
 ('11111111-1111-4111-8111-111111111111','QA-SYP-1',14000,14000,'SYP',1,14000);
