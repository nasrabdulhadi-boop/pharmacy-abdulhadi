import test from 'node:test';
import assert from 'node:assert/strict';

const STAGING_URL='https://vpjxdsprfcpqclnhbeoh.supabase.co';
const key=process.env.STAGING_SUPABASE_PUBLISHABLE_KEY;
const supportToken=process.env.STAGING_SUPPORT_ACCESS_TOKEN;
const enabled=process.env.RUN_STAGING_SUPPORT_SMOKE==='true';
const decodePayload=(token)=>{try{const part=token.split('.')[1];return JSON.parse(Buffer.from(part,'base64url').toString('utf8'))}catch{return null}};

test('staging technical support cannot read privileged product RPC', {skip:!enabled?'Set RUN_STAGING_SUPPORT_SMOKE=true to run with isolated QA credentials':false}, async()=>{
 assert.ok(key&&supportToken,'Provide QA-only publishable key and a technical-support JWT as environment secrets');
 const claims=decodePayload(supportToken);
 assert.equal(claims?.iss,`${STAGING_URL}/auth/v1`,'Support JWT must belong to isolated QA project');
 assert.equal(claims?.app_metadata?.system_role,'technical_support','Must use a real technical-support token, never admin');
 assert.notEqual(claims?.app_metadata?.role,'admin','Support token must not carry legacy admin access');
 assert.ok(typeof claims?.exp==='number'&&claims.exp>Date.now()/1000,'Support token must not be expired');
 const response=await fetch(`${STAGING_URL}/rest/v1/rpc/admin_get_products_page`,{
  method:'POST',headers:{'apikey':key,'Authorization':`Bearer ${supportToken}`,'Content-Type':'application/json'},
  body:JSON.stringify({p_limit:5,p_offset:0})
 });
 const body=await response.text();
 assert.ok(response.status===401||response.status===403||(response.ok&&JSON.parse(body)?.length===0),
  `Support must not receive product rows (HTTP ${response.status}); response intentionally omitted`);
});
