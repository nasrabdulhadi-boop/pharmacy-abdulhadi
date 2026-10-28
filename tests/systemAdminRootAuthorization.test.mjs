import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const ui=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
test('admin root checks app metadata role, not email identity',()=>{
 assert.match(ui,/const admin=s\?\.user\?\.app_metadata\?\.role==='admin'\|\|\['system_owner','system_admin'\]\.includes\(s\?\.user\?\.app_metadata\?\.system_role\)/);
 assert.doesNotMatch(ui,/const admin=s\?\.user\?\.email/);
});
test('admin refresh no longer relies on fixed email',()=>{
 assert.doesNotMatch(ui,/ss\.user\?\.email===/);
 assert.match(ui,/ss\.user\?\.app_metadata\?\.system_role/);
});
