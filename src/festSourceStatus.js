import {createHash} from 'node:crypto';
import manifest from './festManifest.json' with {type:'json'};
// No input URL, patient data, database access, or credentials. Full ZIP digest, not just HTTP timestamps.
export async function inspectFestSource({fetcher=fetch,now=()=>new Date(),signal=AbortSignal.timeout(45000)}={}){
 const response=await fetcher(manifest.sourceUrl,{signal,redirect:'error',cache:'no-store',headers:{'User-Agent':'Pharmacy-Clinical-Preview/FEST-reference-check'}});
 if(!response.ok||!response.body)throw new Error('fest_source_unavailable');
 const hash=createHash('sha256');let size=0;
 for await(const chunk of response.body){size+=chunk.byteLength;if(size>40_000_000)throw new Error('fest_source_too_large');hash.update(chunk)}
 if(!size)throw new Error('fest_source_empty');
 return {state:hash.digest('hex')===manifest.zipSha256?'current':'stale',snapshot:manifest.snapshot,checkedAt:now().toISOString(),basisDate:manifest.basisDate};
}
