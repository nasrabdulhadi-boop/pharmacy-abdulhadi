-- Staff and recovery-mailbox Auth identities cannot assume the ordinary API role.
do $$ begin
 if exists(select from pg_roles where rolname='pharmacy_workspace_only') then raise exception 'Reserved role exists';end if;
end $$;
create function pharmacy_branch_private.workspace_identity_guard() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.role is distinct from 'pharmacy_workspace_only' then raise exception 'Invalid workspace identity role';end if;
 return new;
end $$;
revoke all on function pharmacy_branch_private.workspace_identity_guard() from public,anon,authenticated;
create trigger manager_workspace_identity_guard before insert or update on auth.users for each row
when (new.raw_app_meta_data->>'workspace_issuer'='pharmacy_manager_v1')
execute function pharmacy_branch_private.workspace_identity_guard();

create table public.manager_recovery_contacts(
 manager_id uuid primary key references auth.users on delete cascade,
 mailbox_id uuid unique not null references auth.users on delete cascade,
 email text not null, verified_at timestamptz not null default now(),check(manager_id<>mailbox_id)
);
alter table public.manager_recovery_contacts enable row level security;
revoke all on public.manager_recovery_contacts from public,anon,authenticated;
grant select,insert,update on public.manager_recovery_contacts to service_role;

create function public.manager_staff_directory() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,'name',u.raw_app_meta_data->>'staff_name','kind',u.raw_app_meta_data->>'staff_kind','sections',u.raw_app_meta_data->'sections') order by u.created_at),'[]'::jsonb)
 from auth.users u where pharmacy_branch_private.manager_role() in ('system_admin','system_owner') and u.role='pharmacy_workspace_only'
 and u.raw_app_meta_data->>'workspace_issuer'='pharmacy_manager_v1' and u.raw_app_meta_data->>'manager_id'=auth.uid()::text and u.raw_app_meta_data->>'staff_kind' in ('employee','support');
$$;
revoke all on function public.manager_staff_directory() from public,anon;
grant execute on function public.manager_staff_directory() to authenticated;

create function public.manager_staff_view(p_actor uuid,p_section text,p_search text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare meta jsonb; result jsonb; q text:=left(coalesce(trim(p_search),''),100);
begin
 select raw_app_meta_data into meta from auth.users where id=p_actor and role='pharmacy_workspace_only'
 and raw_app_meta_data->>'workspace_issuer'='pharmacy_manager_v1' and (banned_until is null or banned_until<=now());
 if meta is null or not coalesce((meta->'sections') ? p_section,false) then raise exception 'Section denied' using errcode='42501';end if;
 if p_section='diagnostics' and meta->>'staff_kind'='support' then return jsonb_build_array(jsonb_build_object('الخدمة','اتصال قاعدة البيانات','الحالة','متصل'));end if;
 if meta->>'staff_kind'<>'employee' then raise exception 'Section denied';end if;
 if p_section in ('products','inventory','pos') then
 select jsonb_agg(to_jsonb(t)) into result from (select p.id,p.name as "الصنف", p.sale_price as "السعر",p.sale_currency as "العملة", case when upper(coalesce(p.sale_currency,'SYP'))='USD' then p.sale_price*(select usd_to_syp from public.pharmacy_currency_settings where id=1) else p.sale_price end as "البيع بالليرة",p.barcode as "الباركود",
 (select coalesce(sum(b.quantity),0) from public.batches b where b.product_id=p.id and b.quantity>0 and (b.expiry_date is null or b.expiry_date>=current_date)) as "الرصيد المتاح"
 from public.products p where p.active and (q='' or strpos(lower(p.name),lower(q))>0 or p.barcode=q) order by p.name,p.id limit 75)t;
 elsif p_section='suppliers' then select jsonb_agg(to_jsonb(t)) into result from (select name as "المورد" from public.suppliers where strpos(lower(name),lower(q))>0 order by name limit 75)t;
 elsif p_section='purchases' then select jsonb_agg(to_jsonb(t)) into result from (select invoice_number as "فاتورة الشراء",invoice_date as "التاريخ" from public.purchases where strpos(coalesce(invoice_number::text,''),q)>0 or q='' order by created_at desc limit 75)t;
 elsif p_section='debtors' then select jsonb_agg(to_jsonb(t)) into result from (select d.id,d.name as "الاسم",(select coalesce(sum(coalesce(x.debit,0)-coalesce(x.credit,0)),0) from public.debtor_transactions x where x.debtor_id=d.id and coalesce(x.currency,'SYP')='SYP') as "الرصيد بالليرة" from public.debtors d where d.active and strpos(lower(d.name),lower(q))>0 order by d.name limit 75)t;
 else raise exception 'Section unavailable';end if;
 return coalesce(result,'[]');
end $$;
revoke all on function public.manager_staff_view(uuid,text,text) from public,anon,authenticated;
grant execute on function public.manager_staff_view(uuid,text,text) to service_role;
create function public.manager_find_mailbox(p_manager uuid,p_email text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select from auth.users where lower(email)=p_email and role='pharmacy_workspace_only' and raw_app_meta_data->>'workspace_issuer'='pharmacy_manager_v1' and raw_app_meta_data->>'staff_kind'='mailbox' and raw_app_meta_data->>'manager_id'=p_manager::text);
$$;
revoke all on function public.manager_find_mailbox(uuid,text) from public,anon,authenticated;
grant execute on function public.manager_find_mailbox(uuid,text) to service_role;

-- Scoped copies preserve the verified production accounting logic and actor attribution.
do $copies$
declare f record; definition text; sig text;
begin
 for f in select p.oid,p.proname,p.prosrc,md5(p.prosrc) fingerprint,pg_get_function_identity_arguments(p.oid) args
 from pg_proc p where p.pronamespace='public'::regnamespace and p.proname in ('complete_sale_accounting_currency','admin_create_debtor','admin_record_debtor_payment') loop
 if f.fingerprint not in ('2ecfba6e5a82a9a49256351b681aeecf','86bd8a4f44f077034ff814b0c3636c24','52847ff39b6f4f487c85aa8b7f743f81') or strpos(lower(f.prosrc),'if not public.is_admin()')=0 then raise exception 'Accounting definition has changed';end if;
 definition:=replace(pg_get_functiondef(f.oid),'FUNCTION public.'||f.proname||'(','FUNCTION pharmacy_branch_private.staff_'||f.proname||'(');
 definition:=regexp_replace(definition,'IF NOT public\.is_admin\(\)', 'IF current_setting(''pharmacy.staff_command'',true) IS DISTINCT FROM ''verified''','i');
 execute definition;
 sig:=format('pharmacy_branch_private.staff_%I(%s)',f.proname,f.args);
 execute 'revoke all on function '||sig||' from public,anon,authenticated,service_role';
 end loop;
end $copies$;
create table pharmacy_branch_private.staff_receipts (
 actor uuid not null, request_id uuid not null,operation text not null, payload jsonb not null,result jsonb not null, primary key(actor,request_id)
);
alter table pharmacy_branch_private.staff_receipts enable row level security;
revoke all on pharmacy_branch_private.staff_receipts from public,anon,authenticated;
create function public.manager_staff_command(p_actor uuid,p_request uuid,p_op text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare scope text; old pharmacy_branch_private.staff_receipts; result jsonb; items jsonb;
begin
 scope:=case p_op when 'sale' then 'pos' when 'add_product' then 'products' when 'add_debtor' then 'debtors' when 'pay_debtor' then 'debtors' end;
 if p_request is null or scope is null or not exists(select from auth.users where id=p_actor and role='pharmacy_workspace_only' and raw_app_meta_data->>'workspace_issuer'='pharmacy_manager_v1' and raw_app_meta_data->>'staff_kind'='employee' and raw_app_meta_data->'sections' ? scope and (banned_until is null or banned_until<=now())) then raise exception 'Section denied';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request::text,1));
 select * into old from pharmacy_branch_private.staff_receipts where actor=p_actor and request_id=p_request;
 if found then if old.payload=p_payload and old.operation=p_op then return old.result;end if;raise exception 'Request changed';end if;
 perform set_config('request.jwt.claim.sub',p_actor::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',p_actor)::text,true);
 perform set_config('pharmacy.staff_command','verified',true);
 if p_op='sale' then
 if jsonb_typeof(p_payload->'items') is distinct from 'array' or jsonb_array_length(p_payload->'items') not between 1 and 100 then raise exception 'Invalid cart';end if;
 perform 1 from public.pharmacy_currency_settings where id=1 for share;
 perform 1 from public.products p where p.id in(select (x->>'product_id')::uuid from jsonb_array_elements(p_payload->'items') x) order by p.id for share;
 if exists(select from jsonb_array_elements(p_payload->'items') x left join public.products p on p.id=(x->>'product_id')::uuid
 where p.id is null or (x->>'expected_price')::numeric is null or (x->>'expected_price')::numeric is distinct from
 case when upper(coalesce(p.sale_currency,'SYP'))='USD' then p.sale_price*(select usd_to_syp from public.pharmacy_currency_settings where id=1) else p.sale_price end) then raise exception 'Price changed';end if;
 select jsonb_agg(jsonb_build_object('product_id',(x->>'product_id')::uuid,'quantity',(x->>'quantity')::numeric) order by x->>'product_id') into items from jsonb_array_elements(p_payload->'items') x;
 if exists(select from jsonb_array_elements(items) x where x->>'quantity' is null or (x->>'quantity')::numeric not between 1 and 100000 or trunc((x->>'quantity')::numeric)<>(x->>'quantity')::numeric) then raise exception 'Invalid quantity';end if;
 result:=pharmacy_branch_private.staff_complete_sale_accounting_currency('SYP',null,0,null,items,'بيع موظف','cash');
 elsif p_op='add_product' then
 if nullif(trim(p_payload->>'name'),'') is null or length(p_payload->>'name')>160 or nullif(trim(p_payload->>'barcode'),'') is null or length(p_payload->>'barcode')>80
 or (p_payload->>'price') is null or (p_payload->>'price')::numeric not between 0 and 1000000000 then raise exception 'Invalid product';end if;
 perform pg_advisory_xact_lock(hashtextextended(trim(p_payload->>'barcode'),42));
 if exists(select from public.product_barcodes where barcode=trim(p_payload->>'barcode')) or exists(select from public.products where barcode=trim(p_payload->>'barcode')) then raise exception 'Barcode already used';end if;
 insert into public.products(name,barcode,sale_price,sale_currency,active,customer_visible,unit,parts_per_unit,reorder_level) values(trim(p_payload->>'name'),trim(p_payload->>'barcode'),(p_payload->>'price')::numeric,'SYP',true,false,'علبة',1,0) returning to_jsonb(id) into result;
 insert into public.audit_logs(user_id,action,entity_type,entity_id,details) values(p_actor,'staff_create_product','product',(result#>>'{}')::uuid,jsonb_build_object('name',p_payload->>'name'));
 elsif p_op='add_debtor' then result:=to_jsonb(pharmacy_branch_private.staff_admin_create_debtor(left(p_payload->>'name',120),null,null,null));
 else
 if (p_payload->>'amount') is null or (p_payload->>'amount')::numeric not between 1 and 1000000000000 then raise exception 'Invalid amount';end if;
 result:=pharmacy_branch_private.staff_admin_record_debtor_payment((p_payload->>'id')::uuid,(p_payload->>'amount')::numeric,'دفعة بواسطة موظف','cash');
 end if;
 insert into pharmacy_branch_private.staff_receipts values(p_actor,p_request,p_op,p_payload,result);
 return result;
end $$;
revoke all on function public.manager_staff_command(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.manager_staff_command(uuid,uuid,text,jsonb) to service_role;
create table pharmacy_branch_private.used_mail_sessions(id uuid primary key,used_at timestamptz default now());
revoke all on pharmacy_branch_private.used_mail_sessions from public,anon,authenticated;
create function public.manager_consume_mail_session(p_user uuid,p_session uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not exists(select from auth.sessions where id=p_session and user_id=p_user and (not_after is null or not_after>now())) then return false;end if;
 insert into pharmacy_branch_private.used_mail_sessions(id) values(p_session) on conflict do nothing;
 return found;
end $$;
revoke all on function public.manager_consume_mail_session(uuid,uuid) from public,anon,authenticated;
grant execute on function public.manager_consume_mail_session(uuid,uuid) to service_role;
