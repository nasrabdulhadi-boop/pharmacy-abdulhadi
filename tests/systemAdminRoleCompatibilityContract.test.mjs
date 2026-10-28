import test from 'node:test';
import assert from 'node:assert/strict';
import {verifiedSystemRole} from '../src/systemAdminRoleGate.js';
test('server-issued legacy admin role remains compatible with system center',()=>{
 assert.equal(verifiedSystemRole({app_metadata:{role:'admin'}}),'system_admin');
});
test('support role takes precedence over legacy admin',()=>{
 assert.equal(verifiedSystemRole({app_metadata:{role:'admin',system_role:'technical_support'}}),'technical_support');
});
test('unknown explicit system role cannot fall back to admin',()=>{
 assert.equal(verifiedSystemRole({app_metadata:{role:'admin',system_role:'invalid'}}),null);
});
test('email and user metadata cannot elevate privileges',()=>{
 assert.equal(verifiedSystemRole({email:'admin@example.com',user_metadata:{role:'admin'}}),null);
});
