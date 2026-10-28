import test from 'node:test';
import assert from 'node:assert/strict';
import {CAPABILITIES,ROLES,hasCapability,sanitizeTechnicalDiagnostic} from '../src/systemAccessPolicy.js';
test('support has exactly two non-sensitive UI capabilities',()=>{
 const allowed=CAPABILITIES.filter(x=>hasCapability('technical_support',x));
 assert.deepEqual(allowed,['system.view_technical_health','system.view_sanitized_diagnostics']);
 for(const cap of CAPABILITIES.filter(x=>!allowed.includes(x))) assert.equal(hasCapability('technical_support',cap),false,cap);
});
test('unknown roles and capabilities always fail closed',()=>{
 for(const role of [...ROLES,'support','admin','',null,undefined]){
  for(const cap of ['unknown','',null,undefined]) assert.equal(hasCapability(role,cap),false);
 }
 assert.equal(hasCapability('technical_support','__proto__'),false);
});
test('diagnostic sanitizer cannot leak unapproved fields',()=>{
 const data={status:'healthy',component:'database',observedAt:'2026-10-28T12:00:00Z',userId:'private',email:'private@example.com',token:'secret',sql:'select * from patients',error:'secret',finance:{balance:999}};
 assert.deepEqual(sanitizeTechnicalDiagnostic(data),{status:'healthy',component:'database',observedAt:'2026-10-28T12:00:00Z'});
 assert.deepEqual(sanitizeTechnicalDiagnostic({status:'broken',component:'patients',observedAt:'not-a-date'}),{status:'unknown',component:'unknown',observedAt:null});
});
