import test from 'node:test';
import assert from 'node:assert/strict';

const STAGING_URL='https://vpjxdsprfcpqclnhbeoh.supabase.co';
const key=process.env.STAGING_SUPABASE_PUBLISHABLE_KEY;
const supportToken=process.env.STAGING_SUPPORT_ACCESS_TOKEN;
const enabled=process.env.RUN_STAGING_SUPPORT_SMOKE==='true';

test('staging technical support cannot read privileged product RPC', {skip:!enabled?'Set RUN_STAGING_SUPPORT_SMOKE=true to run with isolated QA credentials':false}, async()=>{
 assert.ok(key&&supportToken,'Provide QA-only publishable key and a technical-support JWT as environment secrets');
 const response=await fetch(`${STAGING_URL}/rest/v1/rpc/admin_get_products_page`,{
  method:'POST',headers:{'apikey':key,'Authorization':`Bearer ${supportToken}`,'Content-Type':'application/json'},
  body:JSON.stringify({p_limit:5,p_offset:0})
 });
 const body=await response.text();
 assert.ok(response.status===401||response.status===403||(response.ok&&JSON.parse(body)?.length===0),
  `Support must not receive product rows (HTTP ${response.status}); response intentionally omitted`);
});
