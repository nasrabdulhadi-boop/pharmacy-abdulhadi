-- QA ONLY: additive private storage and narrowly authorized RPCs. Never apply to production.
begin;
create table if not exists pharmacy_qa_private.debtors(
 id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 1 and 200),phone text,address text,notes text,
 created_by uuid not null references auth.users(id),request_id uuid not null,created_at timestamptz not null default now(),unique(created_by,request_id));
create table if not exists pharmacy_qa_private.debtor_entries(
 id uuid primary key default gen_random_uuid(),debtor_id uuid not null references pharmacy_qa_private.debtors(id),kind text not null check(kind in ('charge','payment')),
 amount numeric(18,4) not null check(amount>0),currency text not null default 'SYP' check(currency='SYP'),payment_method text check(payment_method in ('cash','other')),
 notes text,actor_id uuid not null references auth.users(id),request_id uuid not null,created_at timestamptz not null default now(),unique(actor_id,request_id));
create index if not exists qa_debtor_entries_account on pharmacy_qa_private.debtor_entries(debtor_id,created_at,id);
create table if not exists pharmacy_qa_private.debtor_cash_receipts(
 entry_id uuid primary key references pharmacy_qa_private.debtor_entries(id),amount numeric(18,4) not null check(amount>0),currency text not null check(currency='SYP'),created_at timestamptz not null default now());
create table if not exists pharmacy_qa_private.audit_events(
 id uuid primary key default gen_random_uuid(),actor_id uuid not null,actor_email text,actor_role text not null,action text not null,
 entity_type text not null,entity_id text,details jsonb not null default '{}',created_at timestamptz not null default now());
create index if not exists qa_audit_events_date on pharmacy_qa_private.audit_events(created_at desc,id);
alter table pharmacy_qa_private.debtors enable row level security;
alter table pharmacy_qa_private.debtor_entries enable row level security;
alter table pharmacy_qa_private.debtor_cash_receipts enable row level security;
alter table pharmacy_qa_private.audit_events enable row level security;
revoke all on pharmacy_qa_private.debtors,pharmacy_qa_private.debtor_entries,pharmacy_qa_private.debtor_cash_receipts,pharmacy_qa_private.audit_events from public,anon,authenticated;
create or replace function pharmacy_qa_private.write_audit(p_action text,p_entity_type text,p_entity_id text,p_details jsonb default '{}',p_event_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare r text:=public.qa_current_system_role();
begin
 if auth.uid() is null or r is null or r not in ('employee','system_admin','system_owner') then return; end if;
 insert into pharmacy_qa_private.audit_events(id,actor_id,actor_email,actor_role,action,entity_type,entity_id,details)
 select coalesce(p_event_id,gen_random_uuid()),auth.uid(),u.email,r,p_action,p_entity_type,p_entity_id,coalesce(p_details,'{}') from auth.users u where u.id=auth.uid()
 on conflict(id) do nothing;
end $$;
revoke all on function pharmacy_qa_private.write_audit(text,text,text,jsonb,uuid) from public,anon,authenticated;
create or replace function pharmacy_qa_private.audit_workspace_mutation() returns trigger language plpgsql security definer set search_path='' as $$
declare before_row jsonb:=case when tg_op='INSERT' then '{}' else to_jsonb(old) end; after_row jsonb:=case when tg_op='DELETE' then '{}' else to_jsonb(new) end; fields text[]; before_safe jsonb; after_safe jsonb; details jsonb; entity text;
begin
 if tg_op='UPDATE' and before_row=after_row then return new; end if;
 fields:=case tg_table_name
 when 'qa_employee_operations' then array['id','employee_id','operation','status','decided_by','decided_at']
 when 'products' then array['id','name','barcode','active_ingredient','strength','dosage_form','manufacturer','category','unit','purchase_price','sale_price','sale_currency','parts_per_unit','reorder_level','active']
 when 'catalog' then array['id','code','title','price','currency','parts']
 when 'batches' then array['id','product_id','quantity','cost','expiry']
 when 'documents' then array['id','request_id','kind','employee_id','product_id','quantity','total','cost','currency','source_id']
 when 'movements' then array['id','document_id','batch_id','quantity','cost']
 when 'ledger' then array['document_id','kind','currency','amount']
 when 'debtors' then array['id','name','created_by']
 when 'debtor_entries' then array['id','debtor_id','kind','amount','currency','payment_method','actor_id']
 else array['entry_id','amount','currency'] end;
 select coalesce(jsonb_object_agg(k,v),'{}') into before_safe from jsonb_each(before_row)e(k,v) where k=any(fields);
 select coalesce(jsonb_object_agg(k,v),'{}') into after_safe from jsonb_each(after_row)e(k,v) where k=any(fields);
 details:=jsonb_build_object('before',before_safe,'after',after_safe,'source','server_transaction');
 if tg_table_name='qa_employee_operations' then details:=details||jsonb_build_object('execution_mode',after_row->'payload'->>'execution_mode','bundle_parent',after_row->'payload'->>'bundle_parent','request_data',after_row->'payload'->'data','lines',after_row->'payload'->'lines','purchase_header',(after_row->'payload'->'purchase_header')-'notes','items_count',case when jsonb_typeof(after_row->'payload'->'lines')='array' then jsonb_array_length(after_row->'payload'->'lines') else 0 end); end if;
 entity:=coalesce(after_row->>'id',before_row->>'id',after_row->>'document_id',before_row->>'document_id',after_row->>'entry_id',before_row->>'entry_id');
 perform pharmacy_qa_private.write_audit(tg_table_name||'_'||lower(tg_op),tg_table_schema||'.'||tg_table_name,entity,details);
 if tg_op='DELETE' then return old; end if;return new;
end $$;
revoke all on function pharmacy_qa_private.audit_workspace_mutation() from public,anon,authenticated;
do $$ declare t text; sch text; begin
 foreach t in array array['qa_employee_operations','products','catalog','batches','documents','movements','ledger','debtors','debtor_entries','debtor_cash_receipts'] loop
  sch:=case when t in ('qa_employee_operations','products') then 'public' else 'pharmacy_qa_private' end;
  execute format('drop trigger if exists qa_employee_audit on %I.%I',sch,t);
  execute format('create trigger qa_employee_audit after insert or update or delete on %I.%I for each row execute function pharmacy_qa_private.audit_workspace_mutation()',sch,t);
 end loop;
end $$;
create or replace function public.qa_create_debtor(p_name text,p_phone text,p_address text,p_notes text,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare r text:=public.qa_current_system_role(); d pharmacy_qa_private.debtors; v_name text:=btrim(p_name);v_phone text:=nullif(btrim(p_phone),'');result uuid;
begin
 if auth.uid() is null or r is null or r not in ('employee','system_admin','system_owner') then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_request_id is null or v_name is null or length(v_name) not between 1 and 200 or length(coalesce(v_phone,''))>40 or length(coalesce(p_address,''))>500 or length(coalesce(p_notes,''))>1000 then raise exception 'invalid_debtor' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_request_id::text,741));
 select * into d from pharmacy_qa_private.debtors where created_by=auth.uid() and request_id=p_request_id;
 if found then
  if d.name=v_name and d.phone is not distinct from v_phone and d.address is not distinct from p_address and d.notes is not distinct from p_notes then return d.id; end if;
  raise exception 'idempotency_conflict' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(lower(v_name)||coalesce(v_phone,''),742));
 if exists(select 1 from pharmacy_qa_private.debtors where lower(name)=lower(v_name) and phone is not distinct from v_phone) then raise exception 'duplicate_debtor' using errcode='23505'; end if;
 insert into pharmacy_qa_private.debtors(name,phone,address,notes,created_by,request_id) values(v_name,v_phone,p_address,p_notes,auth.uid(),p_request_id) returning id into result;
 return result;
end $$;
create or replace function public.qa_list_debtors(p_query text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r text:=public.qa_current_system_role();result jsonb;
begin
 if auth.uid() is null or r is null or r not in ('employee','system_admin','system_owner') then raise exception 'not_authorized' using errcode='42501'; end if;
 if length(coalesce(p_query,''))>200 then raise exception 'invalid_query' using errcode='22023'; end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into result from (
 select d.id,d.name,d.phone,d.address,d.notes,
 coalesce(sum(e.amount) filter(where e.kind='charge'),0) total_debt,coalesce(sum(e.amount) filter(where e.kind='payment'),0) total_paid,
 coalesce(sum(case e.kind when 'charge' then e.amount else -e.amount end),0) balance,coalesce(max(e.created_at),d.created_at) last_activity
 from pharmacy_qa_private.debtors d left join pharmacy_qa_private.debtor_entries e on e.debtor_id=d.id
 where nullif(btrim(p_query),'') is null or position(lower(btrim(p_query)) in lower(d.name||' '||coalesce(d.phone,'')))>0 group by d.id order by d.created_at desc,d.id limit 1000)x;
 perform pharmacy_qa_private.write_audit('debtor_list_viewed','debtors',null,jsonb_build_object('source','server_read','rows',jsonb_array_length(result)));
 return result;
end $$;
create or replace function public.qa_debtor_ledger(p_debtor_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r text:=public.qa_current_system_role();d pharmacy_qa_private.debtors;result jsonb;
begin
 if auth.uid() is null or r is null or r not in ('employee','system_admin','system_owner') then raise exception 'not_authorized' using errcode='42501'; end if;
 select * into d from pharmacy_qa_private.debtors where id=p_debtor_id;if not found then raise exception 'debtor_not_found' using errcode='22023'; end if;
 select jsonb_build_object('debtor',jsonb_build_object('id',d.id,'name',d.name,'phone',d.phone,'address',d.address,'notes',d.notes),'balance',coalesce(sum(case kind when 'charge' then amount else -amount end),0),'transactions',coalesce(jsonb_agg(jsonb_build_object('id',id,'type',case kind when 'payment' then 'payment' else 'adjustment' end,'debit',case kind when 'charge' then amount else 0 end,'credit',case kind when 'payment' then amount else 0 end,'notes',notes,'payment_method',payment_method,'currency',currency,'balance_after',balance_after,'created_at',created_at) order by created_at desc,id),'[]')) into result from(select e.*,sum(case kind when 'charge' then amount else -amount end) over(order by created_at,id) balance_after from pharmacy_qa_private.debtor_entries e where debtor_id=d.id)t;
 perform pharmacy_qa_private.write_audit('debtor_ledger_viewed','debtors',d.id::text,jsonb_build_object('source','server_read'));
 return result;
end $$;
create or replace function public.qa_record_debtor_payment(p_debtor_id uuid,p_amount numeric,p_notes text,p_payment_method text,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare r text:=public.qa_current_system_role();balance numeric;old_entry pharmacy_qa_private.debtor_entries;result uuid;
begin
 if auth.uid() is null or r is null or r not in ('employee','system_admin','system_owner') then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_request_id is null or p_amount is null or p_amount not between 0.0001 and 100000000 or p_amount<>round(p_amount,4) or p_payment_method is null or p_payment_method not in ('cash','other') or length(coalesce(p_notes,''))>1000 then raise exception 'invalid_payment' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_request_id::text,743));
 select * into old_entry from pharmacy_qa_private.debtor_entries where actor_id=auth.uid() and request_id=p_request_id;
 if found then
  if old_entry.kind='payment' and old_entry.debtor_id=p_debtor_id and old_entry.amount=p_amount and old_entry.payment_method=p_payment_method and old_entry.notes is not distinct from p_notes then return old_entry.id; end if;
  raise exception 'idempotency_conflict' using errcode='22023';
 end if;
 perform 1 from pharmacy_qa_private.debtors where id=p_debtor_id for update;
 if not found then raise exception 'debtor_not_found' using errcode='22023'; end if;
 select coalesce(sum(case kind when 'charge' then amount else -amount end),0) into balance from pharmacy_qa_private.debtor_entries where debtor_id=p_debtor_id;
 if p_amount>balance then raise exception 'payment_exceeds_debt' using errcode='22023'; end if;
 insert into pharmacy_qa_private.debtor_entries(debtor_id,kind,amount,payment_method,notes,actor_id,request_id) values(p_debtor_id,'payment',p_amount,p_payment_method,p_notes,auth.uid(),p_request_id) returning id into result;
 if p_payment_method='cash' then insert into pharmacy_qa_private.debtor_cash_receipts(entry_id,amount,currency) values(result,p_amount,'SYP'); end if;
 return result;
end $$;
create or replace function public.qa_security_audit(p_limit integer default 150)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not coalesce(public.qa_current_system_role() in ('system_admin','system_owner'),false) then raise exception 'not_authorized' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select id,actor_id as user_id,actor_email,actor_role,action,entity_type,entity_id,details,created_at from pharmacy_qa_private.audit_events order by created_at desc,id limit least(greatest(coalesce(p_limit,150),1),500))x);
end $$;
create or replace function public.qa_record_workspace_access(p_section text,p_request_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or public.qa_current_system_role() is distinct from 'employee' then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_request_id is null or p_section is null or p_section not in ('dashboard','pos','pharmacyProducts','siteProducts','inventory','smart','purchases','suppliers','supplierDebts','orders','prescriptions','requests','customers','debtors','offers','cashbox','returns','reports','profitCenterPreview','systemCenter','security') then raise exception 'invalid_section' using errcode='22023'; end if;
 perform pharmacy_qa_private.write_audit('workspace_visit','workspace',p_section,jsonb_build_object('source','client_reported_navigation'),p_request_id);
 return true;
end $$;
revoke all on function public.qa_create_debtor(text,text,text,text,uuid),public.qa_list_debtors(text),public.qa_debtor_ledger(uuid),public.qa_record_debtor_payment(uuid,numeric,text,text,uuid),public.qa_security_audit(integer),public.qa_record_workspace_access(text,uuid) from public,anon;
grant execute on function public.qa_create_debtor(text,text,text,text,uuid),public.qa_list_debtors(text),public.qa_debtor_ledger(uuid),public.qa_record_debtor_payment(uuid,numeric,text,text,uuid),public.qa_security_audit(integer),public.qa_record_workspace_access(text,uuid) to authenticated;
-- Extend manager-only QA cash accounting; debtor receipts are collections, never sales/profit.
create or replace function public.qa_sandbox_report() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not coalesce(public.qa_current_system_role() in ('system_owner','system_admin'),false) then raise exception 'not_authorized' using errcode='42501'; end if;
 return jsonb_build_object('balances',(select coalesce(jsonb_agg(x),'[]') from(select kind,currency,sum(amount) amount from(select kind,currency,amount from pharmacy_qa_private.ledger union all select 'cash',currency,amount from pharmacy_qa_private.debtor_cash_receipts)l group by kind,currency order by kind,currency)x),
 'profit',(select coalesce(jsonb_agg(x),'[]') from(select currency,sum(case kind when 'sale' then total-cost else cost-total end) amount from pharmacy_qa_private.documents where kind in ('sale','return_request') group by currency)x),'documents',(select count(*) from pharmacy_qa_private.documents),
 'cash_entries',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]') from(
 select d.id,d.created_at,case d.kind when 'sale' then 'sale_cash' when 'return_request' then 'customer_return_refund' else 'income' end type,l.amount,l.currency,coalesce(d.kind,'QA') description
 from pharmacy_qa_private.ledger l join pharmacy_qa_private.documents d on d.id=l.document_id where l.kind='cash'
 union all select r.entry_id,r.created_at,'debtor_payment',r.amount,r.currency,'تحصيل دين — '||d.name from pharmacy_qa_private.debtor_cash_receipts r join pharmacy_qa_private.debtor_entries e on e.id=r.entry_id join pharmacy_qa_private.debtors d on d.id=e.debtor_id)x));
end $$;
notify pgrst,'reload schema';
commit;
