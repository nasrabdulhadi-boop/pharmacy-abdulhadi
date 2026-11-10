import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {catalogFindings,catalogSample,previewCatalogImport,readCatalogCsv} from '../src/adminCatalogTools.js';
import {makeSetupPackage,readSetupPackage} from '../src/adminPrintSettings.js';

test('CSV preview protects currencies, flags duplicates and preserves quoted values',()=>{
 const data=readCatalogCsv(catalogSample);
 assert.equal(data.length,2);
 assert.equal(readCatalogCsv('barcode;name;price;currency\r\nQA-IMPORT-01;"اسم; اختبار";9.10;SYP')[0].name,'اسم; اختبار');
 const previous={id:'1',barcode:data[0].barcode,sale_currency:'SYP',sale_price:12000};
 const [update]=previewCatalogImport(data,[previous]);
 assert.equal(update.mode,'update');
 assert.equal(update.price,'12500');
 assert.deepEqual(update.errors,[]);
 assert.ok(previewCatalogImport([data[0],data[0]],[previous]).every(row=>row.errors.length));
 assert.ok(previewCatalogImport([{...data[0],currency:'USD'}],[previous])[0].errors.length);
 assert.throws(()=>readCatalogCsv('barcode,name,price,currency\nfoo,"oops,1,USD'));
});

test('setup package transfers templates and appearance without machine or account data',()=>{
 const packet=makeSetupPackage({device:{name:'station',printer:'local'},templates:{receipt:{title:'QA'}}},{language:'fr',density:'compact'});
 assert.equal(packet.device,undefined);
 assert.equal(readSetupPackage(JSON.stringify(packet)).templates.receipt.title,'QA');
 assert.throws(()=>readSetupPackage(JSON.stringify({...packet,appearance:{language:'unknown',density:'compact'}})));
});

test('catalog review identifies normalized names, barcode conflicts and missing fields',()=>{
 const rows=[{id:'1',name:' TEST  MED',barcode:'ABC'},{id:'2',name:'test med',barcode:'abc'}];
 const result=catalogFindings(rows);
 assert.ok(result.some(issue=>issue.kind==='similar'&&issue.items.length===2));
 assert.ok(result.some(issue=>issue.kind==='barcode'&&issue.items.length===2));
 assert.ok(result.some(issue=>issue.kind==='missing'&&issue.missing.includes('strength')));
 assert.equal(rows[0].name,' TEST  MED');
});

test('import saves an audited batch, rejects stale preview atomically and denies employees',async()=>{
 const db=new PGlite();
 try {
  await db.exec(`
   create role anon; create role authenticated;
   create schema auth; create schema pharmacy_qa_private;
   create function auth.uid() returns uuid language sql as $$ select 'fbefbf60-c041-4000-8a17-5d94ec9ad383'::uuid $$;
   create table auth.users(id uuid primary key,email text); insert into auth.users values(auth.uid(),'qa@example.invalid');
   create function public.qa_current_system_role() returns text language sql as $$ select current_setting('qa.role',true) $$;
   create table pharmacy_qa_private.catalog(id uuid primary key,code text unique,title text,price numeric,currency text,parts integer);
   create table pharmacy_qa_private.audit_events(id uuid primary key,actor_id uuid,actor_email text,actor_role text,action text,entity_type text,entity_id text,details jsonb);
   create table public.products(id uuid primary key,name text,barcode text unique,active_ingredient text,strength text,dosage_form text,manufacturer text,category text,unit text,reorder_level numeric,purchase_price numeric,sale_price numeric,parts_per_unit numeric,customer_visible boolean,sale_currency text,active boolean);
  `);
  const existing=await readFile(new URL('../audits/qa/employee_daily_operations.sql',import.meta.url),'utf8');
  const start=existing.indexOf('create or replace function public.qa_save_workspace_product');
  await db.exec(existing.slice(start,existing.indexOf('do $do$',start)));
  await db.exec(await readFile(new URL('../audits/qa/admin_catalog_import.sql',import.meta.url),'utf8'));
  await db.exec("set qa.role='system_admin'");
  const create={mode:'create',barcode:'QA-IMPORT-A',name:'Synthetic A',price:'10.50',currency:'USD'};
  const apply=rows=>db.query('select public.qa_apply_catalog_import($1::uuid,$2::jsonb) as count',[crypto.randomUUID(),JSON.stringify(rows)]);
  const batchId=crypto.randomUUID();
  const replay=()=>db.query('select public.qa_apply_catalog_import($1::uuid,$2::jsonb) as count',[batchId,JSON.stringify([create])]);
  assert.equal((await replay()).rows[0].count,1);
  assert.equal((await replay()).rows[0].count,1);
  const {rows:[original]}=await db.query('select id from public.products');
  const update={...create,mode:'update',id:original.id,previousPrice:'10.50',price:'11.75'};
  assert.equal((await apply([update])).rows[0].count,1);
  await assert.rejects(apply([{...create,barcode:'QA-IMPORT-0'},update]),error=>error.code==='40001');
  const {rows}=await db.query('select barcode,sale_price::text from public.products');
  assert.deepEqual(rows,[{barcode:'QA-IMPORT-A',sale_price:'11.75'}]);
  assert.equal((await db.query('select count(*)::int n from pharmacy_qa_private.audit_events')).rows[0].n,2);
  await db.exec("set qa.role='employee'");
  await assert.rejects(apply([{...create,barcode:'QA-IMPORT-B'}]),error=>error.code==='42501');
 } finally {await db.close();}
});
