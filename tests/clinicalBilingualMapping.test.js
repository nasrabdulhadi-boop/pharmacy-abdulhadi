import test from 'node:test';
import assert from 'node:assert/strict';
import {createBilingualAliasIndex,resolveBilingualIngredient,matchBilingualProducts} from '../src/clinicalBilingualMapping.js';
const alias=(text,language,id='ingredient-1')=>({alias:text,language,canonical_ingredient_id:id,status:'approved',reviewer_id:'pharmacist-test',reviewed_at:'2026-10-25',source_reference_id:'synthetic-label',source_version:'test',source_document_id:'synthetic-document'});
test('approved Arabic and English labels resolve to the same canonical ingredient',()=>{
 const {index}=createBilingualAliasIndex([alias('باراسيتامول','ar'),alias('Paracetamol','en')]);
 assert.equal(resolveBilingualIngredient('باراسيتامول',index).canonicalIngredientId,'ingredient-1');
 assert.equal(resolveBilingualIngredient('PARACETAMOL',index).canonicalIngredientId,'ingredient-1');
});
test('conflicting approved aliases never resolve automatically',()=>{
 const result=createBilingualAliasIndex([alias('دواء','ar','a'),alias('دواء','ar','b')]);
 assert.equal(result.conflicts.length,1);
 assert.equal(resolveBilingualIngredient('دواء',result.index).status,'ambiguous');
});
test('unreviewed alias and unknown name fail closed',()=>{
 const result=createBilingualAliasIndex([{...alias('Example','en'),status:'draft'}]);
 assert.equal(result.invalid.length,1);
 assert.equal(resolveBilingualIngredient('Example',result.index).status,'unverified');
});
test('language mapping does not claim clinical safety or complete composition',()=>{
 const result=matchBilingualProducts([{id:1,active_ingredient:'باراسيتامول'},{id:2,active_ingredient:'Paracetamol'}],[],[alias('باراسيتامول','ar'),alias('Paracetamol','en')]);
 assert.equal(result.results[0].languageIndependentIngredientId,result.results[1].languageIndependentIngredientId);
 assert.equal(result.results.every(x=>x.eligibleForClinicalScreening===false),true);
});
