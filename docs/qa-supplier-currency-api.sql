CREATE FUNCTION public.qa_supplier_currency_list_v2() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb; BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.is_admin(),false) THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x)),'[]') INTO v FROM (
 SELECT s.id,s.name,s.phone,s.address,p.currency,count(*) invoice_count,sum(total) invoice_total,
 sum(paid_amount) paid_total,sum(due_amount) balance,
 (SELECT max(sp.created_at) FROM supplier_currency_qa.supplier_payments sp WHERE sp.supplier_id=s.id AND sp.currency=p.currency) last_payment
 FROM supplier_currency_qa.suppliers s JOIN supplier_currency_qa.purchases p ON p.supplier_id=s.id GROUP BY s.id,p.currency) x;
 RETURN v; END $$;
CREATE FUNCTION public.qa_supplier_currency_ledger_v2(p_supplier_id uuid,p_currency text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb; BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.is_admin(),false) THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object('supplier',to_jsonb(s)||jsonb_build_object('currency',p_currency),
 'summary',(SELECT jsonb_build_object('invoice_total',coalesce(sum(total),0),'paid_total',coalesce(sum(paid_amount),0),'balance',coalesce(sum(due_amount),0)) FROM supplier_currency_qa.purchases WHERE supplier_id=s.id AND currency=p_currency),
 'invoices',(SELECT coalesce(jsonb_agg(to_jsonb(p)||jsonb_build_object('items','[]'::jsonb) ORDER BY p.created_at,p.invoice_number),'[]') FROM supplier_currency_qa.purchases p WHERE supplier_id=s.id AND currency=p_currency),
 'payments',(SELECT coalesce(jsonb_agg(to_jsonb(sp)||jsonb_build_object('allocations',
 (SELECT coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('invoice_number',p.invoice_number)),'[]') FROM supplier_currency_qa.supplier_payment_allocations a JOIN supplier_currency_qa.purchases p ON p.id=a.purchase_id WHERE payment_id=sp.id)) ORDER BY sp.created_at DESC),'[]') FROM supplier_currency_qa.supplier_payments sp WHERE supplier_id=s.id AND currency=p_currency))
 INTO v FROM supplier_currency_qa.suppliers s WHERE s.id=p_supplier_id;
 RETURN v; END $$;
CREATE FUNCTION public.qa_supplier_currency_fx_v2() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN IF auth.uid() IS NULL OR NOT coalesce(public.is_admin(),false) THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 RETURN jsonb_build_object('usd_to_syp',140); END $$;
CREATE FUNCTION public.qa_supplier_currency_cashbox_v2() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v jsonb; BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.is_admin(),false) THEN RAISE EXCEPTION 'Admin authorization required'; END IF;
 SELECT jsonb_build_object('entries',coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.created_at DESC),'[]'),
 'usd_balance',coalesce(sum(amount) FILTER(WHERE currency='USD'),0),
 'syp_balance',coalesce(sum(amount) FILTER(WHERE currency='SYP'),0),
 'balance',coalesce(sum(amount_syp),0)) INTO v FROM supplier_currency_qa.cashbox_entries c;
 RETURN v; END $$;
REVOKE ALL ON FUNCTION public.qa_supplier_currency_list_v2() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.qa_supplier_currency_ledger_v2(uuid,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.qa_supplier_currency_fx_v2() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.qa_supplier_currency_cashbox_v2() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.qa_supplier_currency_list_v2(),public.qa_supplier_currency_ledger_v2(uuid,text),public.qa_supplier_currency_fx_v2(),public.qa_supplier_currency_cashbox_v2() TO authenticated;
NOTIFY pgrst,'reload schema';
