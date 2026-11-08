import {createClient} from 'npm:@supabase/supabase-js@2.118.0';
import {handleStaffAccount} from './handler.js';
Deno.serve(req=>handleStaffAccount(req,{
 projectUrl:Deno.env.get('SUPABASE_URL'),
 publishable:JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')||'{}').default||Deno.env.get('SUPABASE_ANON_KEY'),
 secret:JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),createClient
}));
