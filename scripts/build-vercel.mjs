import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {allowStagingAuthMutation} from '../src/stagingAuthGuard.js';
export function vercelBuildArgs(env){
 const qa=env.VERCEL_ENV==='preview'&&env.VERCEL_GIT_COMMIT_REF==='feature/system-administration-center-preview-20261028'&&allowStagingAuthMutation({mode:'staging',enabled:env.VITE_ENABLE_AUTH_MUTATIONS,url:env.VITE_SUPABASE_URL,publishableKey:env.VITE_SUPABASE_PUBLISHABLE_KEY});
 return qa?['run','build','--','--mode','staging']:['run','build'];
}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const result=spawnSync('npm',vercelBuildArgs(process.env),{stdio:'inherit',env:process.env,shell:false});
 process.exit(result.status??1);
}
