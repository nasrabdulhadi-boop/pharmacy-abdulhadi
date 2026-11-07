// Local component interaction fixture, not an authentication bypass.
// Every Auth/RPC call is mocked in a separate, untracked bundle; no network calls.
import {build} from 'esbuild';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
if(process.env.VERCEL_ENV||process.env.CI)throw new Error('Local UI fixture only');
const output='qa-ui-fixture';mkdirSync(output,{recursive:true});
const source=readFileSync('src/main.jsx','utf8').replace(/createRoot\(document\.getElementById\('root'\)\)\.render\([\s\S]*?;\s*$/,'')+
 "\nfunction UiFixture(){const [dark,setDark]=useState(false),[narrow,setNarrow]=useState(false);return <div className={dark?'adminDark':''} style={{minHeight:'100vh',background:dark?'#101d19':'#f7f9fc'}}><p style={{padding:12,background:'#fff0c0',color:'#222'}}>QA UI fixture — synthetic display only; Auth and RPC are mocked.</p><button onClick={()=>setDark(v=>!v)}>Toggle fixture theme</button><button onClick={()=>setNarrow(v=>!v)}>Toggle fixture mobile width</button><div data-fixture-frame style={{width:narrow?390:'100%',maxWidth:'100%',margin:'auto'}}><SystemAdministrationPreview/></div></div>};createRoot(document.getElementById('root')).render(<UiFixture/>);";
const fixture=`const user={id:'00000000-0000-4000-8000-000000000001',email:'ui-fixture@example.invalid',app_metadata:{system_role:'system_owner'},user_metadata:{full_name:'Synthetic UI account'}};
export const createClient=()=>({auth:{
 getUser:async()=>({data:{user},error:null}),getSession:async()=>({data:{session:{user}},error:null}),
 onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}}),
 updateUser:async body=>{if(body.data)user.user_metadata={...user.user_metadata,...body.data};return {data:{user},error:null}},
 signOut:async()=>({error:null}),resetPasswordForEmail:async()=>({error:null})
},rpc:async name=>({error:null,data:name==='qa_support_health'?[{component:'database',status:'healthy'},{component:'authentication',status:'unknown'}]:name==='qa_admin_accounts'?[{id:user.id,email:user.email,system_role:'system_owner'}]:name==='qa_admin_center_status'?{schema_version:1,unprotected_public_tables:0,anonymous_sensitive_tables:0}:null})});`;
await build({stdin:{contents:source,resolveDir:process.cwd()+'/src',loader:'jsx'},bundle:true,outfile:output+'/fixture.js',platform:'browser',format:'esm',
 define:{'import.meta.env.MODE':'"staging"','import.meta.env.VITE_SUPABASE_URL':'"https://vpjxdsprfcpqclnhbeoh.supabase.co"','import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY':'"local-fixture-not-a-key"','import.meta.env.VITE_ENABLE_AUTH_MUTATIONS':'"true"'},
 plugins:[{name:'isolated-no-network-fixture',setup(b){b.onResolve({filter:/^@supabase\/supabase-js$/},()=>({path:'fixture',namespace:'qa-ui'}));b.onLoad({filter:/.*/,namespace:'qa-ui'},()=>({contents:fixture,loader:'js'}));}}]});
writeFileSync(output+'/index.html','<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>QA administration component fixture</title><link rel="stylesheet" href="./fixture.css"></head><body><div id="root"></div><script type="module" src="./fixture.js"></script></body></html>');
console.log('Local no-network UI fixture built');
