import test from 'node:test';
import assert from 'node:assert/strict';
import {prepareRegister,queueSale,markSynced} from '../src/offlineSaleQueue.js';
const day='2026-11-14';
const now=Date.parse(day+'T12:00:00Z');
const fixture={role:'employee',fx_rate:140,products:[{id:'a',active:true,name:'QA',barcode:'QA-1',sale_currency:'USD',sale_price:'2.125'}],
 batches:[{product_id:'a',quantity:5,expiry_date:day},{product_id:'a',quantity:20,expiry_date:'2026-11-13'}]};
test('offline save excludes expired stock and preserves cash total and order identity across reload',()=>{
 const register=prepareRegister('user',fixture,null,now,day);
 const saved=queueSale(register,[{id:'a',quantity:3}],'local',now,day);
 const reopened=JSON.parse(JSON.stringify(saved));
 assert.equal(reopened.products[0].stock,2);
 assert.equal(reopened.sales[0].total,8925000);
 assert.equal(reopened.sales[0].lines[0].unitPrice,'297.5000');
 assert.throws(()=>queueSale(reopened,[{id:'a',quantity:3}],'two',now,day),/insufficient_stock/);
 assert.throws(()=>prepareRegister('user',fixture,reopened,now,day),/sync_first/);
 const synced=markSynced(reopened,'local','remote');
 assert.equal(synced.lastReceipt.serverId,'remote');
 assert.equal(synced.sales.length,0);
 assert.throws(()=>queueSale(synced,[{id:'a',quantity:1}],'two',now,day),/expired_snapshot/);
});
test('a disconnected register cannot keep selling into the next business day',()=>{
 const register=prepareRegister('user',fixture,null,now,day);
 assert.throws(()=>queueSale(register,[{id:'a',quantity:1}],'local',now+1,'2026-11-15'),/expired_snapshot/);
 assert.throws(()=>prepareRegister('user',{...fixture,role:'technical_support'},null,now,day),/invalid_catalog/);
});
