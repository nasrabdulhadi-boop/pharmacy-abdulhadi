import test from 'node:test';
import assert from 'node:assert/strict';
import {verifiedSystemRole,canViewSystemAdminSection} from './systemAdminRoleGate.js';
import {hasCapability,sanitizeTechnicalDiagnostic} from './systemAccessPolicy.js';

test('role gate fails closed for missing and forged metadata',()=>{
 assert.equal(verifiedSystemRole(null),null);
 assert.equal(verifiedSystemRole({user_metadata:{system_role:'system_owner'}}),null);
 assert.equal(verifiedSystemRole({app_metadata:{system_role:'employee',role:'admin'}}),'employee');
 assert.equal(canViewSystemAdminSection('employee','access'),false);
 assert.equal(canViewSystemAdminSection('technical_support','access'),false);
});
test('support cannot submit employee operations or approve them',()=>{
 for(const capability of ['employee.pos_sale','employee.purchase_draft_create','employee.return_request_create','system.manage_users','finance.read','finance.write'])assert.equal(hasCapability('technical_support',capability),false);
 assert.equal(hasCapability('technical_support','system.view_sanitized_diagnostics'),true);
});
test('employee has no administrative, financial or pricing authority',()=>{
 for(const capability of ['system.manage_users','system.manage_backups','finance.read','finance.write','employee.price_change','employee.invoice_delete','employee.finance_manage'])assert.equal(hasCapability('employee',capability),false);
});
test('diagnostics never return raw errors',()=>{
 const d=sanitizeTechnicalDiagnostic({component:'database',status:'healthy',observedAt:'2026-10-30T00:00:00.000Z',password:'hidden',sql:'select secret',user_id:'private'});
 assert.equal('password' in d,false);assert.equal('sql' in d,false);assert.equal('user_id' in d,false);
});
