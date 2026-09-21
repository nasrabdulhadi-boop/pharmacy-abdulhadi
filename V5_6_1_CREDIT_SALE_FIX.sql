-- v5.6.1: Fix credit sale error: column reference "total" is ambiguous
-- Run this AFTER V5_6_ACCOUNTING.sql. It is safe to rerun.

CREATE OR REPLACE FUNCTION public.complete_sale_accounting(
 p_items jsonb,
 p_discount numeric DEFAULT 0,
 p_payment_method text DEFAULT 'cash',
 p_debtor_id uuid DEFAULT NULL,
 p_notes text DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,auth AS $$
DECLARE
 v_sale_id uuid := gen_random_uuid();
 it jsonb;
 b record;
 need numeric;
 take numeric;
 sub numeric := 0;
 v_total numeric := 0;
 v_paid numeric := 0;
 v_due numeric := 0;
 v_debtor_name text;
BEGIN
 IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 IF jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 THEN RAISE EXCEPTION 'Sale must contain items'; END IF;
 IF p_payment_method NOT IN ('cash','credit') THEN RAISE EXCEPTION 'Invalid payment method'; END IF;
 IF p_payment_method='credit' AND p_debtor_id IS NULL THEN RAISE EXCEPTION 'اختر ملف المتدين أولاً'; END IF;
 IF p_debtor_id IS NOT NULL THEN
   SELECT d.name INTO v_debtor_name FROM public.debtors d WHERE d.id=p_debtor_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'ملف المتدين غير موجود'; END IF;
 END IF;

 INSERT INTO public.sales(id,customer_id,debtor_id,subtotal,discount,total,created_by,payment_method,paid_amount,due_amount,payment_notes)
 VALUES(v_sale_id,NULL,p_debtor_id,0,greatest(coalesce(p_discount,0),0),0,auth.uid(),p_payment_method,0,0,p_notes);

 FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
   need := coalesce((it->>'quantity')::numeric,0);
   IF need<=0 THEN RAISE EXCEPTION 'Invalid quantity'; END IF;
   FOR b IN
     SELECT bt.id,bt.quantity,bt.purchase_price,bt.expiry_date
     FROM public.batches bt
     WHERE bt.product_id=(it->>'product_id')::uuid
       AND bt.quantity>0
       AND (bt.expiry_date IS NULL OR bt.expiry_date>=current_date)
     ORDER BY bt.expiry_date NULLS LAST,bt.received_date NULLS FIRST,bt.id
     FOR UPDATE
   LOOP
     EXIT WHEN need<=0;
     take := least(need,b.quantity);
     UPDATE public.batches bt SET quantity=bt.quantity-take WHERE bt.id=b.id;
     INSERT INTO public.sale_items(sale_id,product_id,batch_id,quantity,unit_price,unit_cost)
     VALUES(v_sale_id,(it->>'product_id')::uuid,b.id,take,(it->>'unit_price')::numeric,b.purchase_price);
     INSERT INTO public.stock_movements(product_id,batch_id,movement_type,quantity,reference_id,created_by)
     VALUES((it->>'product_id')::uuid,b.id,'sale',-take,v_sale_id,auth.uid());
     sub := sub + take*(it->>'unit_price')::numeric;
     need := need-take;
   END LOOP;
   IF need>0 THEN RAISE EXCEPTION 'Insufficient non-expired stock for product %',(it->>'product_id'); END IF;
 END LOOP;

 v_total := greatest(sub-greatest(coalesce(p_discount,0),0),0);
 IF p_payment_method='cash' THEN v_paid:=v_total; v_due:=0; ELSE v_paid:=0; v_due:=v_total; END IF;
 UPDATE public.sales s SET subtotal=sub,total=v_total,paid_amount=v_paid,due_amount=v_due WHERE s.id=v_sale_id;

 IF p_payment_method='credit' THEN
   INSERT INTO public.debtor_transactions(debtor_id,transaction_type,sale_id,amount,debit,credit,payment_method,notes,created_by)
   VALUES(p_debtor_id,'sale',v_sale_id,v_total,v_total,0,'credit',p_notes,auth.uid());
 ELSE
   INSERT INTO public.cashbox_entries(entry_type,amount,description,sale_id,created_by)
   VALUES('sale_cash',v_total,'بيع نقدي',v_sale_id,auth.uid());
 END IF;

 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,details)
 VALUES(auth.uid(),'complete_sale','sale',v_sale_id,jsonb_build_object(
   'subtotal',sub,'discount',p_discount,'total',v_total,'payment_method',p_payment_method,
   'debtor_id',p_debtor_id,'debtor_name',v_debtor_name,'paid_amount',v_paid,'due_amount',v_due,'notes',p_notes));

 RETURN jsonb_build_object('sale_id',v_sale_id,'total',v_total,'payment_method',p_payment_method,'debtor_id',p_debtor_id,'paid_amount',v_paid,'due_amount',v_due);
END; $$;

REVOKE ALL ON FUNCTION public.complete_sale_accounting(jsonb,numeric,text,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_sale_accounting(jsonb,numeric,text,uuid,text) TO authenticated;
