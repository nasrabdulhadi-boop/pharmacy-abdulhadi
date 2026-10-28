import test from 'node:test';
import assert from 'node:assert/strict';
import {ROLES,CAPABILITIES,hasCapability,sanitizeTechnicalDiagnostic} from '../src/systemAccessPolicy.js';

test('support is strictly diagnostic and never gets sensitive or write capabilities',()=>{
 for(const capability of CAPABILITIES){
  assert.equal(hasCapability('technical_support',capability),
   ['system.view_technical_health','system.view_sanitized_diagnostics'].includes(capability),capability);
 }
});
test('unknown roles and unknown capabilities are denied',()=>{
 for(const role of ['admin','support','authenticated','',null,undefined,'__proto__']){
  for(const capability of CAPABILITIES)assert.equal(hasCapability(role,capability),false);
 }
 for(const role of ROLES)assert.equal(hasCapability(role,'finance.export_all'),false);
});
test('admin cannot control owner-only security and backup functions',()=>{
 assert.equal(hasCapability('system_admin','system.manage_security'),false);
 assert.equal(hasCapability('system_admin','system.manage_backups'),false);
});
test('sanitization removes secrets, user data, and raw SQL errors',()=>{
 const result=sanitizeTechnicalDiagnostic({
  status:'healthy',component:'database',observedAt:'2026-10-28T12:00:00Z',
  password:'secret',user_id:'private',sql:'select * from patients',financial_total:500,
  error:'Sensitive row details',url:'https://private.invalid'
 });
 assert.deepEqual(result,{status:'healthy',component:'database',observedAt:'2026-10-28T12:00:00Z'});
 assert.equal(sanitizeTechnicalDiagnostic({status:'oops',component:'customers',observedAt:'bad'}).status,'unknown');
});
