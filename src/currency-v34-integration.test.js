import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const ui=readFileSync(new URL('./main.jsx',import.meta.url),'utf8');
const file=name=>readFileSync(new URL('../CURRENCY_COMPLETION_V6_4_34/'+name,import.meta.url),'utf8');
test('purchase currency selection routes independently to USD and SYP RPCs',()=>{
 assert.match(ui,/invoiceCurrency==='USD'\?'admin_create_purchase_usd_v1':'admin_create_purchase_syp_v1'/);
 assert.match(ui,/عملة فاتورة المورد/);
 assert.match(ui,/sale_currency:.*sale_currency/);
});
test('supplier return uses native currency credit note and customer return stays compatible',()=>{
 const a=ui.slice(ui.indexOf('function CurrencyReturns('),ui.indexOf('function AuditDetailsModal('));
 assert.match(a,/admin_currency_supplier_return_v2/);
 assert.match(a,/admin_currency_return_list_v1/);
 assert.match(a,/admin_customer_return/);
});
test('supplier refund UI and ledger exist',()=>{
 assert.match(ui,/admin_currency_supplier_refund_receipt_v1/);
 assert.match(ui,/credit_notes/);
 assert.match(ui,/selected\.refunds/);
});
test('manual cashbox old reconcile is inactive and day reports SYP normalized',()=>{
 assert.match(file('20_DASHBOARD_CASHBOX_COMPATIBILITY.sql'),/automatic_reconciliation_disabled/);
 assert.match(file('20_DASHBOARD_CASHBOX_COMPATIBILITY.sql'),/COALESCE\(sp\.amount_syp,sp\.amount\)/);
 assert.doesNotMatch(ui,/supabase\.rpc\('admin_cashbox_reconcile'/);
});
test('supplier allocations and refund write operations are currency guarded',()=>{
 assert.match(file('02_GUARD_SUPPLIER_ALLOCATIONS_STAGING_ONLY.sql'),/v_payment_currency IS DISTINCT FROM v_invoice_currency/);
 assert.match(file('16_SUPPLIER_REFUNDS_RECEIPTS.sql'),/v_available/);
 assert.match(file('15_SUPPLIER_RETURNS_CREDIT_NOTES.sql'),/credit_amount=credit_amount\+NEW\.amount/);
});