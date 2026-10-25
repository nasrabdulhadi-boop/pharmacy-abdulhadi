import test from 'node:test';
import assert from 'node:assert/strict';
import {screenBilingualReviewedPairs} from '../src/clinicalBilingualScreening.js';
const source={reviewer_id:'synthetic',reviewed_at:'2026-10-25',source_reference_id:'synthetic',source_version:'1',source_document_id:'synthetic-document'};
const alias=(alias,id)=>({...source,alias,language:'en',canonical_ingredient_id:id,status:'approved'});
const mapping=(product_id,ingredient_id)=>({...source,product_id,ingredient_id,status:'approved',composition_verified:true});
const product=(id,label,ingredient)=>({id,active_ingredient:label,verified_composition:{...source,status:'approved',ingredient_ids:[ingredient]}});
const rule={...source,id:'synthetic-rule',ingredient_a_id:'a',ingredient_b_id:'b',severity:'major',mechanism:'synthetic',recommendation:'synthetic',reference_id:'synthetic',status:'approved',active:true};
const products=[product('one','Ingredient A','a'),product('two','Ingredient B','b')];
const aliases=[alias('Ingredient A','a'),alias('Ingredient B','b')];
test('extraneous conflicting approved ingredient mapping quarantines product',()=>{
 const r=screenBilingualReviewedPairs(products,aliases,[mapping('one','a'),mapping('one','c'),mapping('two','b')],[rule]);
 assert.equal(r.findings.length,0);
 assert.equal(r.status,'incomplete');
 assert.ok(r.unresolved.some(x=>x.productId==='one'&&x.reason==='incomplete_ingredient_mappings'));
 assert.equal(r.safeToCombine,null);
});
test('invalid extra mapping cannot silently replace a verified mapping',()=>{
 const invalid={...mapping('one','c'),status:'candidate'};
 const r=screenBilingualReviewedPairs(products,aliases,[mapping('one','a'),invalid,mapping('two','b')],[rule]);
 assert.equal(r.findings.length,1);
 assert.equal(r.productionEnabled,false);
 assert.equal(r.safeToCombine,null);
});
