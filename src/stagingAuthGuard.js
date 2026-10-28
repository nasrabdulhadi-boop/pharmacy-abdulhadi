// This guard is deliberately disabled unless all conditions match the isolated QA project.
// It is not an authorization boundary; Supabase Auth and server-side RLS remain mandatory.
export const ISOLATED_QA_PROJECT_URL='https://vpjxdsprfcpqclnhbeoh.supabase.co';
export function allowStagingAuthMutation({mode,url,publishableKey,enabled}={}){
 return mode==='staging' && enabled==='true' && url===ISOLATED_QA_PROJECT_URL && typeof publishableKey==='string' && publishableKey.length>0;
}
