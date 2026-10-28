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
 return {};
});
