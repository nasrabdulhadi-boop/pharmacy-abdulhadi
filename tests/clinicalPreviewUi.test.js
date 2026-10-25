import test from 'node:test';
import assert from 'node:assert/strict';
import {createLatestPreviewTask,clinicalPreviewMessage,clinicalReviewIssueMessages} from '../src/clinicalPreviewUi.js';
import {inspectBilingualReviewCsv} from '../src/clinicalReviewCsvIntake.js';
import {exportBilingualReviewTemplateCsv} from '../src/clinicalAliasReviewPackage.js';
import {summarizeIngredientAliasCandidates} from '../src/clinicalAliasCandidates.js';

function deferred(){let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject}}

test('late search result cannot overwrite a newer result or clear its loading indicator',async()=>{
 const task=createLatestPreviewTask(),old=deferred(),current=deferred();
 const state={result:null,busy:true};
 const handlers={success:value=>{state.result=value},settled:()=>{state.busy=false}};
 const first=task.run(()=>old.promise,handlers),second=task.run(()=>current.promise,handlers);
 old.resolve(['old']);await first;
 assert.deepEqual(state,{result:null,busy:true});
 current.resolve(['current']);await second;
 assert.deepEqual(state,{result:['current'],busy:false});
});

test('starting a new audit invalidates a pending CSV inspection, including late errors',async()=>{
 for(const failure of [false,true]){
  const task=createLatestPreviewTask(),file=deferred(),updates=[];
  const pending=task.run(()=>file.promise,{success:x=>updates.push(x),error:e=>updates.push(e),settled:()=>updates.push('settled')});
  task.invalidate();
  if(failure)file.reject(new Error('old CSV'));else file.resolve({acceptedCount:10});
  await pending;assert.deepEqual(updates,[]);
 }
});

test('current request failures are displayed and loading is released',async()=>{
 const updates=[];
 await createLatestPreviewTask().run(()=>{throw new Error('denied')},{success:()=>assert.fail('no success'),error:e=>updates.push(e.message),settled:()=>updates.push('settled')});
 assert.deepEqual(updates,['denied','settled']);
});

test('template rejection reasons are localized without granting clinical approval',()=>{
 const candidates=[{alias:'باراسيتامول',language:'ar'}];
 const result=inspectBilingualReviewCsv(exportBilingualReviewTemplateCsv(candidates),candidates);
 const messages=clinicalReviewIssueMessages(result);
 assert.equal(messages.length,1);
 assert.match(messages[0],/السجل 2/);
 assert.match(messages[0],/معرّف المادة الفعالة/);
 assert.doesNotMatch(messages[0],/missing|approved/);
 assert.equal(result.acceptedCount,0);assert.equal(result.productionEnabled,false);
 assert.equal(result.clinicalRulesActivated,0);
});

test('review details enforce one combined 50-item limit across issue categories',()=>{
 const result={rejected:Array.from({length:30},(_,index)=>({index,problems:['missing alias']})),unrecognized:Array.from({length:30},(_,index)=>({index,alias:'unknown'})),conflicts:[{alias:'x',first:'a',second:'b'}]};
 assert.equal(clinicalReviewIssueMessages(result).length,50);
 assert.equal(clinicalReviewIssueMessages(result,100).length,61);
 assert.equal(clinicalPreviewMessage('Empty CSV'),'ملف CSV فارغ');
 assert.equal(clinicalPreviewMessage('Invalid column count at row 4'),'عدد الأعمدة غير صحيح في السجل 4');
});

test('language summary accounts for every candidate, including unsupported scripts',()=>{
 const result=summarizeIngredientAliasCandidates([{language:'ar'},{language:'en'},{language:'mixed'},{language:'other'}]);
 assert.equal(result.total,result.arabic+result.english+result.mixed+result.other);
 assert.equal(result.approved,0);
});
