-- ISOLATED QA ONLY: vpjxdsprfcpqclnhbeoh. No production schema compatibility claim.
begin;
do $$ begin
 if to_regclass('public.qa_employee_operations') is null then raise exception 'QA prerequisite missing'; end if;
end $$;
create schema if not exists pharmacy_qa_private;
revoke all on schema pharmacy_qa_private from public,anon,authenticated;
create table if not exists pharmacy_qa_private.catalog(
 id uuid primary key default gen_random_uuid(),code text unique not null,title text not null,
 price numeric(18,4) not null check(price>=0),currency text not null check(currency in ('USD','SYP')),
 parts integer not null default 1 check(parts between 1 and 1000));
create table if not exists pharmacy_qa_private.batches(
 id uuid primary key default gen_random_uuid(),product_id uuid not null references pharmacy_qa_private.catalog,
 quantity numeric(18,4) not null check(quantity>=0),cost numeric(18,4) not null check(cost>=0),expiry date not null);
create index if not exists qa_batches_fefo on pharmacy_qa_private.batches(product_id,expiry,id);
create table if not exists pharmacy_qa_private.documents(
 id uuid primary key default gen_random_uuid(),request_id uuid unique not null references public.qa_employee_operations,
 kind text not null,employee_id uuid not null,product_id uuid references pharmacy_qa_private.catalog,
 quantity numeric(18,4) not null default 0,total numeric(18,4) not null default 0,cost numeric(18,4) not null default 0,
 currency text check(currency in ('USD','SYP')),source_id uuid references pharmacy_qa_private.documents,
 created_at timestamptz not null default now());
create index if not exists qa_documents_source on pharmacy_qa_private.documents(source_id);
create table if not exists pharmacy_qa_private.movements(
 id bigint generated always as identity primary key,document_id uuid not null references pharmacy_qa_private.documents,
 batch_id uuid not null references pharmacy_qa_private.batches,quantity numeric(18,4) not null,cost numeric(18,4) not null);
create index if not exists qa_movements_document on pharmacy_qa_private.movements(document_id);
create table if not exists pharmacy_qa_private.ledger(
 document_id uuid primary key references pharmacy_qa_private.documents,kind text not null,
 currency text not null check(currency in ('USD','SYP')),amount numeric(18,4) not null);
alter table pharmacy_qa_private.catalog enable row level security;
alter table pharmacy_qa_private.batches enable row level security;
alter table pharmacy_qa_private.documents enable row level security;
alter table pharmacy_qa_private.movements enable row level security;
alter table pharmacy_qa_private.ledger enable row level security;
revoke all on all tables in schema pharmacy_qa_private from public,anon,authenticated;
revoke all on all sequences in schema pharmacy_qa_private from public,anon,authenticated;
insert into pharmacy_qa_private.catalog(code,title,price,currency,parts) values
 ('QA-USD','صنف تجريبي بالدولار — غير مخصص للمرضى',2,'USD',10),
 ('QA-SYP','صنف تجريبي بالليرة — غير مخصص للمرضى',300,'SYP',1)
on conflict(code) do nothing;
-- Seed exactly once; never overwrite stock on rerun.
do $$ declare p record; begin
 for p in select * from pharmacy_qa_private.catalog loop
  if not exists(select 1 from pharmacy_qa_private.batches where product_id=p.id) then
   insert into pharmacy_qa_private.batches(product_id,quantity,cost,expiry) values
    (p.id,10,case when p.currency='USD' then 1 else 100 end,current_date+30),
    (p.id,20,case when p.currency='USD' then 1.5 else 150 end,current_date+90),
    (p.id,5,0.5,current_date-1);
  end if;
 end loop;
end $$;
create or replace function public.qa_sandbox_catalog()
returns table(id uuid,code text,title text,sale_price numeric,currency text,parts integer,available numeric)
language sql stable security definer set search_path='' as $$
 select p.id,p.code,p.title,p.price,p.currency,p.parts,
 coalesce((select sum(b.quantity) from pharmacy_qa_private.batches b where b.product_id=p.id and b.expiry>=current_date),0)
 from pharmacy_qa_private.catalog p where auth.uid() is not null and
 coalesce(public.qa_current_system_role() in ('employee','system_admin','system_owner'),false)
 order by p.code;
$$;
create or replace function public.qa_submit_sandbox_operation(p_operation text,p_payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; p pharmacy_qa_private.catalog; q numeric; allowed text[];
begin
 if auth.uid() is null or public.qa_current_system_role() is distinct from 'employee' then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_operation is null or p_operation not in ('sale','purchase_draft','inventory_count','return_request','order_process')
 or p_payload is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>2048 then raise exception 'invalid_payload' using errcode='22023'; end if;
 allowed:=case p_operation when 'sale' then array['product_id','quantity'] when 'purchase_draft' then array['product_id','quantity','bonus','unit_cost','discount','expiry'] when 'inventory_count' then array['product_id','quantity','expected_quantity'] when 'return_request' then array['sale_id','quantity'] else array[]::text[] end;
 if exists(select 1 from jsonb_object_keys(p_payload) k where not(k=any(allowed))) then raise exception 'unexpected_field' using errcode='22023'; end if;
 if p_operation<>'order_process' then
  q:=(p_payload->>'quantity')::numeric;
  if q is null or q='NaN'::numeric or q<0 or q>10000 or q<>round(q,4) or (q=0 and p_operation not in ('inventory_count','purchase_draft')) then raise exception 'invalid_quantity' using errcode='22023'; end if;
  if p_operation<>'return_request' then
   select * into p from pharmacy_qa_private.catalog where id=(p_payload->>'product_id')::uuid;
   if not found or q*p.parts<>trunc(q*p.parts) then raise exception 'invalid_product_or_part' using errcode='22023'; end if;
  elsif not exists(select 1 from pharmacy_qa_private.documents where id=(p_payload->>'sale_id')::uuid and kind='sale' and employee_id=auth.uid()) then
   raise exception 'invalid_sale' using errcode='22023';
  end if;
 end if;
 if p_operation='purchase_draft' then
  if not (p_payload ?& array['unit_cost','bonus','discount','expiry']) or q+coalesce((p_payload->>'bonus')::numeric,0)<=0 or
  (p_payload->>'unit_cost')::numeric not between 0 and 1000000 or
  (p_payload->>'bonus')::numeric not between 0 and 10000 or
  (p_payload->>'discount')::numeric not between 0 and q*(p_payload->>'unit_cost')::numeric or
  (p_payload->>'expiry')::date<current_date then raise exception 'invalid_purchase' using errcode='22023'; end if;
  if exists(select 1 from jsonb_each(p_payload) e where e.value='null'::jsonb) or
    (p_payload->>'bonus')::numeric*p.parts<>trunc((p_payload->>'bonus')::numeric*p.parts) then raise exception 'invalid_purchase_values' using errcode='22023'; end if;
 elsif p_operation='inventory_count' then
  if (p_payload->>'expected_quantity')::numeric is null or (p_payload->>'expected_quantity')::numeric not between 0 and 1000000 then raise exception 'invalid_snapshot' using errcode='22023'; end if;
 end if;
 insert into public.qa_employee_operations(employee_id,operation,payload) values(auth.uid(),p_operation,jsonb_build_object('sandbox',true,'data',p_payload)) returning id into v_id;
 return v_id;
end $$;
create or replace function pharmacy_qa_private.execute_operation(r public.qa_employee_operations)
returns uuid language plpgsql set search_path='' as $$
<<op>>
declare d jsonb:=r.payload->'data'; p pharmacy_qa_private.catalog; source pharmacy_qa_private.documents;
 b record; doc uuid; q numeric:=coalesce((d->>'quantity')::numeric,0); needed numeric; take numeric;
 total numeric:=0; cost numeric:=0; have numeric; bonus numeric; returned numeric;
begin
 -- Only called by the manager-gated decision function; no API grants.
 if r.operation='return_request' then
  select * into source from pharmacy_qa_private.documents where id=(d->>'sale_id')::uuid for update;
  if not found or source.kind<>'sale' or source.employee_id<>r.employee_id then raise exception 'invalid_sale' using errcode='22023'; end if;
  select * into p from pharmacy_qa_private.catalog where id=source.product_id;
 else select * into p from pharmacy_qa_private.catalog where id=(d->>'product_id')::uuid; end if;
 if r.operation<>'order_process' and (p.id is null or q*p.parts<>trunc(q*p.parts)) then raise exception 'invalid_product_or_part' using errcode='22023'; end if;
 -- Serialize all mutations for a product, including FEFO selection and stock counts.
 if p.id is not null then perform pg_advisory_xact_lock(hashtextextended(p.id::text,617)); end if;
 insert into pharmacy_qa_private.documents(request_id,kind,employee_id,product_id,quantity,currency,source_id)
 values(r.id,r.operation,r.employee_id,p.id,q,p.currency,source.id) returning id into doc;
 if r.operation='sale' then
  needed:=q;
  for b in select * from pharmacy_qa_private.batches where product_id=p.id and expiry>=current_date and quantity>0 order by expiry,id for update loop
   take:=least(needed,b.quantity);if take<=0 then exit; end if;
   update pharmacy_qa_private.batches set quantity=quantity-take where id=b.id;
   insert into pharmacy_qa_private.movements(document_id,batch_id,quantity,cost) values(doc,b.id,-take,b.cost);
   cost:=cost+take*b.cost;needed:=needed-take;
  end loop;
  if needed>0 then raise exception 'insufficient_stock' using errcode='22023'; end if;
  total:=q*p.price;
  insert into pharmacy_qa_private.ledger values(doc,'cash',p.currency,total);
 elsif r.operation='purchase_draft' then
  bonus:=(d->>'bonus')::numeric;total:=q*(d->>'unit_cost')::numeric-(d->>'discount')::numeric;
  cost:=total/(q+bonus);
  insert into pharmacy_qa_private.batches(product_id,quantity,cost,expiry) values(p.id,q+bonus,cost,(d->>'expiry')::date) returning id into b;
  insert into pharmacy_qa_private.movements(document_id,batch_id,quantity,cost) values(doc,b.id,q+bonus,cost);
  insert into pharmacy_qa_private.ledger values(doc,'supplier_debt',p.currency,total);
 elsif r.operation='inventory_count' then
  select coalesce(sum(quantity),0) into have from pharmacy_qa_private.batches where product_id=p.id and expiry>=current_date;
  if have<>(d->>'expected_quantity')::numeric then raise exception 'inventory_snapshot_stale' using errcode='22023'; end if;
  needed:=abs(q-have);
  if q<have then
   for b in select * from pharmacy_qa_private.batches where product_id=p.id and expiry>=current_date and quantity>0 order by expiry,id for update loop
    take:=least(needed,b.quantity);if take<=0 then exit; end if;
    update pharmacy_qa_private.batches set quantity=quantity-take where id=b.id;
    insert into pharmacy_qa_private.movements(document_id,batch_id,quantity,cost) values(doc,b.id,-take,b.cost);needed:=needed-take;
   end loop;
  elsif q>have then
   insert into pharmacy_qa_private.batches(product_id,quantity,cost,expiry) values(p.id,needed,0,current_date+365) returning id into b;
   insert into pharmacy_qa_private.movements(document_id,batch_id,quantity,cost) values(doc,b.id,needed,0);
  end if;
 elsif r.operation='return_request' then
  select coalesce(sum(quantity),0) into returned from pharmacy_qa_private.documents where source_id=source.id and kind='return_request';
  if q+returned>source.quantity then raise exception 'return_exceeds_sale' using errcode='22023'; end if;
  needed:=q;
  for b in select m.batch_id,m.cost,-m.quantity-coalesce((select sum(rm.quantity) from pharmacy_qa_private.movements rm join pharmacy_qa_private.documents rd on rd.id=rm.document_id where rd.source_id=source.id and rm.batch_id=m.batch_id),0) available from pharmacy_qa_private.movements m where m.document_id=source.id order by m.id loop
   take:=least(needed,b.available);if take<=0 then continue; end if;
   update pharmacy_qa_private.batches set quantity=quantity+take where id=b.batch_id;
   insert into pharmacy_qa_private.movements(document_id,batch_id,quantity,cost) values(doc,b.batch_id,take,b.cost);
   cost:=cost+take*b.cost;needed:=needed-take;if needed=0 then exit; end if;
  end loop;
  if needed<>0 then raise exception 'return_allocation_mismatch'; end if;
  total:=q*(source.total/source.quantity);
  insert into pharmacy_qa_private.ledger values(doc,'cash',p.currency,-total);
 end if;
 update pharmacy_qa_private.documents set total=op.total,cost=op.cost where id=doc;
 return doc;
end $$;
revoke all on function pharmacy_qa_private.execute_operation(public.qa_employee_operations) from public,anon,authenticated;
-- Replace both reviewer paths only after authorization_functions.sql NULL-role hardening.
create or replace function public.qa_review_employee_operation(p_id uuid,p_approve boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare r public.qa_employee_operations;
begin
 if auth.uid() is null or not coalesce(public.qa_current_system_role() in ('system_owner','system_admin'),false) then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_id is null or p_approve is null then raise exception 'invalid_decision' using errcode='22023'; end if;
 select * into r from public.qa_employee_operations where id=p_id for update;
 if not found or r.status<>'pending' then return false; end if;
 if p_approve and r.payload->>'sandbox'='true' then perform pharmacy_qa_private.execute_operation(r); end if;
 update public.qa_employee_operations set status=case when p_approve then 'approved' else 'rejected' end,decided_at=now(),decided_by=auth.uid() where id=p_id;
 return true;
end $$;
create or replace function public.qa_sandbox_documents()
returns table(id uuid,request_id uuid,kind text,product_id uuid,quantity numeric,total numeric,currency text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 select d.id,d.request_id,d.kind,d.product_id,d.quantity,d.total,d.currency,d.created_at
 from pharmacy_qa_private.documents d where auth.uid() is not null and
 coalesce(public.qa_current_system_role() in ('system_owner','system_admin') or (public.qa_current_system_role()='employee' and d.employee_id=auth.uid()),false)
 order by d.created_at desc,d.id limit 100;
$$;
create or replace function public.qa_sandbox_report()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not coalesce(public.qa_current_system_role() in ('system_owner','system_admin'),false) then raise exception 'not_authorized' using errcode='42501'; end if;
 return jsonb_build_object('balances',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select kind,currency,sum(amount) amount from pharmacy_qa_private.ledger group by kind,currency order by kind,currency) x),'profit',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select currency,sum(case kind when 'sale' then total-cost else cost-total end) amount from pharmacy_qa_private.documents where kind in ('sale','return_request') group by currency) x),'documents',(select count(*) from pharmacy_qa_private.documents));
end $$;
create or replace function public.qa_sandbox_requests() returns table(id uuid,operation text,payload jsonb,status text,decided_by uuid,decided_at timestamptz,created_at timestamptz) language sql stable security definer set search_path='' as $$
 select o.id,o.operation,o.payload,o.status,o.decided_by,o.decided_at,o.created_at from public.qa_employee_operations o where auth.uid() is not null and coalesce(public.qa_current_system_role() in ('system_owner','system_admin') or (public.qa_current_system_role()='employee' and o.employee_id=auth.uid()),false) order by o.created_at desc,o.id limit 100
$$;
revoke all on function public.qa_sandbox_requests() from public,anon;
grant execute on function public.qa_sandbox_requests() to authenticated;
revoke all on function public.qa_sandbox_catalog(),public.qa_submit_sandbox_operation(text,jsonb),public.qa_sandbox_documents(),public.qa_sandbox_report() from public,anon;
grant execute on function public.qa_sandbox_catalog(),public.qa_submit_sandbox_operation(text,jsonb),public.qa_sandbox_documents(),public.qa_sandbox_report() to authenticated;
notify pgrst,'reload schema';
commit;
