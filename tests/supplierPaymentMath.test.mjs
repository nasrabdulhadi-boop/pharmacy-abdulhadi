import test from 'node:test';
import assert from 'node:assert/strict';
import {supplierSettlement,supplierMoney} from '../src/supplierPaymentMath.js';
test('same currency and both conversion directions use decimal arithmetic',()=>{
 assert.equal(supplierSettlement('10','USD','USD','142'),10);
 assert.equal(supplierSettlement('1420','SYP','USD','142'),10);
 assert.equal(supplierSettlement('10','USD','SYP','142'),1420);
 assert.equal(supplierSettlement('1420','SYP','SYP','142'),1420);
 assert.equal(supplierSettlement('1','SYP','USD','3'),0.333333);
 assert.equal(supplierSettlement('1','SYP','USD','128'),0.007813);
 assert.equal(supplierSettlement('0.01','USD','SYP','142.35'),1.4235);
});
test('invalid, nonfinite, subcent or unsafe tender is rejected',()=>{
 for(const amount of ['','NaN','Infinity','-1','0','0.001','1e3','9007199254740991'])assert.equal(supplierSettlement(amount,'USD','USD','142'),null,amount);
 for(const rate of ['0','-1','NaN','Infinity',''])assert.equal(supplierSettlement('10','USD','SYP',rate),null,rate);
 assert.equal(supplierSettlement('10','EUR','USD','142'),null);
});
test('fractional debt remains visible rather than disappearing at two decimals',()=>{
 assert.equal(supplierMoney(0.000001),'0.000001');
 assert.equal(supplierMoney(89.992958),'89.992958');
});
