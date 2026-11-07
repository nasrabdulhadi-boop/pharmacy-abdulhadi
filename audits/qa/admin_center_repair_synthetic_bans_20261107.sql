-- Applied once on QA. Keep obsolete synthetic accounts banned; do not unban them.
do $repair$
declare changed integer;
begin
 if not exists(select 1 from pg_namespace where nspname='pharmacy_qa_private') then raise exception 'QA only';end if;
 update auth.users set banned_until=now()+interval '100 years'
 where banned_until::text='infinity' and email like '%@example.invalid' and email ~ '^qa[-_+]';
 get diagnostics changed=row_count;
 if changed<>4 then raise exception 'unexpected synthetic fixture count: %',changed;end if;
 if exists(select 1 from auth.users where email like '%@example.invalid' and email ~ '^qa[-_+]' and banned_until::text='infinity')then raise exception 'infinity remains';end if;
end $repair$;
