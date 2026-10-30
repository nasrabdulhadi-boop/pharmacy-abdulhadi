-- QA-only. Enforce current server role and live Auth session on every protected call.
CREATE OR REPLACE FUNCTION public.qa_current_system_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 select case when u.raw_app_meta_data->>'system_role' in ('system_owner','system_admin','technical_support','employee') then u.raw_app_meta_data->>'system_role'
 when not (u.raw_app_meta_data ? 'system_role') and u.raw_app_meta_data->>'role'='admin' then 'system_admin' else null end
 from auth.users u join auth.sessions s on s.user_id=u.id
 where u.id=auth.uid() and s.id::text=(auth.jwt()->>'session_id') and (s.not_after is null or s.not_after>now()) and (u.banned_until is null or u.banned_until<=now())
 limit 1
$function$;
CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 select auth.uid() is not null and coalesce(public.qa_current_system_role() in ('system_owner','system_admin'),false)
$function$;
CREATE OR REPLACE FUNCTION public.qa_list_employee_operations()
 RETURNS TABLE(id uuid, operation text, status text, created_at timestamptz, decided_at timestamptz)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 select o.id,o.operation,o.status,o.created_at,o.decided_at from public.qa_employee_operations o
 where auth.uid() is not null and coalesce(public.qa_current_system_role() in ('system_owner','system_admin') or
 (public.qa_current_system_role()='employee' and o.employee_id=auth.uid()),false)
 order by o.created_at desc,o.id limit 100
$function$;
CREATE OR REPLACE FUNCTION public.qa_my_staff_approvals()
 RETURNS TABLE(id uuid, action_type text, status text, created_at timestamptz, decided_at timestamptz)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $function$
 select r.id,r.action_type,r.status,r.created_at,r.decided_at from public.qa_staff_approval_requests r
 where auth.uid() is not null and coalesce(public.qa_current_system_role() in ('system_owner','system_admin') or
 (public.qa_current_system_role()='employee' and r.requested_by=auth.uid()),false)
 order by r.created_at desc,r.id limit 100
$function$;

CREATE OR REPLACE FUNCTION public.qa_support_health() RETURNS TABLE(component text,status text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 select x.component,x.status from (values ('database','unknown'),('authentication','unknown'),('api','unknown'),('deployment','unknown'))x(component,status) where auth.uid() is not null and coalesce(public.qa_current_system_role() in ('technical_support','system_owner','system_admin'),false)
$$;
