import test from 'node:test';
import assert from 'node:assert/strict';
import {ADMIN_PREF_KEY,readAdminPreferences,writeAdminPreferences,normalizeAdminPreferences} from '../src/systemAdminPreferences.js';
test('preferences are allowlisted',()=>{
 assert.deepEqual(normalizeAdminPreferences({language:'en',density:'compact',role:'system_owner',token:'secret'}),{language:'en',density:'compact'});
 assert.deepEqual(normalizeAdminPreferences({language:'xx',density:'wrong'}),{language:'ar',density:'comfortable'});
});
test('malformed and unavailable storage fails safely',()=>{
 assert.deepEqual(readAdminPreferences({getItem:()=>'{'}),{language:'ar',density:'comfortable'});
 assert.equal(writeAdminPreferences({setItem:()=>{throw Error('denied')}},{language:'en'}),false);
});
test('save and restore local preferences only',()=>{
 const memory=new Map();const storage={getItem:k=>memory.get(k),setItem:(k,v)=>memory.set(k,v)};
 assert.equal(writeAdminPreferences(storage,{language:'en',density:'compact',email:'private'}),true);
 assert.deepEqual(readAdminPreferences(storage),{language:'en',density:'compact'});
 assert.equal(memory.get(ADMIN_PREF_KEY).includes('private'),false);
});
