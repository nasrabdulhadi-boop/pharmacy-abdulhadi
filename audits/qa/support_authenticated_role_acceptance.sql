begin;
do $fixture$
declare u uuid:=gen_random_uuid(); s uuid:=gen_random_uuid();
begin
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values(u,'authenticated','authenticated','qa-support-test-'||u||'@example.invalid',now(),'{"system_role":"technical_support"}','{}',now(),now());
insert into auth.sessions(id,user_id,aal,created_at,updated_at,not_after) values(s,u,'aal1',now(),now(),now()+interval '1 hour');
perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'session_id',s,'role','authenticated')::text,true);
end $fixture$;
set local role authenticated;
do $checks$
declare r jsonb; n integer; denied boolean;
begin
if current_user<>'authenticated' then raise exception 'role test invalid';end if;
if public.qa_my_role()<>'technical_support' then raise exception 'support role invalid';end if;
r:=public.qa_workspace_snapshot();
if (select array_agg(k order by k) from jsonb_object_keys(r) k)<>array['health','role'] then raise exception 'snapshot leaks extra fields';end if;
select count(*) into n from public.admin_get_products_page(5,0);
if n<>0 then raise exception 'privileged RPC leaked rows';end if;
denied:=false;
begin select count(*) into n from public.products; denied:=n=0; exception when insufficient_privilege then denied:=true;end;
if not denied then raise exception 'direct products leak';end if;
denied:=false;
begin perform public.qa_list_debtors();exception when insufficient_privilege then denied:=true;end;
if not denied then raise exception 'debtors leak';end if;
denied:=false;
begin perform public.qa_security_audit();exception when insufficient_privilege then denied:=true;end;
if not denied then raise exception 'audit leak';end if;
if has_schema_privilege(current_user,'pharmacy_qa_private','USAGE') then raise exception 'private schema exposed';end if;
end $checks$;
select jsonb_build_object('passed',8,'role',current_user,'mode','actual authenticated database role; synthetic session; not signed HTTP JWT') as result;
reset role;
rollback;
