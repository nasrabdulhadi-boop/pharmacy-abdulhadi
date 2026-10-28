import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const config=readFileSync(new URL('../vite.config.js',import.meta.url),'utf8');
test('build config refuses unsafe enabled auth mutation settings',()=>{
 assert.match(config,/loadEnv\(mode,process\.cwd\(\),'VITE_'\)/);
 assert.match(config,/VITE_ENABLE_AUTH_MUTATIONS==='true'/);
 assert.match(config,/!allowStagingAuthMutation\(/);
 assert.match(config,/throw new Error\('Unsafe auth mutation configuration/);
});
