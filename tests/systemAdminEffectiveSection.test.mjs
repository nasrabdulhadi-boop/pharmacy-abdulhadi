import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {canViewSystemAdminSection} from '../src/systemAdminRoleGate.js';
const source=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
test('support and unauthenticated roles cannot access privileged sections',()=>{
 for(const role of ['technical_support',null])for(const section of ['profile','access','backup','preferences'])assert.equal(canViewSystemAdminSection(role,section),false);
});
test('active admin section is recomputed on every render after role changes',()=>{
 assert.match(source,/const effectiveSection=canViewSystemAdminSection\(verifiedRole,section\)\?section:'overview'/);
 for(const section of ['profile','access','backup','preferences'])assert.ok(source.includes(`!restrictedPreview&&effectiveSection==='${section}'`));
 assert.match(source,/effectiveSection==='overview'&&<section/);
});
