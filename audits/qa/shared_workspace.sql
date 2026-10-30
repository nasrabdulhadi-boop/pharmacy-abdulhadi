begin;
create or replace function public.qa_workspace_snapshot() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r text:=public.qa_current_system_role(); result jsonb; privileged boolean:=coalesce(r in ('system_owner','system_admin'),false);
begin
 if auth.uid() is null or r is null then raise exception 'not_authorized' using errcode='42501'; end if;
 if r='technical_support' then return jsonb_build_object('role',r,'health',(select jsonb_agg(h) from public.qa_support_health()h)); end if;
 if not privileged and r<>'employee' then raise exception 'not_authorized' using errcode='42501'; end if;
 result:=jsonb_build_object('role',r,'fx_rate',140,
 'products',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.title,'barcode',p.code,'active',true,'customer_visible',false,'sale_price',p.price,'sale_currency',p.currency,'parts_per_unit',p.parts,'unit','box','reorder_level',1,'stock',coalesce((select sum(b.quantity) from pharmacy_qa_private.batches b where b.product_id=p.id and b.expiry>=current_date),0)) || case when privileged then jsonb_build_object('purchase_price',(select coalesce(sum(b.quantity*b.cost)/nullif(sum(b.quantity),0),0) from pharmacy_qa_private.batches b where b.product_id=p.id)) else '{}'::jsonb end),'[]'::jsonb) from pharmacy_qa_private.catalog p),
 'batches',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'batch_id',b.id,'product_id',b.product_id,'quantity',b.quantity,'expiry_date',b.expiry,'received_date',current_date,'purchase_currency',p.currency) || case when privileged then jsonb_build_object('purchase_price',b.cost,'original_purchase_price',b.cost,'product_purchase_price',b.cost) else '{}'::jsonb end),'[]'::jsonb) from pharmacy_qa_private.batches b join pharmacy_qa_private.catalog p on p.id=b.product_id),
 'documents',(select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'request_id',d.request_id,'product_id',d.product_id,'kind',d.kind,'quantity',d.quantity,'total',d.total,'currency',d.currency,'created_at',d.created_at) || case when privileged then jsonb_build_object('cost',d.cost) else '{}'::jsonb end),'[]'::jsonb) from pharmacy_qa_private.documents d where privileged or d.employee_id=auth.uid()),
 'requests',(select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) from public.qa_sandbox_requests()q));
 if privileged then result:=result||jsonb_build_object('report',public.qa_sandbox_report()); end if;
 return result;
end $$;
revoke all on function public.qa_workspace_snapshot() from public,anon;
grant execute on function public.qa_workspace_snapshot() to authenticated;
notify pgrst,'reload schema';
commit;
