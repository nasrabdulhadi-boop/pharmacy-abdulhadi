// Research-only source intake. No clinical rule activation and no database writes.
import {nonemptyText,validSourceUrl} from './clinicalProvenance.js';
const evidenceKinds=new Set(['label','curated','research','signal']);
export function validateEvidenceCandidate(row){
 const problems=[];
 if(!row||typeof row!=='object')return {valid:false,problems:['missing candidate']};
 if(!nonemptyText(row.source_id))problems.push('missing source id');
 if(!nonemptyText(row.source_version))problems.push('missing source version');
 if(!nonemptyText(row.source_record_id))problems.push('missing source record id');
 if(!nonemptyText(row.ingredient_a)||!nonemptyText(row.ingredient_b))problems.push('missing ingredient pair');
 if(!evidenceKinds.has(row.evidence_kind))problems.push('invalid evidence kind');
 if(!nonemptyText(row.original_text))problems.push('missing original evidence text');
 if(!validSourceUrl(row.source_url))problems.push('missing source locator');
 if(!['verified','restricted','unknown'].includes(row.license_status))problems.push('missing license assessment');
 return {valid:problems.length===0,problems};
}
export function inspectEvidenceCandidates(rows){
 const list=Array.isArray(rows)?rows:[];
 const seen=new Map(),duplicates=[],conflicts=[],invalid=[],quarantinedKeys=new Set();
 const accepted=[];
 for(let i=0;i<list.length;i++){
  const row=list[i],check=validateEvidenceCandidate(row);
  if(!check.valid){invalid.push({index:i,problems:check.problems});continue}
  const pair=JSON.stringify([row.ingredient_a.trim().toLowerCase(),row.ingredient_b.trim().toLowerCase()].sort());
  const key=JSON.stringify([row.source_id.trim(),row.source_version.trim(),row.source_record_id.trim()]);
  if(seen.has(key)){
   const prior=seen.get(key);
   duplicates.push({firstIndex:prior.index,index:i,key});
   if(prior.pair!==pair||prior.originalText!==row.original_text){conflicts.push({firstIndex:prior.index,index:i,key});quarantinedKeys.add(key)}
   continue;
  }
  seen.set(key,{index:i,pair,originalText:row.original_text});
  accepted.push({key,row:{...row,review_status:'pending',clinical_approved:false}});
 }
 return {total:list.length,accepted:accepted.filter(x=>!quarantinedKeys.has(x.key)).map(x=>x.row),invalid,duplicates,conflicts,quarantinedRecordCount:quarantinedKeys.size,clinicalRulesActivated:0};
}
