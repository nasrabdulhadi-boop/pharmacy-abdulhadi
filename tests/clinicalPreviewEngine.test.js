import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeIngredientName,parseIngredientField,screenExactIngredientOverlap,auditClinicalCatalog,buildIngredientReviewQueue,clinicalAuditCsv} from '../src/clinicalPreviewEngine.js';

test('camelCase and hamza are normalized without inventing synonyms',()=>{
 assert.equal(normalizeIngredientName('diclofenacSodium'),'diclofenac sodium');
 assert.equal(normalizeIngredientName('إيبوبروفين'),'ايبوبروفين');
});
test('combination is split only on explicit plus',()=>{
 assert.deepEqual(parseIngredientField('amoxicillin + clavulanicAcid').components,['amoxicillin','clavulanic acid']);
});
test('shared ingredient across combination and single product is flagged',()=>{
 const r=screenExactIngredientOverlap([{id:1,name:'A',active_ingredient:'amoxicillin + clavulanicAcid'},{id:2,name:'B',active_ingredient:'amoxicillin'}]);
 assert.equal(r.overlaps.length,1);
 assert.deepEqual(r.overlaps[0].shared,['amoxicillin']);
});
test('unknown ingredient does not produce false clearance',()=>{
 const r=screenExactIngredientOverlap([{id:1,name:'A',active_ingredient:''},{id:2,name:'B',active_ingredient:'ibuprofen'}]);
 assert.equal(r.unresolved.length,1);
 assert.equal(r.overlaps.length,0);
});
test('ambiguous separators and doses require manual review',()=>{
 assert.equal(parseIngredientField('drugA/drugB').status,'review');
 assert.equal(parseIngredientField('ibuprofen 400 mg').status,'review');
 assert.equal(parseIngredientField('drugA + ').status,'review');
});
test('different names are not assumed equivalent',()=>{
 const r=screenExactIngredientOverlap([{id:1,name:'A',active_ingredient:'acetaminophen'},{id:2,name:'B',active_ingredient:'paracetamol'}]);
 assert.equal(r.overlaps.length,0);
});

test('catalog audit counts missing and ambiguous fields without editing inputs',()=>{
 const products=[{id:'a',name:'A',active_ingredient:'',strength:'',dosage_form:'tablet'},{id:'b',name:'B',active_ingredient:'amoxicillin + clavulanicAcid',strength:'500 mg',dosage_form:''},{id:'c',name:'C',active_ingredient:'drugA/drugB',strength:'',dosage_form:''}];
 const before=JSON.stringify(products);
 const r=auditClinicalCatalog(products);
 assert.deepEqual(r.counts,{total:3,missingIngredient:1,manualReview:1,missingStrength:2,missingForm:2,parseable:1});
 assert.equal(r.issues.length,3);
 assert.equal(JSON.stringify(products),before);
});

test('review queue groups exact normalized components but does not approve synonyms',()=>{
 const q=buildIngredientReviewQueue([{id:'1',name:'A',active_ingredient:'diclofenacSodium + paracetamol'},{id:'2',name:'B',active_ingredient:'diclofenac sodium'},{id:'3',name:'C',active_ingredient:'acetaminophen'}]);
 assert.equal(q.find(x=>x.normalized==='diclofenac sodium').productCount,2);
 assert.equal(q.find(x=>x.normalized==='paracetamol').productCount,1);
 assert.equal(q.find(x=>x.normalized==='acetaminophen').productCount,1);
 assert.ok(q.every(x=>x.status==='unverified'));
});
test('CSV export quotes values and mitigates spreadsheet formula injection',()=>{
 const csv=clinicalAuditCsv([{id:'x',name:'=HYPERLINK("https://bad")',active_ingredient:'ibuprofen',strength:'400',dosage_form:'tablet'}]);
 assert.ok(csv.includes("'=HYPERLINK"));
 assert.ok(csv.includes('""https://bad""'));
});
