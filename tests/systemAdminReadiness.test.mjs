import test from 'node:test';
import assert from 'node:assert/strict';
import {ADMIN_READINESS,readinessSummary} from '../src/systemAdminReadiness.js';
import {readFileSync} from 'node:fs';
test('readiness counts reconcile with the complete implementation register',()=>{
 const s=readinessSummary();assert.equal(s.total,ADMIN_READINESS.length);
 assert.equal(s.total,s.implemented+s.verificationRequired+s.notImplemented);
 assert.equal(new Set(ADMIN_READINESS.map(x=>x.id)).size,s.total);
});
test('backup, recovery and live diagnostics cannot be reported implemented prematurely',()=>{
 for(const id of ['backup_restore','account_recovery','live_diagnostics'])assert.equal(ADMIN_READINESS.find(x=>x.id===id)?.state,'not_implemented');
 assert.equal(ADMIN_READINESS.find(x=>x.id==='support_isolation')?.state,'verification_required');
});
test('status register is rendered only for authorized overview roles',()=>{
 const source=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
 assert.match(source,/!restrictedPreview&&<div className="systemAdminReadiness"/);
 assert.match(source,/readinessSummary\(\)\.implemented/);
});
