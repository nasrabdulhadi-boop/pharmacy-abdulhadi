#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
node --test src/currency-pricing.test.js
node --input-type=module - <<'JS'
import fs from 'node:fs';
import assert from 'node:assert/strict';
const src=fs.readFileSync('src/main.jsx','utf8');
assert.match(src,/import \{posCartPrice,verifyPosCurrencyCart,validUsdRate\} from '\.\/currency-pricing\.js'/);
assert.match(src,/item=posCartPrice\(p,usdRate\)/);
assert.match(src,/verifyPosCurrencyCart\(cart,data\.usd_to_syp\)/);
assert.match(src,/saleBusyRef\.current=true/);
assert.match(src,/finally\{saleBusyRef\.current=false;setSaleBusy\(false\)\}/);
assert.match(src,/p_currency:'SYP'/);
assert.match(src,/base_unit_price:Number\(x\.base_sale_price\?\?x\.sale_price\?\?0\)/);
assert.ok(!src.includes('base_sale_price:Number(p.sale_price||0),part:defaultPart'));
console.log('PASS: 8 POS integration assertions');
JS
