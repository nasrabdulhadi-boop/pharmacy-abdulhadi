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
