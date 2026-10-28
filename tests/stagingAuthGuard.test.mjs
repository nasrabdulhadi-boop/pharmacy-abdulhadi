import test from 'node:test';
import assert from 'node:assert/strict';
import {allowStagingAuthMutation,ISOLATED_QA_PROJECT_URL} from '../src/stagingAuthGuard.js';
const valid={mode:'staging',enabled:'true',url:ISOLATED_QA_PROJECT_URL,publishableKey:'test-publishable-key'};
test('only explicitly enabled isolated staging may mutate auth',()=>{
 assert.equal(allowStagingAuthMutation(valid),true);
 for(const change of [{mode:'production'},{mode:'development'},{enabled:'false'},{enabled:undefined},{url:'https://eewjjzgwoaxhojnjvzgq.supabase.co'},{url:ISOLATED_QA_PROJECT_URL+'.evil.test'},{publishableKey:''}]){
  assert.equal(allowStagingAuthMutation({...valid,...change}),false,JSON.stringify(change));
 }
 assert.equal(allowStagingAuthMutation(),false);
});
