-- All identities, reservations and audit rows roll back.
begin;
do $test$
declare owner_id uuid:=gen_random_uuid(); manager_id uuid:=gen_random_uuid(); staff_id uuid:=gen_random_uuid(); session_id uuid:=gen_random_uuid(); invitation_id uuid:=gen_random_uuid(); target_id uuid:=gen_random_uuid(); denied boolean; namespace text:='qa-invite-sql-'||gen_random_uuid();
begin
 insert into auth.users(id,email,raw_app_meta_data,created_at,updated_at) values
 (owner_id,namespace||'-owner@example.invalid','{"system_role":"system_owner"}',now(),now()),
 (manager_id,namespace||'-manager@example.invalid','{"system_role":"system_admin"}',now(),now()),
 (staff_id,namespace||'-support@example.invalid','{"system_role":"technical_support"}',now(),now());
 insert into auth.sessions(id,user_id,aal,created_at,updated_at) values(session_id,owner_id,'aal1',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'session_id',session_id,'role','authenticated')::text,true);
 if public.qa_admin_reserve_invitation(invitation_id,namespace||'-new@example.invalid','employee') is distinct from true then raise exception 'reserve failed';end if;
 denied:=false;begin perform public.qa_admin_reserve_invitation(invitation_id,namespace||'-new@example.invalid','employee');exception when unique_violation then denied:=true;end;if not denied then raise exception 'duplicate accepted';end if;
 denied:=false;begin perform public.qa_admin_reserve_invitation(gen_random_uuid(),namespace||'-owner@example.invalid','employee');exception when unique_violation then denied:=true;end;if not denied then raise exception 'existing account accepted';end if;
 denied:=false;begin perform public.qa_service_finalize_invitation(invitation_id,owner_id);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'existing owner modified';end if;
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,invited_at) values(target_id,namespace||'-new@example.invalid','{}',jsonb_build_object('qa_invitation_id',invitation_id),now(),now(),now());
 if public.qa_service_finalize_invitation(invitation_id,target_id) is distinct from true then raise exception 'finalize failed';end if;
 if not exists(select 1 from auth.users where id=target_id and raw_app_meta_data->>'system_role'='employee') then raise exception 'role missing';end if;
 if not exists(select 1 from pharmacy_qa_private.audit_events where action='system_invitation_prepared' and entity_id=target_id::text and details->>'email_sent'='false') then raise exception 'audit missing';end if;
 denied:=false;begin perform public.qa_service_finalize_invitation(invitation_id,target_id);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'finalize replay accepted';end if;
 if has_function_privilege('authenticated','public.qa_service_finalize_invitation(uuid,uuid)','execute') or has_function_privilege('anon','public.qa_admin_reserve_invitation(uuid,text,text)','execute') or has_table_privilege('authenticated','pharmacy_qa_private.account_invitations','select')then raise exception 'unexpected grant';end if;
 update auth.sessions set user_id=manager_id where id=session_id;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',manager_id,'session_id',session_id,'role','authenticated')::text,true);
 denied:=false;begin perform public.qa_admin_reserve_invitation(gen_random_uuid(),namespace||'-escalate@example.invalid','system_admin');exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'manager elevated';end if;
 invitation_id:=gen_random_uuid();perform public.qa_admin_reserve_invitation(invitation_id,namespace||'-manager-new@example.invalid','technical_support');
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,invited_at) values(gen_random_uuid(),namespace||'-manager-new@example.invalid','{}',jsonb_build_object('qa_invitation_id',invitation_id),now(),now(),now()) returning id into target_id;
 delete from auth.sessions where id=session_id;
 denied:=false;begin perform public.qa_service_finalize_invitation(invitation_id,target_id);exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'revoked actor accepted';end if;
 insert into auth.sessions(id,user_id,aal,created_at,updated_at)values(session_id,staff_id,'aal1',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',staff_id,'session_id',session_id,'role','authenticated')::text,true);
 denied:=false;begin perform public.qa_admin_reserve_invitation(gen_random_uuid(),namespace||'-support-new@example.invalid','employee');exception when insufficient_privilege then denied:=true;end;if not denied then raise exception 'support invitation allowed';end if;
end $test$;
select jsonb_build_object('passed',12,'scope','QA invitation hierarchy, existing accounts, replay, audit, grants and revoked session') as result;
rollback;
