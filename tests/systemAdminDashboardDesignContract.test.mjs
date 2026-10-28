import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const ui=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
const css=readFileSync(new URL('../src/SYSTEM_ADMIN_WINDOW_POLISH.css',import.meta.url),'utf8');

test('overview has responsive modern dashboard regions',()=>{
 for(const part of ['systemAdminHero','systemAdminMetrics','systemAdminOverviewLower','systemAdminInfoPanel'])assert.ok(ui.includes(part),`missing ${part}`);
 assert.match(css,/@media\(max-width:900px\)/);
 assert.match(css,/@media\(max-width:600px\)/);
});
test('dashboard does not imply untested backup or diagnostics are healthy',()=>{
 assert.match(ui,/Restore not tested/);
 assert.match(ui,/No live probes/);
 assert.match(ui,/لم يُنفّذ/);
 assert.match(ui,/makeTechnicalHealthSnapshot\(\)/);
});
test('support-only role cannot navigate to sensitive administrative sections',()=>{
 assert.match(ui,/const restrictedPreview=isSupportPreview\|\|isUnverifiedPreview/);
 assert.match(ui,/\.filter\(\(\[id\]\)=>canViewSystemAdminSection\(verifiedRole,id\)\|\|id==='overview'\)/);
 assert.match(ui,/!restrictedPreview&&effectiveSection==='profile'/);
 assert.match(ui,/!restrictedPreview&&effectiveSection==='backup'/);
});
test('navigation supports assistive technology and reduced motion',()=>{
 assert.match(ui,/aria-current=\{effectiveSection===id\?'page':undefined\}/);
 assert.match(css,/prefers-reduced-motion:reduce/);
 assert.match(css,/focus-visible/);
});
