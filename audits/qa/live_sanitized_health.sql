-- QA ONLY. Same endpoint signature; no table/data changes.
create or replace function public.qa_support_health() returns table(component text,status text)
language sql stable security definer set search_path='' as $$
 select x.component,x.status
 from (values ('database','healthy'),('authentication','healthy'),('api','unknown'),('deployment','unknown')) x(component,status)
 where auth.uid() is not null and coalesce(public.qa_current_system_role() in ('technical_support','system_owner','system_admin'),false)
$$;
revoke all on function public.qa_support_health() from public,anon;
grant execute on function public.qa_support_health() to authenticated;
