// Local, in-memory PostgreSQL rehearsal only. Never accepts a remote database URL.
// Auth/Storage platform services are NOT restored; minimal Auth metadata supports FK checks.
import fs from 'node:fs';
import {pathToFileURL} from 'node:url';
import {PGlite} from '@electric-sql/pglite';
import {restoreQaArchive} from '../../src/qaRestoreArchive.js';
export function rehearseQaArchive(archive,phrase){
 return restoreQaArchive(archive,phrase,{createDatabase:()=>new PGlite()});
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const [archivePath,phrasePath,reportPath]=process.argv.slice(2);
 if(!archivePath||!phrasePath||!reportPath)throw Error('Usage: archive.json passphrase-file safe-report.json');
 try{const result=await rehearseQaArchive(JSON.parse(fs.readFileSync(archivePath,'utf8')),fs.readFileSync(phrasePath,'utf8'));fs.writeFileSync(reportPath,JSON.stringify(result,null,2),{mode:0o600});console.log(JSON.stringify(result));}
 catch(e){fs.writeFileSync(reportPath,JSON.stringify(e.safeSummary||{failed:true},null,2),{mode:0o600});console.error(JSON.stringify(e.safeSummary||{failed:true}));process.exitCode=1;}
}
