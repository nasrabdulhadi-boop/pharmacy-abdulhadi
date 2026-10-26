import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
const script=new URL('../qa/clinical-security/run-isolated-supabase.mjs',import.meta.url);
function denied(config,message){
 const folder=mkdtempSync(join(tmpdir(),'clinical-guard-'));
 try{
  const input=join(folder,'synthetic.json');writeFileSync(input,JSON.stringify(config),{mode:0o600});
  const result=spawnSync(process.execPath,[script.pathname,input,'hardened'],{encoding:'utf8',timeout:5000});
  assert.notEqual(result.status,0);assert.match(result.stderr,message);assert.equal(result.stdout,'');
 }finally{rmSync(folder,{recursive:true,force:true})}
}
test('remote integration runner refuses the live pharmacy project before authenticating',()=>{
 denied({project_ref:'eewjjzgwoaxhojnjvzgq'},/Wrong isolated project/);
});
test('remote integration runner refuses a live origin even if the isolated ref is supplied',()=>{
 denied({project_ref:'vpjxdsprfcpqclnhbeoh',base_url:'https://eewjjzgwoaxhojnjvzgq.supabase.co'},/Wrong isolated origin/);
});
test('remote integration runner refuses secret-role keys before authenticating',()=>{
 denied({project_ref:'vpjxdsprfcpqclnhbeoh',base_url:'https://vpjxdsprfcpqclnhbeoh.supabase.co',public_key:'sb_secret_synthetic'},/Only a public API key is allowed/);
});
