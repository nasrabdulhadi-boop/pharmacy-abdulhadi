begin;
create or replace function public.qa_submit_workspace_bundle(p_operation text,p_payloads jsonb,p_currency text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare parent uuid:=gen_random_uuid(); child uuid; ids jsonb:='[]'; item jsonb; currency text;
begin
 if public.qa_current_system_role() is distinct from 'employee' then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_operation is null or p_operation not in ('sale','purchase_draft','return_request','order_process','inventory_count') or jsonb_typeof(p_payloads) is distinct from 'array' or jsonb_array_length(p_payloads) not between 1 and 30 then raise exception 'invalid_bundle' using errcode='22023'; end if;
 for item in select value from jsonb_array_elements(p_payloads) loop
  if p_operation='purchase_draft' then
   select p.currency into currency from pharmacy_qa_private.catalog p where p.id=(item->>'product_id')::uuid;
   if p_currency is null or currency is distinct from p_currency then raise exception 'purchase_currency_mismatch' using errcode='22023'; end if;
  end if;
  child:=public.qa_submit_sandbox_operation(p_operation,item);
  update public.qa_employee_operations set payload=payload||jsonb_build_object('bundle_parent',parent) where id=child;
  ids:=ids||to_jsonb(child);
 end loop;
 insert into public.qa_employee_operations(id,employee_id,operation,payload) values(parent,auth.uid(),p_operation,jsonb_build_object('bundle',true,'children',ids,'lines',p_payloads,'currency',case when p_operation='sale' then 'SYP' else p_currency end));
 return parent;
end $$;
create or replace function public.qa_review_employee_operation(p_id uuid,p_approve boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare r public.qa_employee_operations; c public.qa_employee_operations; doc uuid;
begin
 if auth.uid() is null or not coalesce(public.qa_current_system_role() in ('system_owner','system_admin'),false) then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_id is null or p_approve is null then raise exception 'invalid_decision' using errcode='22023'; end if;
 select * into r from public.qa_employee_operations where id=p_id for update;
 if not found or r.status<>'pending' then return false; end if;
 if r.payload->>'bundle'='true' then
  -- Lock all children and product rows in a stable order before applying any line.
  perform 1 from public.qa_employee_operations o where o.id in(select value::text::uuid from jsonb_array_elements_text(r.payload->'children')) order by o.id for update;
  if (select count(*) from public.qa_employee_operations o where o.id in(select value::uuid from jsonb_array_elements_text(r.payload->'children')) and o.status='pending' and o.employee_id=r.employee_id and o.payload->>'bundle_parent'=r.id::text)<>jsonb_array_length(r.payload->'children') then raise exception 'bundle_already_decided' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p.id::text,617)) from pharmacy_qa_private.catalog p where p.id in(select (o.payload->'data'->>'product_id')::uuid from public.qa_employee_operations o where o.payload->>'bundle_parent'=r.id::text and o.payload->'data' ? 'product_id') order by p.id;
  for c in select * from public.qa_employee_operations o where o.payload->>'bundle_parent'=r.id::text order by o.id loop
   if not public.qa_review_employee_operation(c.id,p_approve) then raise exception 'bundle_already_decided' using errcode='22023'; end if;
   if p_approve and r.operation='sale' then
    -- POS settlement is SYP; server-controlled QA FX, never client prices.
    select id into doc from pharmacy_qa_private.documents where request_id=c.id;
    if exists(select 1 from pharmacy_qa_private.documents where id=doc and currency='USD') then
     update pharmacy_qa_private.movements set cost=cost*140 where document_id=doc;
     update pharmacy_qa_private.documents set total=total*140,cost=cost*140,currency='SYP' where id=doc;
     update pharmacy_qa_private.ledger set amount=amount*140,currency='SYP' where document_id=doc;
    end if;
   end if;
  end loop;
 elsif p_approve and r.payload->>'sandbox'='true' then perform pharmacy_qa_private.execute_operation(r);
 end if;
 update public.qa_employee_operations set status=case when p_approve then 'approved' else 'rejected' end,decided_at=now(),decided_by=auth.uid() where id=p_id;
 return true;
end $$;
-- Return uses the original settlement currency; batch cost itself stays in its original currency.
do $$ declare definition text; begin
 select pg_get_functiondef('pharmacy_qa_private.execute_operation(public.qa_employee_operations)'::regprocedure) into definition;
 definition:=replace(definition,'select * into p from pharmacy_qa_private.catalog where id=source.product_id;','select * into p from pharmacy_qa_private.catalog where id=source.product_id; p.currency:=source.currency;');
 definition:=replace(definition,$old$where source_id=source.id and kind='return_request';$old$,$new$where source_id=source.id and kind='return_request' and id<>doc;$new$);
 execute definition;
end $$;
create or replace function public.qa_sandbox_requests() returns table(id uuid,operation text,payload jsonb,status text,decided_by uuid,decided_at timestamptz,created_at timestamptz) language sql stable security definer set search_path='' as $$
 select o.id,o.operation,o.payload,o.status,o.decided_by,o.decided_at,o.created_at from public.qa_employee_operations o where not(o.payload ? 'bundle_parent') and auth.uid() is not null and coalesce(public.qa_current_system_role() in ('system_owner','system_admin') or (public.qa_current_system_role()='employee' and o.employee_id=auth.uid()),false) order by o.created_at desc,o.id limit 100
$$;
revoke all on function public.qa_submit_workspace_bundle(text,jsonb,text) from public,anon;
grant execute on function public.qa_submit_workspace_bundle(text,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
