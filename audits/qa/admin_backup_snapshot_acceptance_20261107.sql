-- Run after installing the QA snapshot functions. Fixtures and all assertions roll back.
begin;
do $test$
declare u uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); result jsonb; denied boolean; role_name text;
begin
insert into auth.users(id,email,raw_app_meta_data,created_at,updated_at) values(u,'qa-backup-test-'||u||'@example.invalid','{"system_role":"system_owner"}',now(),now());
insert into auth.sessions(id,user_id,aal,created_at,updated_at) values(s,u,'aal1',now(),now());
perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'session_id',s,'role','authenticated')::text,true);
result:=public.qa_admin_backup_snapshot();
if result->>'project_ref'<>'vpjxdsprfcpqclnhbeoh' or result->'auth_credentials_included'<>'false'::jsonb then raise exception 'scope invalid';end if;
if jsonb_array_length(result->'tables')<20 or jsonb_array_length(result->'functions')<40 then raise exception 'incomplete application metadata';end if;
if exists(select 1 from jsonb_array_elements(result->'tables') t where jsonb_array_length(t->'rows')<>(t->>'row_count')::integer)then raise exception 'row counts inconsistent';end if;
if exists(select 1 from jsonb_array_elements(result->'auth_metadata') t where t ? 'encrypted_password' or t ? 'recovery_token')then raise exception 'Auth secrets included';end if;
foreach role_name in array array['system_admin','employee','technical_support','disabled'] loop
update auth.users set raw_app_meta_data=jsonb_build_object('system_role',role_name) where id=u;
denied:=false;begin perform public.qa_admin_backup_snapshot();exception when insufficient_privilege then denied:=true;end;
if not denied then raise exception 'role export bypass: %',role_name;end if;
end loop;
if has_function_privilege('anon','public.qa_admin_backup_snapshot()','execute')then raise exception 'anonymous export grant';end if;
end $test$;
select jsonb_build_object('passed',9,'scope','QA export; no restore and no email delivery claimed') as result;
rollback;
