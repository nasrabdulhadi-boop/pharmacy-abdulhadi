-- QA ONLY. Synthetic identities, session rows and role changes roll back.
begin;
create temp table role_acceptance_results(name text,passed boolean) on commit drop;
do $test$
declare owner_id uuid:=gen_random_uuid(); owner_session uuid:=gen_random_uuid(); target_id uuid:=gen_random_uuid(); target_session uuid:=gen_random_uuid(); denied boolean; label text;
begin
insert into auth.users(id,email,raw_app_meta_data,created_at,updated_at) values(owner_id,'qa-owner-'||owner_id||'@example.invalid','{"system_role":"system_owner"}',now(),now()),(target_id,'qa-target-'||target_id||'@example.invalid','{"system_role":"employee","provider":"email"}',now(),now());
insert into auth.sessions(id,user_id,aal,created_at,updated_at) values(owner_session,owner_id,'aal1',now(),now()),(target_session,target_id,'aal1',now(),now());
perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'session_id',owner_session,'role','authenticated')::text,true);
foreach label in array array['system_owner','invalid',''] loop
denied:=false;begin perform public.qa_admin_set_role(target_id,label);exception when insufficient_privilege then denied:=true;end;
if not denied then raise exception 'invalid role accepted';end if;
insert into role_acceptance_results values('reject target role: '||label,true);
end loop;
denied:=false;begin perform public.qa_admin_set_role(owner_id,'employee');exception when insufficient_privilege then denied:=true;end;
if not denied then raise exception 'owner self demotion';end if;insert into role_acceptance_results values('owner self protection',true);
perform public.qa_admin_set_role(target_id,'technical_support');
if exists(select 1 from auth.sessions where user_id=target_id) then raise exception 'live sessions remain';end if;
insert into role_acceptance_results values('sessions revoked',true);
if not exists(select 1 from auth.users where id=target_id and raw_app_meta_data->>'provider'='email' and raw_app_meta_data->>'system_role'='technical_support') then raise exception 'metadata not preserved';end if;
insert into role_acceptance_results values('provider preserved and role changed',true);
if not exists(select 1 from pharmacy_qa_private.audit_events where entity_id=target_id::text and actor_id=owner_id and action='system_role_changed') then raise exception 'audit missing';end if;
insert into role_acceptance_results values('mandatory actor audit',true);
if public.qa_admin_set_role(target_id,'technical_support') is distinct from false then raise exception 'unchanged role incorrectly reports mutation';end if;
insert into role_acceptance_results values('unchanged role returns false',true);
update auth.users set raw_app_meta_data='{"system_role":"system_admin"}' where id=owner_id;
denied:=false;begin perform public.qa_admin_set_role(target_id,'system_admin');exception when insufficient_privilege then denied:=true;end;
if not denied then raise exception 'manager can elevate';end if;
insert into role_acceptance_results values('manager cannot create another manager',true);
foreach label in array array['employee','technical_support'] loop
update auth.users set raw_app_meta_data=jsonb_build_object('system_role',label) where id=owner_id;
denied:=false;begin perform public.qa_admin_accounts();exception when insufficient_privilege then denied:=true;end;
if not denied then raise exception 'restricted actor sees accounts';end if;
insert into role_acceptance_results values(label||' cannot list accounts',true);
denied:=false;begin perform public.qa_admin_set_role(target_id,'employee');exception when insufficient_privilege then denied:=true;end;
if not denied then raise exception 'restricted actor changes roles';end if;
insert into role_acceptance_results values(label||' cannot change roles',true);
end loop;
end $test$;
select count(*) passed,jsonb_agg(to_jsonb(r)) results from role_acceptance_results r;
rollback;