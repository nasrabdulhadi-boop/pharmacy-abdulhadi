-- QA-only remediation, inspected and applied to vpjxdsprfcpqclnhbeoh.
-- Never apply to production. NULL/unknown roles must fail closed.
CREATE OR REPLACE FUNCTION public.qa_current_system_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$ select case when u.raw_app_meta_data->>'system_role' in ('system_owner','system_admin','technical_support','employee') then u.raw_app_meta_data->>'system_role' else null end from auth.users u where u.id=auth.uid() $function$
;
CREATE OR REPLACE FUNCTION public.qa_decide_staff_approval(p_id uuid, p_approve boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
 if auth.uid() is null or NOT COALESCE(public.qa_current_system_role() in ('system_owner','system_admin'),false) then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_id is null or p_approve is null then raise exception 'invalid_decision' using errcode='22023'; end if;
 update public.qa_staff_approval_requests set status=case when p_approve then 'approved' else 'rejected' end,decided_at=now(),decided_by=auth.uid() where id=p_id and status='pending';
 return found;
end $function$
;
CREATE OR REPLACE FUNCTION public.qa_list_employee_operations()
 RETURNS TABLE(id uuid, operation text, status text, created_at timestamp with time zone, decided_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
select o.id,o.operation,o.status,o.created_at,o.decided_at from public.qa_employee_operations o
where auth.uid() is not null and
 (o.employee_id=auth.uid() or public.qa_current_system_role() in ('system_owner','system_admin'))
order by o.created_at desc limit 100 $function$
;
CREATE OR REPLACE FUNCTION public.qa_my_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
select public.qa_current_system_role() $function$
;
CREATE OR REPLACE FUNCTION public.qa_my_staff_approvals()
 RETURNS TABLE(id uuid, action_type text, status text, created_at timestamp with time zone, decided_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
select r.id,r.action_type,r.status,r.created_at,r.decided_at from public.qa_staff_approval_requests r where auth.uid() is not null and (r.requested_by=auth.uid() or public.qa_current_system_role() in ('system_owner','system_admin')) order by r.created_at desc limit 100 $function$
;
CREATE OR REPLACE FUNCTION public.qa_review_employee_operation(p_id uuid, p_approve boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
 if auth.uid() is null or NOT COALESCE(public.qa_current_system_role() in ('system_owner','system_admin'),false) then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_id is null or p_approve is null then raise exception 'invalid_decision' using errcode='22023'; end if;
 update public.qa_employee_operations set status=case when p_approve then 'approved' else 'rejected' end,decided_at=now(),decided_by=auth.uid() where id=p_id and status='pending';
 return found;
end $function$
;
CREATE OR REPLACE FUNCTION public.qa_submit_employee_operation(p_operation text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_id uuid;
begin
 if auth.uid() is null or public.qa_current_system_role() IS DISTINCT FROM 'employee' then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_operation is null or p_operation not in ('sale','inventory_count','purchase_draft','order_process','return_request') then raise exception 'invalid_operation' using errcode='22023'; end if;
 if p_payload is null or p_payload <> '{}'::jsonb then raise exception 'payload_not_supported_in_qa' using errcode='22023'; end if;
 insert into public.qa_employee_operations(employee_id,operation,payload) values(auth.uid(),p_operation,'{}'::jsonb) returning id into v_id;
 return v_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.qa_submit_staff_approval(p_action text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_id uuid;
begin
 if auth.uid() is null or public.qa_current_system_role() IS DISTINCT FROM 'employee' then raise exception 'not_authorized' using errcode='42501'; end if;
 if p_action is null or p_action not in ('inventory_count','purchase_draft','return_request') then raise exception 'invalid_action' using errcode='22023'; end if;
 insert into public.qa_staff_approval_requests(requested_by,action_type) values(auth.uid(),p_action) returning id into v_id;
 return v_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.qa_support_health()
 RETURNS TABLE(component text, status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
select x.component,x.status from (values ('database','healthy'),('authentication','unknown'),('api','unknown'),('deployment','unknown')) x(component,status) where auth.uid() is not null and public.qa_current_system_role() in ('technical_support','system_owner','system_admin') $function$
;
