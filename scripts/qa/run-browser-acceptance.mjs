import {preview} from 'vite';
// Keep preview and browser in the same process lifetime/network environment.
// Browser acceptance independently refuses every non-QA remote hostname.
const server=await preview({preview:{host:'127.0.0.1',port:4173,strictPort:true}});
try{await import('./browser-acceptance.mjs');}
finally{await new Promise(resolve=>server.httpServer.close(resolve));}
