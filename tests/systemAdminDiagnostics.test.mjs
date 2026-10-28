import test from 'node:test';
import assert from 'node:assert/strict';
import {makeTechnicalHealthSnapshot,summarizeTechnicalHealth} from '../src/systemAdminDiagnostics.js';
test('technical snapshot is fixed to four safe components',()=>{
 const snapshot=makeTechnicalHealthSnapshot({observedAt:'2026-10-28T12:00:00.000Z',components:{api:'healthy',database:'degraded',patients:'healthy',token:'secret'}});
 assert.equal(snapshot.length,4);
 assert.deepEqual(snapshot.map(x=>x.component),['authentication','api','database','deployment']);
 assert.equal(JSON.stringify(snapshot).includes('secret'),false);
 assert.equal(JSON.stringify(snapshot).includes('patients'),false);
 assert.equal(summarizeTechnicalHealth(snapshot),'degraded');
});
test('health status is unknown without verified observations',()=>{
 const snapshot=makeTechnicalHealthSnapshot();
 assert.equal(summarizeTechnicalHealth(snapshot),'unknown');
 assert.equal(summarizeTechnicalHealth([]),'unknown');
});
test('health summary handles outages and all healthy',()=>{
 assert.equal(summarizeTechnicalHealth(makeTechnicalHealthSnapshot({components:{api:'unavailable'}})),'unavailable');
 assert.equal(summarizeTechnicalHealth(makeTechnicalHealthSnapshot({components:{authentication:'healthy',api:'healthy',database:'healthy',deployment:'healthy'}})),'healthy');
});
