import {PGlite} from '@electric-sql/pglite';
import {restoreQaArchive} from './qaRestoreArchive.js';

self.onmessage=async ({data:{file,phrase}})=>{
 try{
  const archive=JSON.parse(await file.text());
  const recovered=await restoreQaArchive(archive,phrase,{
   createDatabase:()=>new PGlite(),
   saveDatabase:true,
  });
  self.postMessage(recovered);
 }catch(error){
  const code=['backup_decryption_failed','archive_requires_exact_decimal_encoding'].includes(error.message)
   ?error.message:'restore_failed';
  self.postMessage({code});
 }
};
