import test from 'node:test';
import assert from 'node:assert/strict';
import {previewLocalBilingualIdentity} from '../src/clinicalIdentitySandbox.js';
import {inspectBilingualReviewCsv} from '../src/clinicalReviewCsvIntake.js';
import {exportBilingualReviewTemplateCsv} from '../src/clinicalAliasReviewPackage.js';
const source={reviewer_id:'synthetic-reviewer',reviewed_at:'2026-10-25',source_reference_id:'synthetic',source_version:'test',source_document_id:'synthetic-document'};
const alias=(name,id,language='en')=>({...source,alias:name,language,canonical_ingredient_id:id,status:'approved'});
const product=(id,active_ingredient)=>({id,name:'Synthetic '+id,active_ingredient});

test('local Arabic and English aliases share an identity without creating a clinical result',()=>{
 const result=previewLocalBilingualIdentity([product('ar','باراسيتامول'),product('en','Paracetamol')],[alias('باراسيتامول','synthetic-a','ar'),alias('Paracetamol','synthetic-a')]);
 assert.equal(result.identityOverlaps.length,1);
 assert.deepEqual(result.identityOverlaps[0].sharedIngredientIds,['synthetic-a']);
 assert.equal(result.clinicallyApproved,false);assert.equal(result.productionEnabled,false);
 assert.equal(result.clinicalRulesActivated,0);assert.equal(result.safeToCombine,null);
 assert.equal(result.sourceVerification,'not_performed');
});
test('no dictionary means unresolved, with no inferred translations',()=>{
 const result=previewLocalBilingualIdentity([product('a','باراسيتامول'),product('b','Paracetamol')],[]);
 assert.equal(result.matched.length,0);assert.equal(result.unresolved.length,2);
 assert.equal(result.identityOverlaps.length,0);
});
test('partially documented combination cannot create identity findings',()=>{
 const result=previewLocalBilingualIdentity([product('combo','مادة ا + Ingredient C'),product('single','Ingredient A')],[alias('مادة ا','a','ar'),alias('Ingredient A','a')]);
 assert.equal(result.identityOverlaps.length,0);
 assert.equal(result.unresolved[0].reason,'alias_missing_or_conflicting');
});
test('fully documented synthetic combination matches only explicitly mapped components',()=>{
 const result=previewLocalBilingualIdentity([product('combo','مادة ا + Ingredient C'),product('single','Ingredient A')],[alias('مادة ا','a','ar'),alias('Ingredient A','a'),alias('Ingredient C','c')]);
 assert.equal(result.identityOverlaps.length,1);assert.equal(result.unresolved.length,0);
});
test('conflicting aliases, duplicate product IDs and malformed composition fail closed',()=>{
 const result=previewLocalBilingualIdentity([product('dup','Ingredient A'),product('dup','Ingredient A'),product('other','مادة ا'),product('dose','Ingredient A 500 mg')],[alias('Ingredient A','a'),alias('مادة ا','a','ar'),alias('مادة ا','b','ar')]);
 assert.equal(result.identityOverlaps.length,0);assert.equal(result.unresolved.length,4);
 assert.equal(result.aliasConflicts.length,1);
});
test('salts keep separate explicit identities and are never merged by spelling',()=>{
 const result=previewLocalBilingualIdentity([product('sodium','Diclofenac Sodium'),product('potassium','Diclofenac Potassium')],[alias('Diclofenac Sodium','sodium'),alias('Diclofenac Potassium','potassium')]);
 assert.equal(result.matched.length,2);assert.equal(result.identityOverlaps.length,0);
});
test('candidate CSV does not create aliases for local matching',()=>{
 const candidates=[{alias:'باراسيتامول',language:'ar'},{alias:'paracetamol',language:'en'}];
 const file=inspectBilingualReviewCsv(exportBilingualReviewTemplateCsv(candidates),candidates);
 assert.deepEqual(file.sandboxAliases,[]);
 assert.equal(previewLocalBilingualIdentity([product('a','باراسيتامول'),product('b','paracetamol')],file.sandboxAliases).identityOverlaps.length,0);
});

test('oversized selection is rejected before building a quadratic identity matrix',()=>{
 const result=previewLocalBilingualIdentity(Array.from({length:51},(_,i)=>product(String(i),'Synthetic')),[]);
 assert.equal(result.identityOverlaps.length,0);assert.equal(result.unresolved[0].reason,'identity_selection_limit');
 assert.equal(result.productionEnabled,false);
});

test('review CSV to local bilingual simulation works end-to-end without enabling clinical screening',()=>{
 const rows=[alias('باراسيتامول','synthetic-a','ar'),alias('Paracetamol','synthetic-a')];
 const columns=['alias','language','canonical_ingredient_id','status','source_reference_id','source_version','source_url','source_document_id','reviewer_id','reviewed_at'];
 const csv='\uFEFF'+[columns.join(','),...rows.map(row=>columns.map(c=>'"'+String(row[c]||'').replaceAll('"','""')+'"').join(','))].join('\r\n');
 const intake=inspectBilingualReviewCsv(csv,rows.map(row=>({alias:row.alias})));
 assert.equal(intake.acceptedCount,2);
 const result=previewLocalBilingualIdentity([product('ar','باراسيتامول'),product('en','Paracetamol')],intake.sandboxAliases);
 assert.equal(result.identityOverlaps.length,1);
 assert.equal(result.clinicallyApproved,false);assert.equal(intake.productionEnabled,false);
});
