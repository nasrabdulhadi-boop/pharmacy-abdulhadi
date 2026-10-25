import test from 'node:test';
import assert from 'node:assert/strict';
import {screenBilingualReviewedPairs} from '../src/clinicalBilingualScreening.js';
const src={reviewer_id:'synthetic',reviewed_at:'2026-10-25',source_reference_id:'synthetic',source_version:'1',source_document_id:'synthetic'};
const alias=(name,id)=>({...src,alias:name,language:'en',canonical_ingredient_id:id,status:'approved'});
const mapping=(product_id,ingredient_id)=>({...src,product_id,ingredient_id,status:'approved',composition_verified:true});
const product=(id,name,ingredient)=>({id,active_ingredient:name,verified_composition:{...src,status:'approved',ingredient_ids:[ingredient]}});
const rule={...src,id:'synthetic-rule',ingredient_a_id:'a',ingredient_b_id:'b',severity:'major',mechanism:'synthetic',recommendation:'synthetic',reference_id:'synthetic',status:'approved',active:true};
test('duplicate product IDs are quarantined even if one record looks valid',()=>{
 const r=screenBilingualReviewedPairs([product('dup','Ingredient A','a'),product('dup','Ingredient A','a'),product('other','Ingredient B','b')],
 [alias('Ingredient A','a'),alias('Ingredient B','b')],[mapping('dup','a'),mapping('other','b')],[rule]);
 assert.equal(r.findings.length,0);
 assert.equal(r.status,'incomplete');
 assert.equal(r.unresolved.filter(x=>x.productId==='dup'&&x.reason==='duplicate_product_id').length,2);
 assert.equal(r.safeToCombine,null);
});
test('unique product IDs still permit limited synthetic reviewed screening',()=>{
 const r=screenBilingualReviewedPairs([product('first','Ingredient A','a'),product('second','Ingredient B','b')],
 [alias('Ingredient A','a'),alias('Ingredient B','b')],[mapping('first','a'),mapping('second','b')],[rule]);
 assert.equal(r.findings.length,1);assert.equal(r.productionEnabled,false);
});
