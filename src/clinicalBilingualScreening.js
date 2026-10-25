// Experimental bilingual identity and reviewed-rule screening.
// All inputs must be explicitly reviewed; incomplete composition fails closed.
import {createBilingualAliasIndex,resolveBilingualIngredient} from './clinicalBilingualMapping.js';
import {clinicalRuleReleaseReady,validateIngredientMapping} from './clinicalRuleEngine.js';
import {nonemptyText,validClinicalId,hasReviewMetadata,hasSourceLocator} from './clinicalProvenance.js';
export function screenBilingualReviewedPairs(products,aliases,mappings,rules){
 const aliasIndex=createBilingualAliasIndex(aliases);
 const rows=Array.isArray(products)?products:[];
 const mappingRows=Array.isArray(mappings)?mappings:[];
 const validatedRules=(Array.isArray(rules)?rules:[]).filter(rule=>clinicalRuleReleaseReady(rule));
 // Conflicting reviewed rules for the same unordered ingredient pair are quarantined.
 const byPair=new Map();
 for(const rule of validatedRules){
  const pair=JSON.stringify([String(rule.ingredient_a_id),String(rule.ingredient_b_id)].sort());
  if(!byPair.has(pair))byPair.set(pair,[]);
  byPair.get(pair).push(rule);
 }
 const ruleConflicts=[];
 const validRules=[];
 for(const [pair,group] of byPair){
  const signatures=new Set(group.map(r=>[r.severity,r.mechanism,r.recommendation].join('::')));
  if(signatures.size>1){ruleConflicts.push({pair,ruleIds:group.map(r=>r.id)});continue}
  validRules.push(group[0]);
 }
 const unresolved=[],ingredientsByProduct=new Map();
 const idCounts=new Map();
 for(const product of rows){
  if(product?.id!=null){const key=String(product.id);idCounts.set(key,(idCounts.get(key)||0)+1)}
 }
 for(const product of rows){
  if(!product||product.id==null){unresolved.push({productId:null,reason:'missing_product_id'});continue}
  const id=String(product.id);
  if(idCounts.get(id)>1){unresolved.push({productId:id,reason:'duplicate_product_id'});continue}
  // The manifest certifies the entire formulation, not merely one ingredient.
  const manifest=product.verified_composition;
  // Never infer completeness from a single reviewed ingredient mapping.
  if(!manifest||manifest.status!=='approved'||!hasReviewMetadata(manifest)||!nonemptyText(manifest.source_reference_id)||!nonemptyText(manifest.source_version)||!hasSourceLocator(manifest)||!Array.isArray(manifest.ingredient_ids)||!manifest.ingredient_ids.length||manifest.ingredient_ids.some(id=>!validClinicalId(id))){
   unresolved.push({productId:id,reason:'composition_not_fully_verified'});continue;
  }
  const expected=new Set(manifest.ingredient_ids.map(String));
  if(expected.size!==manifest.ingredient_ids.length){unresolved.push({productId:id,reason:'duplicate_manifest_ingredients'});continue}
  const validMappings=mappingRows.filter(m=>validateIngredientMapping(m).valid&&String(m.product_id)===id);
  const mapped=new Set(validMappings.map(m=>String(m.ingredient_id)));
  // Extra reviewed mappings are not evidence that the composition manifest is complete.
  // Even when the extra row duplicates an existing ingredient ID, quarantine it for review.
  if(validMappings.length!==expected.size){
   unresolved.push({productId:id,reason:'unexpected_or_duplicate_ingredient_mappings'});continue;
  }
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
 return {status:unresolved.length||ruleConflicts.length?'incomplete':validRules.length?'limited_approved_rule_screening':'no_approved_rules',
  findings,unresolved,approvedRuleCount:validRules.length,aliasConflicts:aliasIndex.conflicts,ruleConflicts,
  coverage:'not_exhaustive',safeToCombine:null,productionEnabled:false};
}
