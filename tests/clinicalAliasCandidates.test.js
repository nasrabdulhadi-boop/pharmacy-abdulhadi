import test from 'node:test';
import assert from 'node:assert/strict';
import {buildIngredientAliasCandidates,summarizeIngredientAliasCandidates,exportIngredientAliasCandidatesCsv} from '../src/clinicalAliasCandidates.js';
test('separates Arabic and English aliases without guessing translation',()=>{
 const result=buildIngredientAliasCandidates([{id:1,name:'عربي',active_ingredient:'باراسيتامول'},{id:2,name:'English',active_ingredient:'Paracetamol'}]);
 assert.equal(result.length,2);
 assert.equal(summarizeIngredientAliasCandidates(result).arabic,1);
 assert.equal(summarizeIngredientAliasCandidates(result).english,1);
 assert.ok(result.every(x=>x.canonical_ingredient_id===null&&x.status==='candidate'&&!x.clinical_approved));
});
test('groups exact normalized labels and ignores ambiguous dose text',()=>{
 const result=buildIngredientAliasCandidates([{id:1,active_ingredient:'Paracetamol'},{id:2,active_ingredient:'PARACETAMOL'},{id:3,active_ingredient:'Paracetamol 500 mg'}]);
 assert.equal(result.length,1);
 assert.equal(result[0].product_count,2);
});
test('exports reviewable Unicode CSV without formula execution',()=>{
 const csv=exportIngredientAliasCandidatesCsv([{alias:'=test',normalized_alias:'=test',language:'en',product_count:1,example_products:['عينة'],status:'candidate'}]);
 assert.ok(csv.startsWith('\uFEFF'));
 assert.ok(csv.includes("'=test"));
 assert.ok(csv.includes('عينة'));
});
