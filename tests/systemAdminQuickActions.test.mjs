import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {canViewSystemAdminSection} from '../src/systemAdminRoleGate.js';
const ui=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
const css=readFileSync(new URL('../src/SYSTEM_ADMIN_REBUILD_V3.css',import.meta.url),'utf8');
test('owner dashboard offers working quick links to four existing sections',()=>{
 assert.match(ui,/className="systemAdminQuickActions"/);
 for(const id of ['profile','access','backup','preferences'])assert.ok(ui.includes(`id:'${id}'`));
 assert.match(ui,/onClick=\{\(\)=>setSection\(action\.id\)\}/);
});
test('quick actions honor role guard and are not rendered to support',()=>{
 assert.match(ui,/!restrictedPreview&&<div className="systemAdminQuickActions"/);
 assert.match(ui,/filter\(action=>canViewSystemAdminSection\(verifiedRole,action.id\)\)/);
 for(const id of ['profile','access','backup','preferences'])assert.equal(canViewSystemAdminSection('technical_support',id),false);
});
test('quick actions have responsive layout and keyboard focus',()=>{
 assert.match(css,/\.systemAdminQuickActionsGrid/);
 assert.match(css,/\.systemAdminQuickAction:focus-visible/);
 assert.match(css,/@media\(max-width:650px\)/);
});
