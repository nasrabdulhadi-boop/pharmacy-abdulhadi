// Isolated clinical rule validation prototype. No rules are shipped as clinically approved.
// Never use product free-text ingredients to assert a clinical interaction.
import {nonemptyText,validClinicalId,hasReviewMetadata,hasSourceLocator} from './clinicalProvenance.js';
const severities=new Set(['contraindicated','major','moderate','minor']);
export function validateClinicalRule(rule){
 const problems=[];
 if(!rule||typeof rule!=='object')return {valid:false,problems:['missing rule']};
 if(!validClinicalId(rule.id)||!validClinicalId(rule.ingredient_a_id)||!validClinicalId(rule.ingredient_b_id)||rule.ingredient_a_id===rule.ingredient_b_id)problems.push('invalid ingredient pair');
 if(!severities.has(rule.severity))problems.push('invalid severity');
 if(!nonemptyText(rule.mechanism)||!nonemptyText(rule.recommendation))problems.push('missing clinical explanation');
 if(!nonemptyText(rule.reference_id)||!nonemptyText(rule.source_version)||!hasReviewMetadata(rule))problems.push('missing source or review metadata');
 if(!hasSourceLocator(rule))problems.push('missing verifiable source locator');
 if(rule.status!=='approved')problems.push('not approved');
 if(rule.active!==true)problems.push('inactive');
 return {valid:problems.length===0,problems};
}
export function verifyClinicalSourceLicense(rule){
 return Boolean(rule&&rule.license_status==='verified'&&nonemptyText(rule.license_reference));
}
// Release readiness is stricter than synthetic research-only screening.
export function clinicalRuleReleaseReady(rule){
 return validateClinicalRule(rule).valid&&verifyClinicalSourceLicense(rule);
}
// One consistent rule registry for both research engines. Conflicts never pick a winner.
export function prepareClinicalRules(rules){
 const eligible=(Array.isArray(rules)?rules:[]).filter(clinicalRuleReleaseReady);
 const idCounts=new Map();
 for(const rule of eligible)idCounts.set(rule.id,(idCounts.get(rule.id)||0)+1);
 const duplicateRuleIds=[...idCounts].filter(([,count])=>count>1).map(([id])=>id);
 const byPair=new Map();
 for(const rule of eligible){
  if(idCounts.get(rule.id)!==1)continue;
  const pair=JSON.stringify([rule.ingredient_a_id,rule.ingredient_b_id].sort());
  if(!byPair.has(pair))byPair.set(pair,[]);
  byPair.get(pair).push(rule);
 }
 const usable=[],ruleConflicts=[];
 for(const [pair,group] of byPair){
  const signatures=new Set(group.map(rule=>JSON.stringify([rule.severity,rule.mechanism,rule.recommendation])));
  if(signatures.size>1)ruleConflicts.push({pair,ruleIds:group.map(rule=>rule.id)});
  else usable.push(group[0]);
 }
 return {rules:usable,duplicateRuleIds,ruleConflicts};
}
export function validateIngredientMapping(mapping){
 const problems=[];
 if(!mapping||typeof mapping!=='object')return {valid:false,problems:['missing mapping']};
 if(mapping.product_id==null||!String(mapping.product_id).trim()||!validClinicalId(mapping.ingredient_id))problems.push('missing product or ingredient');
 if(mapping.status!=='approved')problems.push('mapping not approved');
 if(mapping.composition_verified!==true)problems.push('composition not verified');
 if(!nonemptyText(mapping.source_reference_id)||!nonemptyText(mapping.source_version))problems.push('missing source evidence');
 if(!hasSourceLocator(mapping))problems.push('missing verifiable source locator');
 if(!hasReviewMetadata(mapping))problems.push('missing reviewer metadata');
 return {valid:problems.length===0,problems};
}
export function evaluateReviewedClinicalRules(products,mappings,rules){
 const productRows=(Array.isArray(products)?products:[]).filter(p=>p&&p.id!=null&&String(p.id).trim());
 const productIds=[...new Set(productRows.map(p=>String(p.id)))];
 const duplicateProductIds=productIds.filter(id=>productRows.filter(p=>String(p.id)===id).length>1);
 const byProduct=new Map();
 const unmapped=[];
 for(const id of productIds){
  const m=(Array.isArray(mappings)?mappings:[]).filter(x=>validateIngredientMapping(x).valid&&String(x.product_id)===id);
  if(!m.length||duplicateProductIds.includes(id)||new Set(m.map(row=>row.ingredient_id)).size!==m.length){unmapped.push(id);continue}
  byProduct.set(id,[...new Set(m.map(x=>String(x.ingredient_id)))]);
 }
 // Research screening must not treat unlicensed evidence as an approved clinical finding.
 const {rules:usableRules,duplicateRuleIds,ruleConflicts}=prepareClinicalRules(rules);
 const findings=[];
 for(let i=0;i<productIds.length;i++)for(let j=i+1;j<productIds.length;j++){
  const a=productIds[i],b=productIds[j];
  if(!byProduct.has(a)||!byProduct.has(b))continue;
  for(const rule of usableRules){
   const left=byProduct.get(a),right=byProduct.get(b);
   if((left.includes(String(rule.ingredient_a_id))&&right.includes(String(rule.ingredient_b_id)))||
      (left.includes(String(rule.ingredient_b_id))&&right.includes(String(rule.ingredient_a_id))))
    findings.push({product_a_id:a,product_b_id:b,rule_id:rule.id,severity:rule.severity,reference_id:rule.reference_id});
  }
 }
 return {status:unmapped.length||duplicateRuleIds.length||ruleConflicts.length?'incomplete':usableRules.length?'limited_approved_rule_screening':'no_approved_rules',findings,unmappedProductIds:unmapped,approvedRuleCount:usableRules.length,duplicateProductIds,duplicateRuleIds,ruleConflicts,coverage:'not_exhaustive',safeToCombine:null,productionEnabled:false};
}

export function clinicalReviewReadiness(mappings,rules){
 const mapRows=Array.isArray(mappings)?mappings:[];
 const ruleRows=Array.isArray(rules)?rules:[];
 const mappingProblems=mapRows.map((row,index)=>({index,problems:validateIngredientMapping(row).problems})).filter(row=>row.problems.length);
 const ruleProblems=ruleRows.map((row,index)=>({index,problems:[...validateClinicalRule(row).problems,...(verifyClinicalSourceLicense(row)?[]:['missing verified license metadata'])]})).filter(row=>row.problems.length);
 return {
  mappingsTotal:mapRows.length,
  mappingsApproved:mapRows.length-mappingProblems.length,
  rulesTotal:ruleRows.length,
  rulesApproved:ruleRows.length-ruleProblems.length,
  mappingProblems,ruleProblems,
  evidenceRecordsValid:mapRows.length>0&&ruleRows.length>0&&!mappingProblems.length&&!ruleProblems.length,
  clinicallyReady:false // Rule-list validity does not establish clinical coverage, licensing or release approval.
 };
}
