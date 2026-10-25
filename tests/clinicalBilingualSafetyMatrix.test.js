import test from 'node:test';
import assert from 'node:assert/strict';
import {createBilingualAliasIndex,resolveBilingualIngredient} from '../src/clinicalBilingualMapping.js';
import {inspectBilingualReviewPackage} from '../src/clinicalAliasReviewPackage.js';
const alias=(name,language,id)=>({alias:name,language,canonical_ingredient_id:id,status:'approved',reviewer_id:'synthetic-pharmacist',reviewed_at:'2026-10-25',source_reference_id:'synthetic-source',source_version:'test',source_document_id:'synthetic-document'});
test('Arabic and English require explicit reviewed mapping, not transliteration',()=>{
 const index=createBilingualAliasIndex([alias('Paracetamol','en','ingredient-1')]).index;
 assert.equal(resolveBilingualIngredient('باراسيتامول',index).status,'unverified');
 assert.equal(resolveBilingualIngredient('Paracetamol',index).canonicalIngredientId,'ingredient-1');
});
test('reviewed bilingual labels may share one canonical identity without implying safety',()=>{
 const result=createBilingualAliasIndex([alias('باراسيتامول','ar','ingredient-1'),alias('Paracetamol','en','ingredient-1')]);
 assert.equal(result.conflicts.length,0);
 assert.equal(resolveBilingualIngredient('باراسيتامول',result.index).canonicalIngredientId,'ingredient-1');
 assert.equal(resolveBilingualIngredient('PARACETAMOL',result.index).canonicalIngredientId,'ingredient-1');
});
test('Arabic hamza normalization collision with differing identities is quarantined',()=>{
 const r=inspectBilingualReviewPackage([alias('إختبار','ar','ingredient-a'),alias('اختبار','ar','ingredient-b')],[{alias:'اختبار'}]);
 assert.equal(r.accepted.length,0);
 assert.equal(r.conflicts.length,1);
 assert.equal(r.eligibleForProduction,false);
});
test('unreviewed synthetic Arabic label never enters index',()=>{
 const r=createBilingualAliasIndex([{...alias('دواء تجريبي','ar','ingredient-a'),status:'candidate'}]);
 assert.equal(r.invalid.length,1);
 assert.equal(resolveBilingualIngredient('دواء تجريبي',r.index).canonicalIngredientId,null);
});
