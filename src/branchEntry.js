import {branchIdFromSearch} from './branchWorkspace.js';
if (/^pharmacy-abdulhadi-[a-z0-9]{9}-naser9\.vercel\.app$/.test(location.hostname) && import.meta.env.VITE_SUPABASE_URL==='https://eewjjzgwoaxhojnjvzgq.supabase.co') {
 location.replace('https://pharmacy-abdulhadi.vercel.app'+location.pathname+location.search+location.hash);
} else if (branchIdFromSearch(window.location.search)&&!new URLSearchParams(location.search).has('workspace')) {
 import('./BranchEntry.jsx');
} else {
 import('./main.jsx');
}
