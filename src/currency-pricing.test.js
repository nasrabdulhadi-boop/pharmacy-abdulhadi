import test from 'node:test';
import assert from 'node:assert/strict';
import {posCartPrice,verifyPosCurrencyCart,validUsdRate} from './currency-pricing.js';

test('does not convert historical SYP products when rate is missing',()=>{
 const c=posCartPrice({id:'a',sale_price:25000,sale_currency:'SYP'},null);
 assert.equal(c.sale_price,25000);assert.equal(c.base_sale_price,25000);assert.equal(c.price_fx_rate,1);
});
test('keeps the original USD price, exchange snapshot, and converted SYP separately',()=>{
 const c=posCartPrice({id:'a',sale_price:3,sale_currency:'USD',sale_price_syp:42000,current_fx_rate:14000},14000);
 assert.equal(c.base_sale_price,3);assert.equal(c.sale_price,42000);assert.equal(c.base_sale_price_syp,42000);assert.equal(c.price_fx_rate,14000);
 assert.equal(verifyPosCurrencyCart([c],14000),true);
});
test('rejects an invalid or missing exchange rate, including default 1',()=>{
 for(const rate of [null,undefined,1,0,'',NaN,Infinity])assert.equal(validUsdRate(rate),false);
 assert.throws(()=>posCartPrice({sale_currency:'USD',sale_price:3,current_fx_rate:1},1));
});
test('rejects stale rate during lookup and at checkout',()=>{
 assert.throws(()=>posCartPrice({sale_currency:'USD',sale_price:3,current_fx_rate:12000},14000),/تغيّر سعر الصرف/);
 const c=posCartPrice({sale_currency:'USD',sale_price:3,sale_price_syp:42000,current_fx_rate:14000},14000);
 assert.throws(()=>verifyPosCurrencyCart([c],15000),/تغيّر سعر صرف/);
});
test('rejects legacy draft with no USD price snapshot',()=>{
 assert.throws(()=>verifyPosCurrencyCart([{sale_currency:'USD',base_sale_price:42000,sale_price:42000}],14000),/مسودة قديمة/);
});
test('rejects inconsistent backend SYP conversion',()=>{
 assert.throws(()=>posCartPrice({sale_currency:'USD',sale_price:3,current_fx_rate:14000,sale_price_syp:3},14000),/لا يطابق/);
});
test('allows manual SYP edit without mutating the original USD price',()=>{
 const c=posCartPrice({sale_currency:'USD',sale_price:3,current_fx_rate:14000},14000);
 const updated={...c,sale_price:40500};
 assert.equal(updated.base_sale_price,3);assert.equal(verifyPosCurrencyCart([updated],14000),true);
});
