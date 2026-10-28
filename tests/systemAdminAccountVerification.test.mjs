import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../src/main.jsx',import.meta.url),'utf8');
test('admin dashboard reports account verification using getUser',()=>{
 assert.match(source,/const \[accountVerification,setAccountVerification\]=useState\('checking'\)/);
 assert.match(source,/supabase\.auth\.getUser\(\)\.then/);
 assert.match(source,/setAccountVerification\(error\?'unavailable':data\?\.user\?'verified':'signed_out'\)/);
 assert.match(source,/accountVerification==='verified'\?'جلسة مؤكدة من الخادم'/);
});
