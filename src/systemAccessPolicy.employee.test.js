import test from 'node:test';
import assert from 'node:assert/strict';
import {hasCapability,sanitizeTechnicalDiagnostic} from './systemAccessPolicy.js';
import {verifiedSystemRole,canViewSystemAdminSection} from './systemAdminRoleGate.js';

test('employee can perform only approved operational capabilities',()=>{
 const allowed=['employee.pos_sale','employee.catalog_read','employee.inventory_read','employee.inventory_count_submit','employee.purchase_draft_create','employee.order_process','employee.return_request_create','employee.supplier_operational_read'];
 for(const cap of allowed)assert.equal(hasCapability('employee',cap),true,cap);
 for(const cap of ['employee.price_change','employee.invoice_delete','employee.finance_manage','employee.user_manage','finance.read','finance.write','system.manage_users','pharmacy.write_operations'])assert.equal(hasCapability('employee',cap),false,cap);
 assert.equal(canViewSystemAdminSection('employee','overview'),false);
});
test('technical support has no operational or financial capabilities',()=>{
 for(const cap of ['employee.pos_sale','employee.inventory_read','finance.read','pharmacy.read_sensitive','system.manage_users','system.manage_backups'])assert.equal(hasCapability('technical_support',cap),false,cap);
 assert.equal(hasCapability('technical_support','system.view_sanitized_diagnostics'),true);
});
test('untrusted metadata does not elevate role',()=>{
 assert.equal(verifiedSystemRole({user_metadata:{system_role:'system_owner'}}),null);
 assert.equal(verifiedSystemRole({app_metadata:{system_role:'employee',role:'admin'}}),'employee');
 assert.equal(verifiedSystemRole({app_metadata:{system_role:'technical_support',role:'admin'}}),'technical_support');
});
test('technical diagnostics strip secrets and raw messages',()=>{
 const result=sanitizeTechnicalDiagnostic({component:'api',status:'degraded',observedAt:'2026-10-30T13:00:00.000Z',secret:'secret',error:'raw sql',email:'private@example.com'});
 assert.deepEqual(Object.keys(result).sort(),['component','observedAt','status']);
});
