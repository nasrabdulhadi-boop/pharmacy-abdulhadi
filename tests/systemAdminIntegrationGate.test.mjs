import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
test('admin UI uses the isolated staging auth guard',()=>{
 assert.match(source,/import \{allowStagingAuthMutation\} from '\.\/stagingAuthGuard\.js'/);
 assert.match(source,/authMutationPreviewEnabled=allowStagingAuthMutation\(/);
 assert.doesNotMatch(source,/!url\.includes\('eewjjzgwoaxhojnjvzgq'\)/);
});
test('administration preferences and diagnostics are connected to the UI',()=>{
 assert.match(source,/readAdminPreferences\(/);
 assert.match(source,/writeAdminPreferences\(/);
 assert.match(source,/summarizeTechnicalHealth\(makeTechnicalHealthSnapshot\(\)\)/);
});
test('backup center is non-operational until audited service exists',()=>{
 assert.match(source,/getBackupCenterStatus\(\)/);
 assert.match(source,/تنزيل النسخ والاستعادة معطّلان/);
});
