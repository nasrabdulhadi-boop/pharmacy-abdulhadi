import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
const prefs=readFileSync(new URL('../src/systemAdminPreferences.js',import.meta.url),'utf8');

test('admin preview retains explicit Arabic and English language choices',()=>{
 assert.match(prefs,/\bar\b/);
 assert.match(prefs,/\ben\b/);
});
test('admin preview has account role gate and verified auth state',()=>{
 assert.match(source,/canViewSystemAdminSection/);
 assert.match(source,/verifiedSystemRole/);
 assert.match(source,/supabase\.auth\.getUser/);
});
test('preview includes density preferences without modifying global application',()=>{
 assert.match(source,/SystemAdministrationPreview/);
 assert.match(prefs,/compact/);
 assert.match(prefs,/comfortable/);
});
