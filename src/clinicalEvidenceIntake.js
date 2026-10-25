// Research-only source intake. No clinical rule activation and no database writes.
const evidenceKinds=new Set(['label','curated','research','signal']);
export function validateEvidenceCandidate(row){
 const problems=[];
 if(!row||typeof row!=='object')return {valid:false,problems:['missing candidate']};
 if(!String(row.source_id||'').trim())problems.push('missing source id');
 if(!String(row.source_version||'').trim())problems.push('missing source version');
 if(!String(row.source_record_id||'').trim())problems.push('missing source record id');
 if(!String(row.ingredient_a||'').trim()||!String(row.ingredient_b||'').trim())problems.push('missing ingredient pair');
 if(!evidenceKinds.has(row.evidence_kind))problems.push('invalid evidence kind');
 if(!String(row.original_text||'').trim())problems.push('missing original evidence text');
 if(!String(row.source_url||'').trim())problems.push('missing source locator');
 if(!['verified','restricted','unknown'].includes(row.license_status))problems.push('missing license assessment');
 return {valid:problems.length===0,problems};
}
export function inspectEvidenceCandidates(rows){
 const list=Array.isArray(rows)?rows:[];
 const seen=new Map(),duplicates=[],conflicts=[],invalid=[];
 const accepted=[];
 for(let i=0;i<list.length;i++){
  const row=list[i],check=validateEvidenceCandidate(row);
  if(!check.valid){invalid.push({index:i,problems:check.problems});continue}
  const pair=[String(row.ingredient_a).trim().toLowerCase(),String(row.ingredient_b).trim().toLowerCase()].sort().join('::');
  const key=[row.source_id,row.source_version,row.source_record_id].join('::');
  if(seen.has(key)){
   const prior=seen.get(key);
   duplicates.push({firstIndex:prior.index,index:i,key});
   if(prior.pair!==pair||prior.originalText!==row.original_text)conflicts.push({firstIndex:prior.index,index:i,key});
   continue;
  }
  seen.set(key,{index:i,pair,originalText:row.original_text});
  accepted.push({...row,review_status:'pending',clinical_approved:false});
 }
 return {total:list.length,accepted,invalid,duplicates,conflicts,clinicalRulesActivated:0};
}
