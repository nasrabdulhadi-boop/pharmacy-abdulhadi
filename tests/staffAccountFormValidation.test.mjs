import test from 'node:test';import assert from 'node:assert/strict';
import{validateStaffAccountForm}from'../src/staffAccountFormValidation.js';
const valid={profile:{full_name:'موظف اصطناعي',start_date:''},email:'staff@example.invalid',password:'Synthetic-Only123!',confirmation:'Synthetic-Only123!'};
test('a weak password and mismatched confirmation each return a visible field explanation',()=>{let e=validateStaffAccountForm({...valid,password:'123456789012',confirmation:'other'});assert.match(e.password,/12/);assert.match(e.confirmation,/غير متطابقين/);e=validateStaffAccountForm({...valid,confirmation:''});assert.match(e.confirmation,/التأكيد/);});
test('staff validation reports invalid identity, dates and lengths without submitting',()=>{const e=validateStaffAccountForm({...valid,email:'not email',profile:{full_name:' ',phone:'1'.repeat(41),start_date:'2026-02-30'}});assert.ok(e.email&&e.full_name&&e.phone&&e.start_date);});
test('valid create inputs pass and optional fields remain optional',()=>{assert.deepEqual(validateStaffAccountForm(valid),{});assert.equal(valid.profile.full_name,'موظف اصطناعي');});
test('profile editing does not require a new password and reset does not require profile data',()=>{assert.deepEqual(validateStaffAccountForm({mode:'profile',profile:valid.profile}),{});assert.deepEqual(validateStaffAccountForm({mode:'password',password:valid.password,confirmation:valid.confirmation,managerPassword:'manager-secret'}),{});assert.ok(validateStaffAccountForm({mode:'password'}).password);});

test("reset requires a manager confirmation even when the new employee password is valid",()=>{assert.ok(validateStaffAccountForm({mode:"password",password:valid.password,confirmation:valid.confirmation}).managerPassword);});
