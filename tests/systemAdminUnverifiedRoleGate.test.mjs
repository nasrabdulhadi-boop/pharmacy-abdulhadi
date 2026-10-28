import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
test('unverified roles cannot access privileged admin preview sections',()=>{
 assert.match(source,/const isUnverifiedPreview=!verifiedRole/);
 assert.match(source,/const restrictedPreview=isSupportPreview\|\|isUnverifiedPreview/);
 assert.match(source,/\.filter\(\(\[id\]\)=>!restrictedPreview\|\|id==='overview'\)/);
 for(const section of ['profile','access','backup','preferences'])assert.ok(source.includes("{!restrictedPreview&&section==='"+section+"'"));
});
