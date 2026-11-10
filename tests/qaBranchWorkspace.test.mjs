import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';
import { branchLink, branchIdFromSearch, orderBranches, branchOperatorSections } from '../src/qaBranchWorkspace.js';

const id = index => `00000000-0000-0000-0000-${String(index).padStart(12,'0')}`;

test('branch links resolve by UUID and comparison preserves large signed totals', () => {
  assert.equal(branchIdFromSearch(new URL(branchLink('https://qa.example.test/#admin',id(1))).search),id(1));
  assert.equal(branchIdFromSearch('?branch=admin'),null);
  const rows = [{name:'A',profit:'9007199254740993'},{name:'B',profit:'9007199254740992'},{name:'C',profit:'-30'}];
  assert.deepEqual(orderBranches(rows,'profit',true).map(row=>row.name),['A','B','C']);
  assert.deepEqual(orderBranches(rows,'profit',false).map(row=>row.name),['C','B','A']);
});

test('branch workspace starts at point of sale and keeps manager areas locked', () => {
  assert.equal(branchOperatorSections[0].id,'pos');
  assert.ok(!branchOperatorSections.some(section=>section.id==='dashboard'));
  for (const id of ['customers','offers','profit','reports','system']) {
    assert.equal(branchOperatorSections.find(section=>section.id===id)?.locked,true);
  }
  for (const id of ['pos','returns','purchases','suppliers','inventory','cashbox']) {
    assert.ok(branchOperatorSections.some(section=>section.id===id && !section.locked));
  }
});

test('database persists branches, scopes membership and independently totals financial movements', async () => {
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated;
      create schema auth;
      grant usage on schema auth to authenticated;
      create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,banned_until timestamptz,system_role text);
      create table auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
      create function auth.uid() returns uuid language sql stable as
      'select nullif(current_setting(''test.user_id'',true),'''')::uuid';
      create function auth.jwt() returns jsonb language sql stable as
      'select jsonb_build_object(''session_id'',current_setting(''test.session_id'',true))';
      create function public.qa_current_system_role() returns text language sql stable security definer as
      'select u.system_role from auth.users u join auth.sessions s on s.user_id=u.id where u.id=auth.uid() and s.id::text=auth.jwt()->>''session_id''';
      insert into auth.users values
      ('${id(1)}','owner@example.test',now(),null,'system_admin'),
      ('${id(2)}','one@example.test',now(),null,null),
      ('${id(3)}','two@example.test',now(),null,null),
      ('${id(4)}','other@example.test',now(),null,'system_admin'),
      ('${id(5)}','unverified@example.test',null,null,null);
      insert into auth.sessions select id,id,null from auth.users;
    `);
    await db.exec(await readFile(new URL('../audits/qa/branch_workspace_20261110.sql',import.meta.url),'utf8'));
    const session = async n => {
      await db.exec('reset role');
      await db.query("select set_config('test.user_id',$1,false),set_config('test.session_id',$1,false)",[id(n)]);
      await db.exec('set role authenticated');
    };
    const claim = async branch => (await db.query('select public.qa_claim_branch($1) as accepted',[branch])).rows[0].accepted;
    const report = async branch => (await db.query("select public.qa_branch_day((now() at time zone 'Asia/Damascus')::date,$1) as report",[branch])).rows[0].report;
    const create = async (name,email) => (await db.query("insert into public.qa_branches(name,location,invite_email) values($1,'QA',$2) returning id",[name,email])).rows[0].id;
    const record = (branch,kind,ref,amount,cash,cost,quantity=null,reorder=null) => db.query(
      'insert into public.qa_branch_events(branch_id,kind,reference,amount,cash,cost,quantity,reorder_level) values ($1,$2,$3,$4,$5,$6,$7,$8)',
      [branch,kind,ref,amount,cash,cost,quantity,reorder]);

    await session(1);
    const first = await create('فرع أول','one@example.test');
    const second = await create('فرع ثاني','two@example.test');
    const pending = await create('فرع ثالث','unverified@example.test');
    await assert.rejects(create('فرع مكرر','owner@example.test'),/row-level security/);
    await session(5);
    assert.equal(await claim(pending),false);
    await session(3);
    assert.equal(await claim(first),false);
    assert.equal(await claim(second),true);
    await record(second,'sale','S2',900,900,500);
    await session(2);
    assert.equal(await claim(first),true);
    assert.equal(await claim(first),true);
    await assert.rejects(create('غير مخوّل','two@example.test'),/row-level security/);
    await assert.rejects(record(second,'withdrawal','W2',12,12,0),/row-level security/);
    await record(first,'deposit','D1',300,300,0);
    await record(first,'sale','S1',1000,700,600);
    await record(first,'return','R1',100,100,60);
    await record(first,'purchase','P1',500,350,0);
    await record(first,'expense','E1',50,50,0);
    await record(first,'withdrawal','W1',200,200,0);
    await record(first,'inventory','SKU-1',0,0,0,2,5);
    await assert.rejects(record(first,'withdrawal','W3',200,100,0),/check constraint/);
    assert.deepEqual((await report(null)).branches.map(row=>row.id),[first]);
    assert.deepEqual((await report(second)).branches,[]);
    await assert.rejects(db.query('update public.qa_branch_events set cash=0 where branch_id=$1',[first]),/permission denied/);
    await session(4);
    assert.deepEqual((await report(null)).branches,[]);
    await session(1);
    const {branches,movements,inventory} = await report(first);
    assert.equal(movements.length,7);
    assert.equal(movements.find(row=>row.kind==='sale').actor_id,id(2));
    assert.equal(inventory[0].quantity,2);
    const [row] = branches;
    assert.deepEqual([row.sales,row.returns,row.profit,row.cash_in,row.cash_paid,row.cash_withdrawn,row.cash_balance,row.shortages],
      ['1000','100','310','1000','500','200','300',1]);
    assert.equal((await report(null)).branches.length,3);
    await db.exec('reset role');
    await db.exec(await readFile(new URL('../audits/qa/branch_operator_workspace.sql',import.meta.url),'utf8'));
    const operator = async (branch,kinds) => (await db.query(
      "select public.qa_branch_operator_day($1,(now() at time zone 'Asia/Damascus')::date,$2) as data",[branch,kinds])).rows[0].data;
    const addSupplier = branch => db.query("insert into public.qa_branch_suppliers(branch_id,name) values ($1,'QA Supplier')",[branch]);
    await session(2);
    const own = await operator(first,['sale']);
    assert.equal(own.branch.name,'فرع أول');
    assert.equal(own.movements.length,1);
    assert.equal(own.movements[0].amount,1000);
    assert.ok(!('cost' in own.movements[0]));
    assert.ok(!('profit' in own.branch));
    assert.equal((await operator(second,['sale'])).branch,null);
    assert.equal((await db.query('select cost from public.qa_branch_events')).rows.length,0);
    assert.equal((await report(first)).branches[0].profit,'0');
    assert.equal((await db.query('select public.qa_branch_event_saved($1,$2) as saved',[first,own.movements[0].id])).rows[0].saved,true);
    await record(first,'deposit','D2',25,25,0);
    assert.equal((await operator(first,['deposit'])).movements.length,2);
    await assert.rejects(record(second,'deposit','D3',25,25,0),/row-level security/);
    await addSupplier(first);
    await assert.rejects(addSupplier(second),/row-level security/);
    await session(3);
    await addSupplier(second);
    assert.deepEqual((await db.query('select branch_id from public.qa_branch_suppliers')).rows.map(row=>row.branch_id),[second]);
    await session(1);
    assert.equal((await db.query('select branch_id from public.qa_branch_suppliers')).rows.length,2);
    assert.equal((await report(first)).branches[0].profit,'310');
    await db.exec('reset role; set role anon');
    await assert.rejects(db.query('select public.qa_claim_branch($1)',[first]),/permission denied/);
  } finally {
    await db.close();
  }
});
