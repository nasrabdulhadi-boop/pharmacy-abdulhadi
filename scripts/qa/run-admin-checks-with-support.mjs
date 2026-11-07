// Runs the existing QA smoke test with a disposable support session. Never prints tokens.
import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {createClient} from '@supabase/supabase-js';
const fixture=JSON.parse(fs.readFileSync(process.env.QA_ACCOUNT_FIXTURES,'utf8'));
if(fixture.environment!=='isolated-qa')throw new Error('isolated QA fixtures required');
const support=fixture.users.find(user=>user.label==='support');
if(!support?.email.startsWith('admin-close-'))throw new Error('disposable support required');
const client=createClient('https://vpjxdsprfcpqclnhbeoh.supabase.co',fixture.key,{auth:{persistSession:false,autoRefreshToken:false}});
const signed=await client.auth.signInWithPassword({email:support.email,password:support.password});
if(signed.error||!signed.data.session)throw new Error('QA support login failed');
const files=[...fs.readdirSync('tests').filter(name=>name.endsWith('.test.mjs')).map(name=>'tests/'+name),...fs.readdirSync('src').filter(name=>name.endsWith('.test.js')).map(name=>'src/'+name)];
const result=spawnSync(process.execPath,['--test',...files],{stdio:'inherit',env:{...process.env,RUN_STAGING_SUPPORT_SMOKE:'true',STAGING_SUPABASE_PUBLISHABLE_KEY:fixture.key,STAGING_SUPPORT_ACCESS_TOKEN:signed.data.session.access_token}});
process.exit(result.status??1);
