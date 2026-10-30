begin;
-- Share the existing validated QA implementation without granting admin authority to employee endpoints.
do $do$ declare definition text;begin
 select pg_get_functiondef('public.qa_submit_sandbox_operation(text,jsonb)'::regprocedure) into definition;
 definition:=replace(definition,'public.qa_submit_sandbox_operation','pharmacy_qa_private.submit_validated_operation');
 definition:=regexp_replace(definition,$old$public\.qa_current_system_role\(\) IS DISTINCT FROM 'employee'$old$,$new$not coalesce(public.qa_current_system_role() in ('employee','system_owner','system_admin'),false)$new$,'gi');
 execute definition;
 select pg_get_functiondef('public.qa_submit_workspace_bundle(text,jsonb,text)'::regprocedure) into definition;
 definition:=replace(definition,'public.qa_submit_workspace_bundle','pharmacy_qa_private.submit_workspace_bundle');
 definition:=replace(definition,'public.qa_submit_sandbox_operation','pharmacy_qa_private.submit_validated_operation');
 definition:=regexp_replace(definition,$old$public\.qa_current_system_role\(\) IS DISTINCT FROM 'employee'$old$,$new$not coalesce(public.qa_current_system_role() in ('employee','system_owner','system_admin'),false)$new$,'gi');
 execute definition;
end $do$;
revoke all on function pharmacy_qa_private.submit_validated_operation(text,jsonb),pharmacy_qa_private.submit_workspace_bundle(text,jsonb,text) from public,anon,authenticated;
create or replace function public.qa_manager_execute_workspace(p_operation text,p_payloads jsonb,p_currency text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare request uuid;
begin
 if auth.uid() is null or not coalesce(public.qa_current_system_role() in ('system_owner','system_admin'),false) then raise exception 'not_authorized' using errcode='42501'; end if;
 request:=pharmacy_qa_private.submit_workspace_bundle(p_operation,p_payloads,p_currency);
 if not public.qa_review_employee_operation(request,true) then raise exception 'manager_execution_failed'; end if;
 return request;
end $$;
revoke all on function public.qa_manager_execute_workspace(text,jsonb,text) from public,anon;
grant execute on function public.qa_manager_execute_workspace(text,jsonb,text) to authenticated;
notify pgrst,'reload schema';
commit;
