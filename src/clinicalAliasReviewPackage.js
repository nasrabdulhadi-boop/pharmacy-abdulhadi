// Offline review package validator. Never grants clinical approval or writes to Supabase.
import {normalizeIngredientName} from './clinicalPreviewEngine.js';
import {validateBilingualAlias,createBilingualAliasIndex} from './clinicalBilingualMapping.js';
export function inspectBilingualReviewPackage(records,candidates){
 const rows=Array.isArray(records)?records:[];
 const known=new Set((Array.isArray(candidates)?candidates:[]).map(x=>normalizeIngredientName(x.alias)));
 const accepted=[],rejected=[],unrecognized=[];
 const seen=new Map(),conflictKeys=new Set(),conflicts=[];
 rows.forEach((row,index)=>{
  const check=validateBilingualAlias(row);
  const key=normalizeIngredientName(row?.alias);
  if(!check.valid){rejected.push({index,problems:check.problems});return}
  if(!known.has(key)){unrecognized.push({index,alias:row.alias});return}
  if(seen.has(key)){
   const previous=seen.get(key);
   if(previous!==String(row.canonical_ingredient_id)){
    conflictKeys.add(key);
    conflicts.push({alias:row.alias,first:previous,second:String(row.canonical_ingredient_id)});
   }else rejected.push({index,problems:['duplicate alias in review package']});
   return;
  }
  seen.set(key,String(row.canonical_ingredient_id));
  accepted.push(row);
 });
 const index=createBilingualAliasIndex(accepted);
 const ambiguous=new Set([...conflictKeys,...index.conflicts.map(x=>normalizeIngredientName(x.alias))]);
 return {accepted:accepted.filter(x=>!ambiguous.has(normalizeIngredientName(x.alias))),
  rejected,unrecognized,conflicts:[...conflicts,...index.conflicts],
  eligibleForProduction:false,clinicalRulesActivated:0};
}
export function exportBilingualReviewTemplateCsv(candidates){
 const cols=['alias','language','canonical_ingredient_id','status','source_reference_id','source_version','source_url','source_document_id','reviewer_id','reviewed_at'];
 const quote=value=>'"'+String(value??'').replace(/"/g,'""').replace(/^[=+\-@\t\r]/,"'$&")+'"';
 const rows=(Array.isArray(candidates)?candidates:[]).map(x=>({
  alias:x.alias,language:x.language==='ar'||x.language==='en'?x.language:'',
  canonical_ingredient_id:'',status:'candidate',source_reference_id:'',source_version:'',
  source_url:'',source_document_id:'',reviewer_id:'',reviewed_at:''
 }));
 return '\uFEFF'+[cols.join(','),...rows.map(row=>cols.map(c=>quote(row[c])).join(','))].join('\r\n');
}
