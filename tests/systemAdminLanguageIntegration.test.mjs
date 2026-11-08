import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
test('admin center navigation translates with local language preference',()=>{
 assert.match(source,/adminCenterEnglish=systemLanguage==='en'/);
 assert.match(source,/System Administration Center/);
 assert.match(source,/adminCenterLabels\.overview/);
 assert.match(source,/adminCenterLabels\.preferences/);
 assert.match(source,/dir=\{getSystemDirection\(\)\}/);
 assert.match(source,/SYSTEM_LANGUAGES\.map/);
});
test('density preference adjusts administration center padding',()=>{
 assert.match(source,/adminPrefs\.density==='compact'\?12:24/);
});
