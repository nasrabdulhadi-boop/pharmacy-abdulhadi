-- QA only. All replays are scoped to the authenticated actor.
create table if not exists pharmacy_qa_private.offline_receipts (
 actor_id uuid not null,
 local_id uuid not null,
 lines jsonb not null,
 receipt_id uuid not null references public.qa_employee_operations,
 primary key (actor_id,local_id)
);
alter table pharmacy_qa_private.offline_receipts enable row level security;
revoke all on pharmacy_qa_private.offline_receipts from public,anon,authenticated;

create or replace function public.qa_sync_offline_sale(p_actor uuid,p_local_id uuid,p_lines jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid();
 actor_role text:=public.qa_current_system_role();
 prior pharmacy_qa_private.offline_receipts;
 item jsonb;
 product pharmacy_qa_private.catalog;
 payload jsonb:='[]';
 receipt uuid;
begin
 if actor is null or actor is distinct from p_actor or not coalesce(actor_role in ('system_owner','system_admin','employee'),false) then
  raise exception 'not_authorized' using errcode='42501';
 end if;
 if p_local_id is null or jsonb_typeof(p_lines) is distinct from 'array' or octet_length(p_lines::text)>12000 then
  raise exception 'invalid_offline_sale' using errcode='22023';
 end if;
 if jsonb_array_length(p_lines) not between 1 and 30 then
  raise exception 'invalid_offline_sale' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||p_local_id::text,956));
 select * into prior from pharmacy_qa_private.offline_receipts where actor_id=actor and local_id=p_local_id;
 if found then
  if prior.lines is distinct from p_lines then raise exception 'offline_id_conflict' using errcode='22023'; end if;
  return prior.receipt_id;
 end if;
 if (select count(distinct x->>'id') from jsonb_array_elements(p_lines) x) <> jsonb_array_length(p_lines) then
  raise exception 'invalid_offline_sale' using errcode='22023';
 end if;
 for item in select x from jsonb_array_elements(p_lines) x order by (x->>'id')::uuid loop
  if coalesce(item->>'quantity','') !~ '^[1-9][0-9]{0,2}$' or
     coalesce(item->>'unitPrice','') !~ '^[0-9]{1,12}(\.[0-9]{1,4})?$' then
   raise exception 'invalid_offline_sale' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended((item->>'id')::uuid::text,617));
  select * into product from pharmacy_qa_private.catalog where id=(item->>'id')::uuid;
  if not found or product.price<=0 or
     (product.price * case when product.currency='USD' then 140 else 1 end)<>(item->>'unitPrice')::numeric then
   raise exception 'offline_price_changed' using errcode='22023';
  end if;
  payload:=payload||jsonb_build_array(jsonb_build_object('product_id',product.id,'quantity',(item->>'quantity')::integer));
 end loop;
 if actor_role='employee' then
  receipt:=public.qa_employee_execute_workspace('sale',payload,null,p_local_id);
 else
  receipt:=public.qa_manager_execute_workspace('sale',payload,null);
 end if;
 insert into pharmacy_qa_private.offline_receipts values(actor,p_local_id,p_lines,receipt);
 return receipt;
end $$;
revoke all on function public.qa_sync_offline_sale(uuid,uuid,jsonb) from public,anon;
grant execute on function public.qa_sync_offline_sale(uuid,uuid,jsonb) to authenticated;
