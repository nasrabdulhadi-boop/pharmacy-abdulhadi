import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
test('preview auth mutations are gated off by default',()=>{
 assert.match(source,/authMutationPreviewEnabled=allowStagingAuthMutation\(/);
 assert.match(source,/import \{allowStagingAuthMutation\} from '\.\/stagingAuthGuard\.js'/);
 assert.match(source,/if\(!authMutationPreviewEnabled\)/);
 assert.match(source,/disabled=\{!authMutationPreviewEnabled\|\|passwordBusy/);
 assert.match(source,/recovery&&!authMutationPreviewEnabled/);
});
test('password change verifies current user and minimum length',()=>{
 assert.match(source,/newPassword\.length<12/);
 assert.match(source,/newPassword!==confirmPassword/);
 assert.match(source,/supabase\.auth\.getUser\(\)/);
 assert.match(source,/user\.id!==sessionUser\.id/);
 assert.match(source,/supabase\.auth\.updateUser\(\{password:newPassword\}\)/);
});
test('recovery delegates to Supabase Auth rather than custom token handling',()=>{
 assert.match(source,/supabase\.auth\.resetPasswordForEmail\(email\.trim\(\),\{redirectTo\}\)/);
 assert.match(source,/const redirectTo=window\.location\.origin\+'\/#admin'/);
});
test('support capabilities are not treated as database authorization',()=>{
 const policy=readFileSync(new URL('../src/systemAccessPolicy.js',import.meta.url),'utf8');
 assert.match(policy,/NOT a database authorization mechanism/);
 assert.match(policy,/technical_support: \['system\.view_technical_health','system\.view_sanitized_diagnostics'\]/);
});
