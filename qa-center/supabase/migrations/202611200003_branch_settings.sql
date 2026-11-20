alter table public.qa_branches add column status text not null default 'active' check(status in ('active','paused','archived'));
create policy qa_branch_status_gate on public.qa_branches as restrictive for select to authenticated using(owner_id=auth.uid() or status='active');
create function public.qa_branch_update(p_branch uuid,p_name text,p_status text,p_expected_name text,p_expected_status text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if public.qa_current_system_role() in ('system_admin','system_owner') then
 update public.qa_branches set name=btrim(p_name),status=p_status where owner_id=auth.uid() and id=p_branch and name=p_expected_name and status=p_expected_status;
 if found then return;end if;
 end if;raise exception 'branch unavailable or changed';
end $$;
revoke all on function public.qa_branch_update(uuid,text,text,text,text) from public,anon;
grant execute on function public.qa_branch_update(uuid,text,text,text,text) to authenticated;
do $patch$
declare def text;
begin
 def:=pg_get_functiondef('qa_branch_private.can_operate(uuid)'::regprocedure);
 if strpos(def,'where b.id = p_branch and (')=0 then raise exception 'unexpected branch access definition';end if;
 execute replace(def,'where b.id = p_branch and (','where b.id = p_branch and b.status=''active'' and (');
 def:=pg_get_functiondef('public.qa_branch_day(date,uuid)'::regprocedure);
 if strpos(def,'b.location, b.invite_email')=0 then raise exception 'unexpected report definition';end if;
 execute replace(replace(def,'b.location, b.invite_email','b.location, b.status, b.invite_email'),'b.location,b.invite_email','b.location,b.status,b.invite_email');
end $patch$;
