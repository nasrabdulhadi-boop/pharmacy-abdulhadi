import {PGlite} from '@electric-sql/pglite';
import {restoreQaArchive} from './qaRestoreArchive.js';

self.onmessage=async ({data:{file,phrase}})=>{
 try{
  const bytes=await file.arrayBuffer();
  const archive=JSON.parse(new TextDecoder().decode(bytes));
  const recovered=await restoreQaArchive(archive,phrase,{
   createDatabase:()=>new PGlite(),
   saveDatabase:true,
   reopenDatabase:database=>new PGlite({loadDataDir:database}),
  });
  const digest=await crypto.subtle.digest('SHA-256',bytes);
  const sourceArchiveSha256=Array.from(new Uint8Array(digest),byte=>byte.toString(16).padStart(2,'0')).join('');
  self.postMessage({...recovered,sourceArchiveSha256});
 }catch(error){
  const code=['backup_decryption_failed','archive_requires_exact_decimal_encoding'].includes(error.message)
   ?error.message:'restore_failed';
  self.postMessage({code});
 }
};
