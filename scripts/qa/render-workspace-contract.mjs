// Isolated React SSR test. No browser, auth login, database request, or deployed test bypass.
import {build} from 'esbuild';import{readFileSync,writeFileSync}from'node:fs';import{createRequire}from'node:module';import assert from'node:assert/strict';
const require=createRequire(import.meta.url);const React=require('react'),{renderToStaticMarkup}=require('react-dom/server');const results=[];
const source=readFileSync('src/main.jsx','utf8').replace(/createRoot\(document\.getElementById\('root'\)\)\.render\([\s\S]*?;\s*$/,'export {Admin};');
const compiled=await build({stdin:{contents:source,resolveDir:process.cwd()+'/src',loader:'jsx'},bundle:true,write:false,platform:'node',format:'cjs',external:['react','react-dom','react-dom/client'],loader:{'.css':'empty'},define:{'import.meta.env.VITE_SUPABASE_URL':JSON.stringify('https://vpjxdsprfcpqclnhbeoh.supabase.co'),'import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY':JSON.stringify('qa-fixture-only'),'import.meta.env.VITE_ENABLE_AUTH_MUTATIONS':'"true"','import.meta.env.MODE':'"staging"'},plugins:[{name:'no-network-auth-fixture',setup(b){b.onResolve({filter:/^@supabase\/supabase-js$/},()=>({path:'auth-fixture',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const createClient=()=>({auth:{},rpc:()=>{throw new Error("SSR must not request data")}});',loader:'js'}))}}]});
const module={exports:{}};new Function('require','module','exports',compiled.outputFiles[0].text)(require,module,module.exports);const {Admin}=module.exports;
try{
 for(const role of ['system_admin','employee','technical_support'])for(const initialTab of ['dashboard','pos','pharmacyProducts','siteProducts','inventory','smart','purchases','suppliers','supplierDebts','orders','prescriptions','requests','customers','debtors','offers','cashbox','returns','reports','profitCenterPreview','systemCenter','security']){
  const html=renderToStaticMarkup(React.createElement(Admin,{role,initialTab,onLogout:()=>{}}));
  assert.ok(html.includes('adminShell'));assert.ok(html.includes('sideBrand'));assert.ok(html.includes('adminTopbar'));assert.ok(html.includes('لوحة التحكم'));assert.ok(html.includes('مركز الأرباح الذكي'));
  if(role!=='system_admin'&&initialTab==='reports'){assert.ok(html.includes('inert=""'));assert.ok(html.includes('••••'));assert.ok(html.includes('الأرقام محجوبة'))}
  if(role==='technical_support'&&['pos','inventory','purchases'].includes(initialTab))assert.ok(html.includes('inert=""'));
  if(role==='employee'&&initialTab==='pos')assert.ok(html.includes('فاتورة البيع'));
  results.push({name:role+' original Admin '+initialTab+' SSR renders safely',passed:true});
 }
}catch(error){results.push({name:'SSR render',passed:false,error:error.message});throw error}finally{writeFileSync('/tmp/pharmacy-workspace-render-results.json',JSON.stringify({results},null,2));console.log({passed:results.filter(x=>x.passed).length,failed:results.filter(x=>!x.passed)})}
