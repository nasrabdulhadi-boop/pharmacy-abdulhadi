-- Isolated QA workspace only.
create table if not exists pharmacy_qa_private.operating_controls (
 version bigint generated always as identity primary key,
 actor uuid not null,
 created_at timestamptz not null default now(),
 return_days integer not null check (return_days between 0 and 365),
 return_behavior text not null check (return_behavior in ('warn','block','approve')),
 paused_operation text check (paused_operation in ('sale','purchase_draft','inventory_count','return_request','order_process')),
 paused_until timestamptz,
 reason text not null
);
alter table pharmacy_qa_private.operating_controls enable row level security;
revoke all on table pharmacy_qa_private.operating_controls from public,anon,authenticated;

create or replace function public.qa_operating_controls()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not coalesce(public.qa_current_system_role() in ('system_admin','system_owner'),false)
 then raise exception 'not_authorized' using errcode='42501';end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.version desc)
 from (select * from pharmacy_qa_private.operating_controls order by version desc limit 20) x),'[]'::jsonb);
end $$;

create or replace function public.qa_save_operating_controls(
 p_expected_version bigint,p_return_days integer,p_return_behavior text,
 p_paused_operation text,p_minutes integer,p_reason text
) returns bigint language plpgsql security definer set search_path='' as $$
declare previous pharmacy_qa_private.operating_controls; saved bigint;
begin
 if auth.uid() is null or not coalesce(public.qa_current_system_role() in ('system_admin','system_owner'),false)
 then raise exception 'not_authorized' using errcode='42501';end if;
 if char_length(coalesce(btrim(p_reason),'')) not between 3 and 400
 or (p_paused_operation is not null and (p_minutes is null or p_minutes not between 1 and 1440))
 then raise exception 'invalid_controls' using errcode='22023';end if;
 perform pg_advisory_xact_lock(413728029);
 select * into previous from pharmacy_qa_private.operating_controls order by version desc limit 1;
 if coalesce(previous.version,0) is distinct from p_expected_version then raise exception 'stale_controls' using errcode='40001';end if;
 insert into pharmacy_qa_private.operating_controls(actor,return_days,return_behavior,paused_operation,paused_until,reason)
 values(auth.uid(),p_return_days,p_return_behavior,case when p_minutes=-1 then previous.paused_operation else p_paused_operation end,
 case when p_minutes=-1 then previous.paused_until when p_paused_operation is not null then now()+make_interval(mins=>p_minutes) end,btrim(p_reason))
 returning version into saved;
 return saved;
end $$;

-- Assert rules when a QA document is created, including queued operations upon execution.
create or replace function pharmacy_qa_private.enforce_operating_controls()
returns trigger language plpgsql security definer set search_path='' as $$
declare cfg pharmacy_qa_private.operating_controls; sold timestamptz; warning boolean:=false;
begin
 select * into cfg from pharmacy_qa_private.operating_controls order by version desc limit 1;
 if not found then return new;end if;
 if new.kind=cfg.paused_operation and cfg.paused_until>now() then
  raise exception 'qa_operation_paused' using errcode='22023';
 end if;
 if new.kind='return_request' and new.source_id is not null then
  select created_at into sold from pharmacy_qa_private.documents where id=new.source_id;
  if sold+make_interval(days=>cfg.return_days)<now() then
   if cfg.return_behavior='block' then raise exception 'qa_return_window_exceeded' using errcode='22023';end if;
   if cfg.return_behavior='approve' and not coalesce(public.qa_current_system_role() in ('system_admin','system_owner'),false)
   then raise exception 'qa_return_manager_approval_required' using errcode='42501';end if;
   warning:=cfg.return_behavior='warn';
  end if;
 end if;
 insert into pharmacy_qa_private.audit_events(actor_id,actor_email,actor_role,action,entity_type,entity_id,details)
 select u.id,u.email,public.qa_current_system_role(),'qa_operating_rule_checked','document',new.id::text,
        jsonb_build_object('version',cfg.version,'kind',new.kind,'return_warning',warning)
 from auth.users u where u.id=auth.uid();
 return new;
end $$;
revoke all on function public.qa_operating_controls(),public.qa_save_operating_controls(bigint,integer,text,text,integer,text) from public,anon;
grant execute on function public.qa_operating_controls(),public.qa_save_operating_controls(bigint,integer,text,text,integer,text) to authenticated;
revoke all on function pharmacy_qa_private.enforce_operating_controls() from public,anon,authenticated;
create or replace trigger qa_operating_policy before insert on pharmacy_qa_private.documents
for each row execute function pharmacy_qa_private.enforce_operating_controls();

create or replace function public.qa_operation_impact(p_document uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare item pharmacy_qa_private.documents;
begin
 if auth.uid() is null or not coalesce(public.qa_current_system_role() in ('system_admin','system_owner'),false)
 then raise exception 'not_authorized' using errcode='42501';end if;
 select * into item from pharmacy_qa_private.documents where id=p_document;
 if not found then raise exception 'document_not_found' using errcode='22023';end if;
 return jsonb_build_object('kind',item.kind,'currency',item.currency,'quantity',item.quantity,'total',item.total,
 'ledger',(select to_jsonb(l) from pharmacy_qa_private.ledger l where l.document_id=item.id),
 'movements',(select coalesce(jsonb_agg(jsonb_build_object('batch',m.batch_id,'quantity',m.quantity,
 'cost',m.cost,'later_links',(select count(*) from pharmacy_qa_private.movements other
 where other.batch_id=m.batch_id and other.id>m.id and other.document_id<>m.document_id)) order by m.id),'[]')
 from pharmacy_qa_private.movements m where m.document_id=item.id),
 'linked_returns',(select count(*) from pharmacy_qa_private.documents r where r.source_id=item.id));
end $$;
revoke all on function public.qa_operation_impact(uuid) from public,anon;
grant execute on function public.qa_operation_impact(uuid) to authenticated;
