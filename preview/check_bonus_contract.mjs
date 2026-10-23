// Run: node preview/check_bonus_contract.mjs
// Static contract checks only; these do not replace integration tests against an isolated database.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const ui=fs.readFileSync('src/main.jsx','utf8');
const sql=fs.readFileSync('preview/bonus_only_purchase_preview.sql','utf8');
const purchase=ui.slice(ui.indexOf('function Purchases('),ui.indexOf('function ',ui.indexOf('function Purchases(')+20));
const inventory=ui.slice(ui.indexOf('function Inventory('),ui.indexOf('function ',ui.indexOf('function Inventory(')+20));
const checks=[
 ['bonus-only invoice line accepted',purchase.includes('(Number(x.quantity)+Number(x.bonus_quantity||0))>0')],
 ['paid quantity input permits zero',purchase.includes('min="0" value={x.quantity}')],
 ['bonus excluded from subtotal',purchase.includes('Number(x.quantity||0)*Number(x.purchase_price||0)')],
 ['free bonus does not require paid purchase price',purchase.includes('Number(x.quantity)>0&&Number(x.purchase_price)<=0')],
 ['SYP paid batch conditional',sql.includes('IF v_qty>0 THEN')],
 ['SYP bonus line points to bonus batch',sql.includes('IF v_qty=0 THEN UPDATE public.purchase_items SET batch_id=v_bonus_batch_id')],
 ['USD bonus line points to bonus batch',sql.includes('IF v_qty=0 THEN UPDATE public.purchase_items SET batch_id=v_batch_bonus')],
 ['USD subtotal excludes bonus',sql.includes('v_sum:=v_sum+v_qty*v_net_usd')],
 ['SYP subtotal excludes bonus',sql.includes('v_total:=v_total+(v_qty*v_purchase_price)')],
 ['inventory displays bonus marker',inventory.includes('🎁 بونص')],
 ['admin-only bonus lookup',sql.includes('REVOKE ALL ON FUNCTION public.admin_bonus_batch_ids() FROM PUBLIC, anon;')]
];
for(const [label,ok] of checks){console.log((ok?'PASS':'FAIL')+' '+label);assert.ok(ok,label);}
console.log('Static checks passed. Database integration and sale tests still required.');
