import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const code=readFileSync(new URL('./main.jsx',import.meta.url),'utf8');

test('currency engine requires explicit Vercel opt in',()=>{
 assert.match(code,/VITE_ENABLE_USD_ENGINE\s*===\s*'true'/);
 assert.match(code,/if\(!CURRENCY_ENGINE_OPT_IN\)return Promise\.resolve\(false\)/);
});
test('all core finance sections preserve tested SYP legacy implementation',()=>{
 for(const name of ['Reports','Purchases','SupplierDebts','Suppliers','Returns']){
  assert.match(code,new RegExp('function Legacy'+name+'\\('));
  assert.match(code,new RegExp('function Currency'+name+'\\('));
  assert.match(code,new RegExp('function '+name+'\\(props\\)\\{return <CurrencyPageSwitch'));
 }
});
test('missing backend is fail-closed to existing safe screen',()=>{
 assert.match(code,/if\(res\.error\)\{console\.warn\('Currency backend unavailable/);
 assert.match(code,/return status\?<CurrencyView/);
 assert.match(code,/legacy:LegacyView/);
});
test('currency-aware SYP purchase and USD paths remain independent',()=>{
 assert.match(code,/invoiceCurrency==='USD'\?'admin_create_purchase_usd_v1':'admin_create_purchase_syp_v1'/);
 assert.match(code,/invoiceCurrency==='SYP'&&valid\.some/);
 assert.match(code,/admin_currency_supplier_return_v2/);
 assert.match(code,/admin_currency_supplier_refund_receipt_v1/);
});
test('purchase amount discount is labelled and computed in invoice currency',()=>{
 assert.match(code,/invoiceCurrency==='USD'\?'\$':'ل\.س'/);
 assert.match(code,/p_discount_value:rawDiscountValue/);
});
test('opening cashbox does not reconcile mutable records',()=>{
 const body=code.slice(code.indexOf('function Cashbox('),code.indexOf('function Legacy')>0?code.indexOf('function Debtors('):undefined);
 assert.doesNotMatch(body,/supabase\.rpc\('admin_cashbox_reconcile'/);
});
test('user browser build has no service-role key or SQL migration execution',()=>{
 assert.doesNotMatch(code,/service_role/i);
 assert.doesNotMatch(code,/\bDROP\s+TABLE\b|\bTRUNCATE\b/i);
});