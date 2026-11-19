import {spawnSync} from 'node:child_process';
if (process.env.VERCEL_ENV === 'production') throw new Error('This build is for the isolated manager preview only');
const result=spawnSync(process.execPath,['node_modules/vite/bin/vite.js','build','--mode','staging'],{
 stdio:'inherit',
 env:{...process.env,VITE_SUPABASE_URL:'https://vpjxdsprfcpqclnhbeoh.supabase.co',VITE_SUPABASE_PUBLISHABLE_KEY:'sb_publishable_R8W3y_ZUYp5kCLGifFb1cQ_-2dW4s0d',VITE_ENABLE_AUTH_MUTATIONS:'true'}
});
process.exit(result.status??1);
