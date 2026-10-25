// Explicit, pharmacist-reviewed Arabic/English aliases only.
// No automatic transliteration or inferred chemical equivalence.
import {normalizeIngredientName} from './clinicalPreviewEngine.js';
export function validateBilingualAlias(row){
 const problems=[];
 if(!row||typeof row!=='object')return {valid:false,problems:['missing alias']};
 if(!String(row.canonical_ingredient_id||'').trim())problems.push('missing canonical ingredient');
 if(!['ar','en'].includes(row.language))problems.push('unsupported language');
 if(!normalizeIngredientName(row.alias))problems.push('missing alias');
 if(row.status!=='approved')problems.push('alias not approved');
 if(!row.reviewer_id||!row.reviewed_at)problems.push('missing pharmacist review');
 if(!row.source_reference_id||!row.source_version||(!row.source_url&&!row.source_document_id))problems.push('missing source traceability');
 return {valid:problems.length===0,problems};
}
export function createBilingualAliasIndex(aliases){
 const index=new Map(),conflicts=[],invalid=[];
 for(const [position,row] of (Array.isArray(aliases)?aliases:[]).entries()){
  const result=validateBilingualAlias(row);
  if(!result.valid){invalid.push({position,problems:result.problems});continue}
  const key=normalizeIngredientName(row.alias);
  const canonical=String(row.canonical_ingredient_id);
  if(index.has(key)&&index.get(key)!==canonical){
   conflicts.push({alias:row.alias,first:index.get(key),second:canonical});
   index.set(key,null); // Ambiguous aliases fail closed permanently, regardless of later rows.
  }else if(!index.has(key))index.set(key,canonical);
 }
 return {index,conflicts,invalid};
}
export function resolveBilingualIngredient(value,aliasIndex){
 const key=normalizeIngredientName(value);
 if(!key)return {status:'missing',canonicalIngredientId:null};
 if(!aliasIndex||!aliasIndex.has(key))return {status:'unverified',canonicalIngredientId:null};
 const id=aliasIndex.get(key);
 return id?{status:'verified_alias',canonicalIngredientId:id}:{status:'ambiguous',canonicalIngredientId:null};
}
export function matchBilingualProducts(products,approvedMappings,aliases){
 const aliasData=createBilingualAliasIndex(aliases);
 const byProduct=new Map();
 for(const row of (Array.isArray(approvedMappings)?approvedMappings:[])){
  if(row.status!=='approved'||row.composition_verified!==true||!row.reviewer_id||!row.reviewed_at||!row.source_reference_id||!row.source_version||(!row.source_url&&!row.source_document_id))continue;
  const id=String(row.product_id);
  if(!byProduct.has(id))byProduct.set(id,new Set());
  byProduct.get(id).add(String(row.ingredient_id));
 }
 const results=(Array.isArray(products)?products:[]).map(product=>{
  const mappings=byProduct.get(String(product.id));
  const alias=resolveBilingualIngredient(product.active_ingredient,aliasData.index);
  return {productId:product.id,languageIndependentIngredientId:alias.canonicalIngredientId,
   verifiedMappingIds:mappings?[...mappings]:[],aliasStatus:alias.status,
   eligibleForClinicalScreening:false}; // Composition completeness not yet established.
 });
 return {...aliasData,results};
}
