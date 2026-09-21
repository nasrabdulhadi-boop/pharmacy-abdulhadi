-- Pharmacy Abdelhadi v5.6 — Barcode intake + accounting + debtors + cashbox + integrated reports + single-product count
BEGIN;

-- =========================
-- 1) Sales accounting fields
-- =========================
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_method text NOT NULL DEFAULT 'cash';
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS paid_amount numeric NOT NULL DEFAULT 0;
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS due_amount numeric NOT NULL DEFAULT 0;
ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS payment_notes text;

DO $$ BEGIN
  ALTER TABLE public.sales DROP CONSTRAINT IF EXISTS sales_payment_method_check;
  ALTER TABLE public.sales ADD CONSTRAINT sales_payment_method_check CHECK(payment_method IN ('cash','credit'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Existing historical sales are treated as cash because old versions had no payment method.
UPDATE public.sales SET payment_method='cash', paid_amount=COALESCE(total,0), due_amount=0 WHERE payment_method IS NULL OR (payment_method='cash' AND paid_amount=0 AND due_amount=0 AND COALESCE(total,0)>0);

-- =========================
-- 2) Debtors / receivables
-- =========================
CREATE TABLE IF NOT EXISTS public.debtors(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  phone text,
  address text,
  notes text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.debtors ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin debtors" ON public.debtors;
CREATE POLICY "admin debtors" ON public.debtors FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());

ALTER TABLE public.sales ADD COLUMN IF NOT EXISTS debtor_id uuid REFERENCES public.debtors(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_sales_payment_method_created ON public.sales(payment_method,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sales_debtor_created ON public.sales(debtor_id,created_at DESC);

CREATE TABLE IF NOT EXISTS public.debtor_transactions(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  debtor_id uuid NOT NULL REFERENCES public.debtors(id) ON DELETE CASCADE,
  transaction_type text NOT NULL CHECK(transaction_type IN ('sale','payment','adjustment')),
  sale_id uuid REFERENCES public.sales(id) ON DELETE SET NULL,
  amount numeric NOT NULL CHECK(amount>=0),
  debit numeric NOT NULL DEFAULT 0 CHECK(debit>=0),
  credit numeric NOT NULL DEFAULT 0 CHECK(credit>=0),
  payment_method text,
  notes text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK((debit>0 AND credit=0) OR (credit>0 AND debit=0) OR (debit=0 AND credit=0))
);
ALTER TABLE public.debtor_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin debtor transactions" ON public.debtor_transactions;
CREATE POLICY "admin debtor transactions" ON public.debtor_transactions FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());
CREATE INDEX IF NOT EXISTS idx_debtor_tx_debtor_created ON public.debtor_transactions(debtor_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_debtor_tx_created ON public.debtor_transactions(created_at DESC);

-- =========================
-- 3) Cashbox
-- =========================
CREATE TABLE IF NOT EXISTS public.cashbox_entries(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_type text NOT NULL CHECK(entry_type IN ('sale_cash','debtor_payment','expense','income','purchase_payment','withdrawal','deposit','adjustment')),
  amount numeric NOT NULL CHECK(amount<>0),
  description text,
  sale_id uuid REFERENCES public.sales(id) ON DELETE SET NULL,
  debtor_transaction_id uuid REFERENCES public.debtor_transactions(id) ON DELETE SET NULL,
  purchase_id uuid REFERENCES public.purchases(id) ON DELETE SET NULL,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.cashbox_entries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin cashbox" ON public.cashbox_entries;
CREATE POLICY "admin cashbox" ON public.cashbox_entries FOR ALL TO authenticated USING(public.is_admin()) WITH CHECK(public.is_admin());
CREATE INDEX IF NOT EXISTS idx_cashbox_created ON public.cashbox_entries(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cashbox_type_created ON public.cashbox_entries(entry_type,created_at DESC);

-- =========================
-- 4) Helpers / debtor list
-- =========================
CREATE OR REPLACE FUNCTION public.admin_create_debtor(p_name text,p_phone text DEFAULT NULL,p_address text DEFAULT NULL,p_notes text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_id uuid;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF NULLIF(trim(COALESCE(p_name,'')),'') IS NULL THEN RAISE EXCEPTION 'اسم المتدين مطلوب'; END IF;
 INSERT INTO public.debtors(name,phone,address,notes) VALUES(trim(p_name),NULLIF(trim(COALESCE(p_phone,'')),''),NULLIF(trim(COALESCE(p_address,'')),''),NULLIF(trim(COALESCE(p_notes,'')),'')) RETURNING id INTO v_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'admin_create_debtor','debtor',v_id,jsonb_build_object('name',trim(p_name),'phone',p_phone));
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.admin_create_debtor(text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_debtor(text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_debtors()
RETURNS TABLE(id uuid,name text,phone text,address text,notes text,created_at timestamptz,total_debt numeric,total_paid numeric,balance numeric,last_activity timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT d.id,d.name,d.phone,d.address,d.notes,d.created_at,
   COALESCE(SUM(t.debit),0),COALESCE(SUM(t.credit),0),COALESCE(SUM(t.debit-t.credit),0),MAX(t.created_at)
 FROM public.debtors d LEFT JOIN public.debtor_transactions t ON t.debtor_id=d.id
 WHERE public.is_admin() GROUP BY d.id ORDER BY COALESCE(SUM(t.debit-t.credit),0) DESC,d.name;
$$;
REVOKE ALL ON FUNCTION public.admin_list_debtors() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_debtors() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_search_debtors(p_query text DEFAULT NULL)
RETURNS TABLE(id uuid,name text,phone text,balance numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT d.id,d.name,d.phone,COALESCE(SUM(t.debit-t.credit),0)
 FROM public.debtors d LEFT JOIN public.debtor_transactions t ON t.debtor_id=d.id
 WHERE public.is_admin() AND (NULLIF(trim(COALESCE(p_query,'')),'') IS NULL OR (d.name||' '||COALESCE(d.phone,'')) ILIKE '%'||trim(p_query)||'%')
 GROUP BY d.id ORDER BY d.name LIMIT 30;
$$;
REVOKE ALL ON FUNCTION public.admin_search_debtors(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_debtors(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_debtor_ledger(p_debtor_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v jsonb;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object(
  'debtor',to_jsonb(d),
  'balance',COALESCE((SELECT SUM(debit-credit) FROM public.debtor_transactions WHERE debtor_id=d.id),0),
  'transactions',COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'id',t.id,'type',t.transaction_type,'sale_id',t.sale_id,'amount',t.amount,'debit',t.debit,'credit',t.credit,
    'payment_method',t.payment_method,'notes',t.notes,'created_at',t.created_at,'sale_total',s.total,
    'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',p.name,'quantity',si.quantity,'unit_price',si.unit_price,'unit_cost',si.unit_cost) ORDER BY p.name) FROM public.sale_items si JOIN public.products p ON p.id=si.product_id WHERE si.sale_id=t.sale_id),'[]'::jsonb)
  ) ORDER BY t.created_at DESC) FROM public.debtor_transactions t LEFT JOIN public.sales s ON s.id=t.sale_id WHERE t.debtor_id=d.id),'[]'::jsonb)
 ) INTO v FROM public.debtors d WHERE d.id=p_debtor_id;
 IF v IS NULL THEN RAISE EXCEPTION 'Debtor not found'; END IF;
 RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.admin_debtor_ledger(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_debtor_ledger(uuid) TO authenticated;

-- =========================
-- 5) Accounting sale: cash or credit
-- =========================
CREATE OR REPLACE FUNCTION public.complete_sale_accounting(
 p_items jsonb,
 p_discount numeric DEFAULT 0,
 p_payment_method text DEFAULT 'cash',
 p_debtor_id uuid DEFAULT NULL,
 p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE
 v_sale_id uuid:=gen_random_uuid(); it jsonb; b record; need numeric; take numeric; sub numeric:=0; total numeric; v_paid numeric:=0; v_due numeric:=0; v_debtor_name text;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 THEN RAISE EXCEPTION 'Sale must contain items'; END IF;
 IF p_payment_method NOT IN ('cash','credit') THEN RAISE EXCEPTION 'Invalid payment method'; END IF;
 IF p_payment_method='credit' AND p_debtor_id IS NULL THEN RAISE EXCEPTION 'اختر ملف المتدين أولاً'; END IF;
 IF p_debtor_id IS NOT NULL THEN SELECT name INTO v_debtor_name FROM public.debtors WHERE id=p_debtor_id; IF NOT FOUND THEN RAISE EXCEPTION 'ملف المتدين غير موجود'; END IF; END IF;
 INSERT INTO public.sales(id,customer_id,debtor_id,subtotal,discount,total,created_by,payment_method,paid_amount,due_amount,payment_notes)
 VALUES(v_sale_id,NULL,p_debtor_id,0,greatest(coalesce(p_discount,0),0),0,auth.uid(),p_payment_method,0,0,p_notes);
 FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
   need:=coalesce((it->>'quantity')::numeric,0);
   IF need<=0 THEN RAISE EXCEPTION 'Invalid quantity'; END IF;
   FOR b IN SELECT bt.id,bt.quantity,bt.purchase_price,bt.expiry_date FROM public.batches bt WHERE bt.product_id=(it->>'product_id')::uuid AND bt.quantity>0 AND (bt.expiry_date IS NULL OR bt.expiry_date>=current_date) ORDER BY bt.expiry_date NULLS LAST,bt.received_date NULLS FIRST,bt.id FOR UPDATE LOOP
     EXIT WHEN need<=0; take:=least(need,b.quantity); UPDATE public.batches SET quantity=quantity-take WHERE id=b.id;
     INSERT INTO public.sale_items(sale_id,product_id,batch_id,quantity,unit_price,unit_cost) VALUES(v_sale_id,(it->>'product_id')::uuid,b.id,take,(it->>'unit_price')::numeric,b.purchase_price);
     INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,created_by) VALUES((it->>'product_id')::uuid,b.id,'sale',-take,v_sale_id,auth.uid());
     sub:=sub+take*(it->>'unit_price')::numeric; need:=need-take;
   END LOOP;
   IF need>0 THEN RAISE EXCEPTION 'Insufficient non-expired stock for product %',(it->>'product_id'); END IF;
 END LOOP;
 total:=greatest(sub-greatest(coalesce(p_discount,0),0),0);
 IF p_payment_method='cash' THEN v_paid:=total; v_due:=0; ELSE v_paid:=0; v_due:=total; END IF;
 UPDATE public.sales SET subtotal=sub,total=total,paid_amount=v_paid,due_amount=v_due WHERE id=v_sale_id;
 IF p_payment_method='credit' THEN
   INSERT INTO public.debtor_transactions(debtor_id,transaction_type,sale_id,amount,debit,credit,payment_method,notes,created_by) VALUES(p_debtor_id,'sale',v_sale_id,total,total,0,'credit',p_notes,auth.uid());
 ELSE
   INSERT INTO public.cashbox_entries(entry_type,amount,description,sale_id,created_by) VALUES('sale_cash',total,'بيع نقدي',v_sale_id,auth.uid());
 END IF;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'complete_sale','sale',v_sale_id,jsonb_build_object('subtotal',sub,'discount',p_discount,'total',total,'payment_method',p_payment_method,'debtor_id',p_debtor_id,'debtor_name',v_debtor_name,'paid_amount',v_paid,'due_amount',v_due,'notes',p_notes));
 RETURN jsonb_build_object('sale_id',v_sale_id,'total',total,'payment_method',p_payment_method,'debtor_id',p_debtor_id,'paid_amount',v_paid,'due_amount',v_due);
EXCEPTION WHEN OTHERS THEN RAISE;
END; $$;
REVOKE ALL ON FUNCTION public.complete_sale_accounting(jsonb,numeric,text,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_sale_accounting(jsonb,numeric,text,uuid,text) TO authenticated;

-- =========================
-- 6) Debtor payment / cashbox
-- =========================
CREATE OR REPLACE FUNCTION public.admin_record_debtor_payment(p_debtor_id uuid,p_amount numeric,p_notes text DEFAULT NULL,p_payment_method text DEFAULT 'cash')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_balance numeric; v_tx uuid; v_name text;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_amount<=0 THEN RAISE EXCEPTION 'مبلغ الدفعة يجب أن يكون أكبر من صفر'; END IF;
 SELECT d.name,COALESCE((SELECT SUM(t.debit-t.credit) FROM public.debtor_transactions t WHERE t.debtor_id=d.id),0) INTO v_name,v_balance FROM public.debtors d WHERE d.id=p_debtor_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'المتدين غير موجود'; END IF;
 IF p_amount>v_balance THEN RAISE EXCEPTION 'الدفعة أكبر من الدين الحالي'; END IF;
 INSERT INTO public.debtor_transactions(debtor_id,transaction_type,amount,debit,credit,payment_method,notes,created_by) VALUES(p_debtor_id,'payment',p_amount,0,p_amount,p_payment_method,p_notes,auth.uid()) RETURNING id INTO v_tx;
 IF p_payment_method='cash' THEN INSERT INTO public.cashbox_entries(entry_type,amount,description,debtor_transaction_id,created_by) VALUES('debtor_payment',p_amount,'تحصيل دفعة من المتدين: '||v_name,v_tx,auth.uid()); END IF;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'debtor_payment','debtor',p_debtor_id,jsonb_build_object('name',v_name,'amount',p_amount,'payment_method',p_payment_method,'notes',p_notes,'previous_balance',v_balance,'new_balance',v_balance-p_amount));
 RETURN jsonb_build_object('transaction_id',v_tx,'previous_balance',v_balance,'new_balance',v_balance-p_amount);
END; $$;
REVOKE ALL ON FUNCTION public.admin_record_debtor_payment(uuid,numeric,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_record_debtor_payment(uuid,numeric,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_cashbox_summary(p_start timestamptz DEFAULT NULL,p_end timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v jsonb; s timestamptz:=COALESCE(p_start,'1900-01-01'::timestamptz); e timestamptz:=COALESCE(p_end,'2999-12-31'::timestamptz);
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object('cash_in',COALESCE(SUM(CASE WHEN amount>0 THEN amount ELSE 0 END),0),'cash_out',COALESCE(SUM(CASE WHEN amount<0 THEN -amount ELSE 0 END),0),'net',COALESCE(SUM(amount),0),'balance',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries),0),'entries',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'type',c.entry_type,'amount',c.amount,'description',c.description,'created_at',c.created_at) ORDER BY c.created_at DESC) FROM public.cashbox_entries c WHERE c.created_at>=s AND c.created_at<e),'[]'::jsonb)) INTO v FROM public.cashbox_entries c WHERE c.created_at>=s AND c.created_at<e;
 RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.admin_cashbox_summary(timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cashbox_summary(timestamptz,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_cashbox_entry(p_type text,p_amount numeric,p_description text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_id uuid;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF p_amount=0 THEN RAISE EXCEPTION 'المبلغ لا يمكن أن يكون صفراً'; END IF;
 IF p_type NOT IN ('expense','income','withdrawal','deposit','adjustment') THEN RAISE EXCEPTION 'نوع حركة صندوق غير صالح'; END IF;
 INSERT INTO public.cashbox_entries(entry_type,amount,description,created_by) VALUES(p_type,CASE WHEN p_type IN ('expense','withdrawal') THEN -abs(p_amount) ELSE abs(p_amount) END,p_description,auth.uid()) RETURNING id INTO v_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details) VALUES(auth.uid(),'cashbox_entry','cashbox',v_id,jsonb_build_object('type',p_type,'amount',p_amount,'description',p_description));
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.admin_cashbox_entry(text,numeric,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cashbox_entry(text,numeric,text) TO authenticated;

-- Backfill the cashbox for legacy sales from previous versions.
-- Old sales had no payment mode, so v5.6 treats them as historical cash sales.
INSERT INTO public.cashbox_entries(entry_type,amount,description,sale_id,created_by,created_at)
SELECT 'sale_cash',COALESCE(s.total,0),'مبيعات نقدية تاريخية',s.id,s.created_by,s.created_at
FROM public.sales s
WHERE COALESCE(s.total,0)>0
  AND s.payment_method='cash'
  AND NOT EXISTS (SELECT 1 FROM public.cashbox_entries c WHERE c.sale_id=s.id AND c.entry_type='sale_cash');

-- =========================
-- 7) Integrated reporting
-- =========================
CREATE OR REPLACE FUNCTION public.admin_accounting_report(p_start timestamptz,p_end timestamptz,p_compare_start timestamptz DEFAULT NULL,p_compare_end timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v jsonb; cs timestamptz:=p_compare_start; ce timestamptz:=p_compare_end;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object(
  'period',jsonb_build_object('start',p_start,'end',p_end),
  'summary',jsonb_build_object(
    'sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0),
    'cash_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='cash' AND created_at>=p_start AND created_at<p_end),0),
    'credit_sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE payment_method='credit' AND created_at>=p_start AND created_at<p_end),0),
    'debt_collections',COALESCE((SELECT SUM(credit) FROM public.debtor_transactions WHERE transaction_type='payment' AND created_at>=p_start AND created_at<p_end),0),
    'new_debt',COALESCE((SELECT SUM(debit) FROM public.debtor_transactions WHERE transaction_type='sale' AND created_at>=p_start AND created_at<p_end),0),
    'purchases',COALESCE((SELECT SUM(total) FROM public.purchases WHERE created_at>=p_start AND created_at<p_end),0),
    'profit',COALESCE((SELECT SUM((unit_price-unit_cost)*quantity) FROM public.sale_items WHERE created_at>=p_start AND created_at<p_end),0),
    'margin',CASE WHEN COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0)=0 THEN 0 ELSE ROUND((COALESCE((SELECT SUM((unit_price-unit_cost)*quantity) FROM public.sale_items WHERE created_at>=p_start AND created_at<p_end),0)/NULLIF((SELECT SUM(total) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0))*100,2) END,
    'cash_in',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE amount>0 AND created_at>=p_start AND created_at<p_end),0),
    'cash_out',COALESCE((SELECT SUM(-amount) FROM public.cashbox_entries WHERE amount<0 AND created_at>=p_start AND created_at<p_end),0),
    'cash_net',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries WHERE created_at>=p_start AND created_at<p_end),0),
    'cash_balance',COALESCE((SELECT SUM(amount) FROM public.cashbox_entries),0),
    'outstanding_debt',COALESCE((SELECT SUM(debit-credit) FROM public.debtor_transactions),0),
    'sales_count',COALESCE((SELECT COUNT(*) FROM public.sales WHERE created_at>=p_start AND created_at<p_end),0),
    'purchase_count',COALESCE((SELECT COUNT(*) FROM public.purchases WHERE created_at>=p_start AND created_at<p_end),0)
  ),
  'comparison',CASE WHEN cs IS NULL OR ce IS NULL THEN NULL ELSE jsonb_build_object(
    'sales',COALESCE((SELECT SUM(total) FROM public.sales WHERE created_at>=cs AND created_at<ce),0),
    'purchases',COALESCE((SELECT SUM(total) FROM public.purchases WHERE created_at>=cs AND created_at<ce),0),
    'profit',COALESCE((SELECT SUM((unit_price-unit_cost)*quantity) FROM public.sale_items WHERE created_at>=cs AND created_at<ce),0),
    'new_debt',COALESCE((SELECT SUM(debit) FROM public.debtor_transactions WHERE transaction_type='sale' AND created_at>=cs AND created_at<ce),0),
    'debt_collections',COALESCE((SELECT SUM(credit) FROM public.debtor_transactions WHERE transaction_type='payment' AND created_at>=cs AND created_at<ce),0)
  ) END,
  'sales_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'created_at',s.created_at,'total',s.total,'payment_method',s.payment_method,'paid_amount',s.paid_amount,'due_amount',s.due_amount,'debtor_id',s.debtor_id,'debtor_name',d.name) ORDER BY s.created_at DESC) FROM public.sales s LEFT JOIN public.debtors d ON d.id=s.debtor_id WHERE s.created_at>=p_start AND s.created_at<p_end),'[]'::jsonb),
  'purchase_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'created_at',p.created_at,'invoice_number',p.invoice_number,'supplier_name',s.name,'total',p.total) ORDER BY p.created_at DESC) FROM public.purchases p LEFT JOIN public.suppliers s ON s.id=p.supplier_id WHERE p.created_at>=p_start AND p.created_at<p_end),'[]'::jsonb),
  'debt_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'created_at',t.created_at,'type',t.transaction_type,'debtor_name',d.name,'amount',t.amount,'debit',t.debit,'credit',t.credit,'notes',t.notes) ORDER BY t.created_at DESC) FROM public.debtor_transactions t JOIN public.debtors d ON d.id=t.debtor_id WHERE t.created_at>=p_start AND t.created_at<p_end),'[]'::jsonb),
  'cash_rows',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,'type',c.entry_type,'amount',c.amount,'description',c.description) ORDER BY c.created_at DESC) FROM public.cashbox_entries c WHERE c.created_at>=p_start AND c.created_at<p_end),'[]'::jsonb),
  'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('product_name',p.name,'quantity',SUM(si.quantity),'sales',SUM(si.quantity*si.unit_price),'cost',SUM(si.quantity*si.unit_cost),'profit',SUM(si.quantity*(si.unit_price-si.unit_cost))) ORDER BY SUM(si.quantity) DESC) FROM public.sale_items si JOIN public.products p ON p.id=si.product_id WHERE si.created_at>=p_start AND si.created_at<p_end GROUP BY p.name LIMIT 50),'[]'::jsonb)
 ) INTO v;
 RETURN v;
END; $$;
REVOKE ALL ON FUNCTION public.admin_accounting_report(timestamptz,timestamptz,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_accounting_report(timestamptz,timestamptz,timestamptz,timestamptz) TO authenticated;

-- =========================
-- 8) Single-product inventory count
-- =========================
CREATE OR REPLACE FUNCTION public.admin_start_product_inventory_count(p_product_id uuid,p_notes text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE v_id uuid;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.products WHERE id=p_product_id) THEN RAISE EXCEPTION 'المنتج غير موجود'; END IF;
 INSERT INTO public.inventory_counts(created_by,notes) VALUES(auth.uid(),COALESCE(NULLIF(trim(COALESCE(p_notes,'')),''),'جرد منتج واحد')) RETURNING id INTO v_id;
 INSERT INTO public.inventory_count_items(count_id,batch_id,expected_quantity)
 SELECT v_id,b.id,b.quantity FROM public.batches b WHERE b.product_id=p_product_id AND b.quantity>=0;
 RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public.admin_start_product_inventory_count(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_start_product_inventory_count(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_search_inventory_products(p_query text DEFAULT NULL)
RETURNS TABLE(id uuid,name text,barcode text,active_ingredient text,stock numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,auth AS $$
 SELECT p.id,p.name,p.barcode,p.active_ingredient,COALESCE(SUM(b.quantity),0)
 FROM public.products p LEFT JOIN public.batches b ON b.product_id=p.id
 WHERE public.is_admin() AND (NULLIF(trim(COALESCE(p_query,'')),'') IS NULL OR p.name ILIKE '%'||trim(p_query)||'%' OR COALESCE(p.active_ingredient,'') ILIKE '%'||trim(p_query)||'%' OR COALESCE(p.barcode,'')=trim(p_query))
 GROUP BY p.id ORDER BY CASE WHEN COALESCE(p.barcode,'')=trim(COALESCE(p_query,'')) THEN 0 ELSE 1 END,p.name LIMIT 30;
$$;
REVOKE ALL ON FUNCTION public.admin_search_inventory_products(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_inventory_products(text) TO authenticated;

-- =========================
-- 9) Indexes / audit labels
-- =========================
CREATE INDEX IF NOT EXISTS idx_debtors_name ON public.debtors(name);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON public.products(barcode);

COMMIT;
