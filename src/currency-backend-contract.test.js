import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const main=readFileSync(new URL('./main.jsx', import.meta.url),'utf8');
const base=new URL('../CURRENCY_COMPLETION_V6_4_29/',import.meta.url);
const read=p=>readFileSync(new URL(p,base),'utf8');
test('currency feature requires both explicit flag and backend readiness contract',()=>{
 assert.match(main,/VITE_ENABLE_USD_ENGINE === 'true'/);
 assert.match(main,/supabase\.rpc\('admin_currency_backend_contract_v1'\)/);
 assert.match(main,/contract\.data\?\.ready!==true/);
 assert.match(main,/return status\?<CurrencyView/);
});
test('contract checks both USD write RPCs and allocation and supplier return guard',()=>{
 const sql=read('14_BACKEND_READINESS_CONTRACT_REVIEW_ONLY.sql');
 for(const name of ['admin_create_purchase_usd_v1','admin_record_supplier_payment_usd_v1',
  'admin_currency_supplier_debt_list_v1','trg_ab_allocation_metadata_guard_v1',
  'trg_guard_usd_supplier_return_currency_v1'])assert.ok(sql.includes(name),name);
 assert.match(sql,/GRANT EXECUTE ON FUNCTION public\.admin_currency_backend_contract_v1/);
});
test('allocation guard validates currency, exchange snapshot and USD converted amount',()=>{
 const sql=read('02_GUARD_SUPPLIER_ALLOCATIONS_STAGING_ONLY.sql');
 assert.match(sql,/NEW\.currency IS DISTINCT FROM v_invoice_currency/);
 assert.match(sql,/NEW\.fx_rate IS DISTINCT FROM v_payment_fx/);
 assert.match(sql,/NEW\.amount_syp IS DISTINCT FROM ROUND\(NEW\.amount\*v_payment_fx,2\)/);
 assert.match(sql,/BEFORE UPDATE OF currency, fx_rate, amount_syp/);
});
test('purchase and supplier payment lock USD rate through completion of transaction',()=>{
 for(const path of ['03_USD_SUPPLIER_PAYMENTS_STAGING_ONLY.sql','04_USD_PURCHASES_STAGING_ONLY.sql']){
  assert.match(read(path),/FROM public\.pharmacy_currency_settings WHERE id=1 FOR SHARE;/);
 }
});
test('neither frontend nor migration auto-switches currency flag or runs SQL',()=>{
 assert.doesNotMatch(main,/import\.meta\.env\.VITE_ENABLE_USD_ENGINE\s*=\s*true/);
 assert.doesNotMatch(main,/supabase\.rpc\('admin_create_purchase_usd_v1'/);
});

test('supplier return options keep separate paid and bonus batches',()=>{
 const sql=read('12_SUPPLIER_RETURN_OPTIONS_READ_STAGING_ONLY.sql');
 assert.match(sql,/JOIN public\.batches b ON b\.purchase_item_id=pi\.id/);
 assert.match(sql,/CASE WHEN b\.id=pi\.batch_id THEN pi\.quantity ELSE pi\.bonus_quantity END/);
});
test('backend readiness fails on inconsistent legacy ledger balances',()=>{
 const sql=read('14_BACKEND_READINESS_CONTRACT_REVIEW_ONLY.sql');
 assert.match(sql,/v_balances/);
 assert.match(sql,/sp\.currency IS DISTINCT FROM p\.currency/);
 assert.match(sql,/usd_supplier_returns_supported',false/);
});
