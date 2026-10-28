import test from 'node:test';
import assert from 'node:assert/strict';
import {verifiedSystemRole,canViewSystemAdminSection} from '../src/systemAdminRoleGate.js';
test('server-controlled app metadata is required',()=>{
 assert.equal(verifiedSystemRole({user_metadata:{system_role:'system_owner'}}),null);
 assert.equal(verifiedSystemRole({app_metadata:{system_role:'technical_support'}}),'technical_support');
 assert.equal(verifiedSystemRole({app_metadata:{system_role:'unknown'}}),null);
});
test('support preview is limited to overview',()=>{
 for(const section of ['profile','access','backup','preferences'])assert.equal(canViewSystemAdminSection('technical_support',section),false);
 assert.equal(canViewSystemAdminSection('technical_support','overview'),true);
 assert.equal(canViewSystemAdminSection(null,'overview'),false);
});

test('explicit technical support role cannot inherit legacy admin privileges',()=>{
 const account={app_metadata:{role:'admin',system_role:'technical_support'}};
 assert.equal(verifiedSystemRole(account),'technical_support');
 for(const section of ['profile','access','backup','preferences'])assert.equal(canViewSystemAdminSection(verifiedSystemRole(account),section),false);
});
test('explicit invalid role fails closed instead of falling back to legacy admin',()=>{
 for(const role of ['invalid','',null,0])assert.equal(verifiedSystemRole({app_metadata:{role:'admin',system_role:role}}),null);
});
test('legacy admin fallback only applies when explicit system role is absent',()=>{
 assert.equal(verifiedSystemRole({app_metadata:{role:'admin'}}),'system_admin');
 assert.equal(verifiedSystemRole({app_metadata:{role:'user'}}),null);
 assert.equal(verifiedSystemRole({email:'admin@example.test',user_metadata:{role:'admin'}}),null);
});
