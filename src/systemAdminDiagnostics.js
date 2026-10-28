import {sanitizeTechnicalDiagnostic} from './systemAccessPolicy.js';
const COMPONENTS=Object.freeze(['authentication','api','database','deployment']);
export function makeTechnicalHealthSnapshot({observedAt=new Date().toISOString(),components={}}={}){
 return Object.freeze(COMPONENTS.map(component=>sanitizeTechnicalDiagnostic({component,status:components[component],observedAt})));
}
export function summarizeTechnicalHealth(snapshot){
 const entries=Array.isArray(snapshot)?snapshot:[];
 const statuses=entries.map(entry=>sanitizeTechnicalDiagnostic(entry).status);
 return statuses.includes('unavailable')?'unavailable':statuses.includes('degraded')?'degraded':statuses.length===4&&statuses.every(x=>x==='healthy')?'healthy':'unknown';
}
