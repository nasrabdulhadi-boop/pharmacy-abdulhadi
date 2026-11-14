import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {defineConfig,loadEnv} from 'vite';
import {allowStagingAuthMutation} from './src/stagingAuthGuard.js';

export default defineConfig(({mode})=>{
 const env=loadEnv(mode,process.cwd(),'VITE_');
 if(env.VITE_ENABLE_AUTH_MUTATIONS==='true' && !allowStagingAuthMutation({
  mode,
  enabled:env.VITE_ENABLE_AUTH_MUTATIONS,
  url:env.VITE_SUPABASE_URL,
  publishableKey:env.VITE_SUPABASE_PUBLISHABLE_KEY
 })){
  throw new Error('Unsafe auth mutation configuration: only isolated staging is permitted');
 }
 const offline=mode==='staging'&&env.VITE_SUPABASE_URL==='https://vpjxdsprfcpqclnhbeoh.supabase.co';
 const offlinePage='offline-pos/index.html';
 const precache={
  name:'qa-pos-precache',
  apply:'build',
  async writeBundle(options,bundle){
   const directory=options.dir||'dist';
   const html=await readFile(resolve(directory,offlinePage),'utf8');
   const assets=['/'+offlinePage,'/logo.png',
    ...new Set(Array.from(html.matchAll(/(?:src|href)="(\/assets\/[^"]+)"/g),m=>m[1]))];
   if(!assets.some(path=>path.endsWith('.js')))throw Error('Missing offline entry');
   const version=createHash('sha256')
    .update(html)
    .update(assets.map(path=>bundle[path.slice(1)]?.fileName||path).join(','))
    .digest('hex').slice(0,16);
   const worker=await readFile('public/offline-pos/sw.js','utf8');
   await writeFile(resolve(directory,'offline-pos/sw.js'),worker
    .replace('__OFFLINE_VERSION__',version).replace('/* OFFLINE_ASSETS */ []',JSON.stringify(assets)));
  }
 };
 return {worker:{format:'es'},server:{allowedHosts:['terminal.local']},
  ...(offline?{plugins:[precache],build:{rollupOptions:{input:{main:'index.html',offline:offlinePage}}}}:{})};
});
