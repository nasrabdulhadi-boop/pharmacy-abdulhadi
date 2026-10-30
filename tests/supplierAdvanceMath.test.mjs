import test from 'node:test';
import assert from 'node:assert/strict';
import {purchaseAdvancePreview as quote} from '../src/supplierAdvanceMath.js';
test('invoice excess becomes credit, and credit pays the next invoice',()=>{
 assert.deepEqual(quote(100,120,0),{used:0,cashDue:100,created:20,due:0,balance:20});
 assert.deepEqual(quote(50,0,20),{used:20,cashDue:30,created:0,due:30,balance:0});
 assert.deepEqual(quote(5,10,40),{used:5,cashDue:0,created:10,due:0,balance:45});
});
test('six decimal account amounts conserve money without cent rounding',()=>{
 const v=quote(1,0.67,0.333333);
 assert.deepEqual(v,{used:0.333333,cashDue:0.666667,created:0.003333,due:0,balance:0.003333});
 assert.deepEqual(quote(0,15,0),{used:0,cashDue:0,created:15,due:0,balance:15});
});
test('invalid or unsafe money cannot be quoted',()=>{
 for(const value of [-1,NaN,Infinity,1e14]) assert.equal(quote(100,value,0),null);
});
