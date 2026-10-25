import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeClinicalSearch,buildClinicalSearchIndex,searchClinicalCatalog} from '../src/clinicalCatalogSearch.js';
test('clinical catalog search ignores hamza, diacritics, tatweel and numeral scripts',()=>{
 const rows=[{id:'a',name:'إِيـبوبروفين',strength:'500mg',barcode:'00123',active_ingredient:'Ibuprofen'}];
 const index=buildClinicalSearchIndex(rows);
 assert.equal(searchClinicalCatalog(index,'ايبوبروفين')[0].id,'a');
 assert.equal(searchClinicalCatalog(index,'IBUPROFEN ۵۰۰')[0].id,'a');
 assert.equal(searchClinicalCatalog(index,'٠٠١٢٣')[0].id,'a');
 assert.equal(searchClinicalCatalog(index,'123').length,0);
 assert.equal(rows[0].name,'إِيـبوبروفين');
});
test('exact barcode ranks before names; unreviewed translation is never invented',()=>{
 const index=buildClinicalSearchIndex([{id:'barcode',name:'Other',barcode:'123'},{id:'name',name:'123'},{id:'english',name:'English',active_ingredient:'paracetamol'}]);
 assert.deepEqual(searchClinicalCatalog(index,'123').map(x=>x.id),['barcode','name']);
 assert.equal(searchClinicalCatalog(index,'باراسيتامول').length,0);
});
test('inactive and duplicate products cannot silently become selected search results',()=>{
 const index=buildClinicalSearchIndex([{id:'dup',name:'A'},{id:'dup',name:'A'},{id:'inactive',name:'A',active:false},null,{name:'A'}]);
 assert.deepEqual(searchClinicalCatalog(index,'A'),[]);
 assert.equal(normalizeClinicalSearch(''), '');
});
test('search has bounded results and treats wildcard and markup strings literally',()=>{
 const index=buildClinicalSearchIndex(Array.from({length:18000},(_,i)=>({id:String(i),name:'Synthetic medicine '+i,active_ingredient:'Synthetic'})));
 assert.equal(searchClinicalCatalog(index,'Synthetic').length,20);
 for(const q of ['','   ','%','<script>','x'.repeat(129)])assert.equal(searchClinicalCatalog(index,q).length,0);
});

test('live RPC results preserve additional barcode matches and fresh fields when merged with audit cache',async()=>{
 const {mergeClinicalSearchResults}=await import('../src/clinicalCatalogSearch.js');
 const live=[{id:'additional-barcode',name:'Live match'},{id:'same',name:'Current'}];
 const local=[{id:'same',name:'Outdated'},{id:'normalized',name:'Normalized match'}];
 assert.deepEqual(mergeClinicalSearchResults(live,local).map(x=>x.name),['Live match','Current','Normalized match']);
});
