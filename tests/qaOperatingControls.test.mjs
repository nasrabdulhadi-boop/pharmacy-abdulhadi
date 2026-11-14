import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
test('QA controls version, block expired returns, isolate pauses and deny employees',async()=>{
 const db=new PGlite();
 try{
  await db.exec(`
   create role anon; create role authenticated;
   create schema auth; create schema pharmacy_qa_private;
   create function auth.uid() returns uuid language sql as $$ select '00000000-0000-4000-8000-000000000001'::uuid $$;
   create function public.qa_current_system_role() returns text language sql as $$ select current_setting('qa.role',true) $$;
   create table auth.users(id uuid primary key,email text);
   insert into auth.users values(auth.uid(),'qa@example.invalid');
   create table pharmacy_qa_private.audit_events(actor_id uuid,actor_email text,actor_role text,action text,entity_type text,entity_id text,details jsonb);
   create table pharmacy_qa_private.documents(id uuid default gen_random_uuid() primary key,kind text,source_id uuid,created_at timestamptz default now());
   create table pharmacy_qa_private.ledger(document_id uuid);
   create table pharmacy_qa_private.movements(id bigint,document_id uuid,batch_id uuid,quantity numeric,cost numeric);
   set qa.role='system_admin';
  `);
  await db.exec(await readFile(new URL('../audits/qa/admin_operating_controls.sql',import.meta.url),'utf8'));
  const {rows:[sale]}=await db.query("insert into pharmacy_qa_private.documents(kind,created_at) values('sale',now()-interval '60 days') returning id");
  await db.query("select public.qa_save_operating_controls(0,30,'block','purchase_draft',5,'Synthetic QA test')");
  await assert.rejects(db.query("insert into pharmacy_qa_private.documents(kind,source_id) values('return_request',$1)",[sale.id]),/qa_return_window_exceeded/);
  await assert.rejects(db.query("insert into pharmacy_qa_private.documents(kind) values('purchase_draft')"),/qa_operation_paused/);
  await db.query("insert into pharmacy_qa_private.documents(kind) values('sale')");
  await assert.rejects(db.query("select public.qa_save_operating_controls(0,30,'warn',null,null,'Stale settings')"),/stale_controls/);
  await db.query("select public.qa_save_operating_controls(1,30,'warn',null,-1,'Keep pause')");
  await assert.rejects(db.query("insert into pharmacy_qa_private.documents(kind) values('purchase_draft')"),/qa_operation_paused/);
  await db.query("insert into pharmacy_qa_private.documents(kind,source_id) values('return_request',$1)",[sale.id]);
  assert.equal((await db.query("select details->>'return_warning' as warning from pharmacy_qa_private.audit_events order by (details->>'version')::int desc limit 1")).rows[0].warning,'true');
  await db.exec("set qa.role='employee'");
  await assert.rejects(db.query("select public.qa_operating_controls()"),/not_authorized/);
 }finally{await db.close();}
});
