// Experimental bilingual identity and reviewed-rule screening.
// All inputs must be explicitly reviewed; incomplete composition fails closed.
import {createBilingualAliasIndex,resolveBilingualIngredient} from './clinicalBilingualMapping.js';
import {validateClinicalRule,validateIngredientMapping} from './clinicalRuleEngine.js';
export function screenBilingualReviewedPairs(products,aliases,mappings,rules){
 const aliasIndex=createBilingualAliasIndex(aliases);
 const rows=Array.isArray(products)?products:[];
 const mappingRows=Array.isArray(mappings)?mappings:[];
 const validRules=(Array.isArray(rules)?rules:[]).filter(rule=>validateClinicalRule(rule).valid);
 const unresolved=[],ingredientsByProduct=new Map();
 for(const product of rows){
  if(!product||product.id==null){unresolved.push({productId:null,reason:'missing_product_id'});continue}
  const id=String(product.id);
  // The manifest certifies the entire formulation, not merely one ingredient.
  const manifest=product.verified_composition;
  // Never infer completeness from a single reviewed ingredient mapping.
  if(!manifest||manifest.status!=='approved'||!manifest.reviewer_id||!manifest.reviewed_at||!manifest.source_reference_id||!manifest.source_version||(!manifest.source_url&&!manifest.source_document_id)||!Array.isArray(manifest.ingredient_ids)||!manifest.ingredient_ids.length){
   unresolved.push({productId:id,reason:'composition_not_fully_verified'});continue;
  }
  const expected=new Set(manifest.ingredient_ids.map(String));
  if(expected.size!==manifest.ingredient_ids.length){unresolved.push({productId:id,reason:'duplicate_manifest_ingredients'});continue}
  const validMappings=mappingRows.filter(m=>String(m.product_id)===id&&validateIngredientMapping(m).valid);
  const mapped=new Set(validMappings.map(m=>String(m.ingredient_id)));
  if(mapped.size!==expected.size||[...expected].some(x=>!mapped.has(x))){
   unresolved.push({productId:id,reason:'incomplete_ingredient_mappings'});continue;
  }
  // If an ingredient label is provided, it must resolve to a reviewed alias.
  if(expected.size===1){
   if(!String(product.active_ingredient||'').trim()){
    unresolved.push({productId:id,reason:'ingredient_label_missing'});continue;
   }
   const resolved=resolveBilingualIngredient(product.active_ingredient,aliasIndex.index);
   if(resolved.canonicalIngredientId!==[...expected][0]){
    unresolved.push({productId:id,reason:'ingredient_alias_unverified_or_conflicting'});continue;
   }
  }
  if(expected.size>1){
   // A multi-ingredient product must have every individual label explicitly reviewed.
   const reviewedLabels=manifest.reviewed_ingredient_aliases;
   if(!Array.isArray(reviewedLabels)||reviewedLabels.length!==expected.size){
    unresolved.push({productId:id,reason:'combination_aliases_not_fully_verified'});continue;
   }
   const resolved=new Set();
   for(const label of reviewedLabels){
    const match=resolveBilingualIngredient(label,aliasIndex.index);
    if(match.canonicalIngredientId)resolved.add(match.canonicalIngredientId);
   }
   if(resolved.size!==expected.size||[...expected].some(x=>!resolved.has(x))){
    unresolved.push({productId:id,reason:'combination_aliases_unverified_or_conflicting'});continue;
   }
  }
  ingredientsByProduct.set(id,expected);
 }
 const findings=[];
 const ids=[...ingredientsByProduct.keys()];
 for(let i=0;i<ids.length;i++)for(let j=i+1;j<ids.length;j++){
  for(const rule of validRules){
   const a=ingredientsByProduct.get(ids[i]),b=ingredientsByProduct.get(ids[j]);
   if((a.has(String(rule.ingredient_a_id))&&b.has(String(rule.ingredient_b_id)))||
      (a.has(String(rule.ingredient_b_id))&&b.has(String(rule.ingredient_a_id)))){
    findings.push({product_a_id:ids[i],product_b_id:ids[j],rule_id:rule.id,severity:rule.severity,reference_id:rule.reference_id});
   }
  }
 }
 return {status:unresolved.length?'incomplete':validRules.length?'limited_approved_rule_screening':'no_approved_rules',
  findings,unresolved,approvedRuleCount:validRules.length,aliasConflicts:aliasIndex.conflicts,
  coverage:'not_exhaustive',safeToCombine:null,productionEnabled:false};
}
