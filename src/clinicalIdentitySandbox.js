// A local-file identity simulation, never a clinical interaction checker.
// File metadata is self-declared. No source, reviewer or clinical approval is verified here.
import {parseIngredientField} from './clinicalPreviewEngine.js';
import {createBilingualAliasIndex,resolveBilingualIngredient} from './clinicalBilingualMapping.js';
export const MAX_IDENTITY_PREVIEW_PRODUCTS=50;

export function previewLocalBilingualIdentity(products,aliases){
 const rows=Array.isArray(products)?products:[];
 if(rows.length>MAX_IDENTITY_PREVIEW_PRODUCTS)return {
  mode:'local_identity_simulation',matched:[],identityOverlaps:[],aliasConflicts:[],invalidAliasCount:0,
  unresolved:[{productId:null,reason:'identity_selection_limit'}],sourceVerification:'not_performed',
  clinicalRulesActivated:0,clinicallyApproved:false,safeToCombine:null,productionEnabled:false
 };
 const {index,conflicts,invalid}=createBilingualAliasIndex(aliases);
 const counts=new Map();
 for(const p of rows)if(p?.id!=null)counts.set(String(p.id),(counts.get(String(p.id))||0)+1);
 const matched=[],unresolved=[],identityOverlaps=[];
 for(const p of rows){
  if(!p||p.id==null||!String(p.id).trim()){unresolved.push({productId:null,reason:'missing_product_id'});continue}
  if(counts.get(String(p.id))>1){unresolved.push({productId:p.id,reason:'duplicate_product_id'});continue}
  const parsed=parseIngredientField(p.active_ingredient);
  if(parsed.status!=='parsed'){unresolved.push({productId:p.id,name:p.name,reason:'composition_requires_review'});continue}
  const identities=parsed.components.map(label=>resolveBilingualIngredient(label,index));
  if(identities.some(x=>x.status!=='verified_alias')){
   unresolved.push({productId:p.id,name:p.name,reason:'alias_missing_or_conflicting'});continue;
  }
  const ids=new Set(identities.map(x=>x.canonicalIngredientId));
  if(ids.size!==parsed.components.length){unresolved.push({productId:p.id,name:p.name,reason:'duplicate_composition_identity'});continue}
  matched.push({productId:p.id,name:p.name||'',ingredientIds:[...ids]});
 }
 for(let i=0;i<matched.length;i++)for(let j=i+1;j<matched.length;j++){
  const shared=matched[i].ingredientIds.filter(id=>matched[j].ingredientIds.includes(id));
  if(shared.length)identityOverlaps.push({a:matched[i],b:matched[j],sharedIngredientIds:shared});
 }
 return {mode:'local_identity_simulation',matched,unresolved,identityOverlaps,
  aliasConflicts:conflicts,invalidAliasCount:invalid.length,
  sourceVerification:'not_performed',clinicalRulesActivated:0,clinicallyApproved:false,
  safeToCombine:null,productionEnabled:false};
}
