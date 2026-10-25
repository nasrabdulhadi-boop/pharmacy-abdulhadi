// Isolated clinical rule validation prototype. No rules are shipped as clinically approved.
// Never use product free-text ingredients to assert a clinical interaction.
const severities=new Set(['contraindicated','major','moderate','minor']);
export function validateClinicalRule(rule){
 const problems=[];
 if(!rule||typeof rule!=='object')return {valid:false,problems:['missing rule']};
 if(!rule.id||!rule.ingredient_a_id||!rule.ingredient_b_id||rule.ingredient_a_id===rule.ingredient_b_id)problems.push('invalid ingredient pair');
 if(!severities.has(rule.severity))problems.push('invalid severity');
 if(!String(rule.mechanism||'').trim()||!String(rule.recommendation||'').trim())problems.push('missing clinical explanation');
 if(!rule.reference_id||!rule.source_version||!rule.reviewed_at||!rule.reviewer_id)problems.push('missing source or review metadata');
 if(!rule.source_url&&!rule.source_document_id)problems.push('missing verifiable source locator');
 if(rule.status!=='approved')problems.push('not approved');
 if(rule.active!==true)problems.push('inactive');
 return {valid:problems.length===0,problems};
}
export function verifyClinicalSourceLicense(rule){
 return Boolean(rule&&rule.license_status==='verified'&&String(rule.license_reference||'').trim());
}
// Release readiness is stricter than synthetic research-only screening.
export function clinicalRuleReleaseReady(rule){
 return validateClinicalRule(rule).valid&&verifyClinicalSourceLicense(rule);
}
export function validateIngredientMapping(mapping){
 const problems=[];
 if(!mapping||typeof mapping!=='object')return {valid:false,problems:['missing mapping']};
 if(!mapping.product_id||!mapping.ingredient_id)problems.push('missing product or ingredient');
 if(mapping.status!=='approved')problems.push('mapping not approved');
 if(mapping.composition_verified!==true)problems.push('composition not verified');
 if(!mapping.source_reference_id||!mapping.source_version)problems.push('missing source evidence');
 if(!mapping.source_url&&!mapping.source_document_id)problems.push('missing verifiable source locator');
 if(!mapping.reviewer_id||!mapping.reviewed_at)problems.push('missing reviewer metadata');
 return {valid:problems.length===0,problems};
}
export function evaluateReviewedClinicalRules(products,mappings,rules){
 const productIds=[...new Set((products||[]).filter(p=>p&&p.id!=null&&String(p.id).trim()).map(p=>String(p.id)))];
 const byProduct=new Map();
 const unmapped=[];
 for(const id of productIds){
  const m=(mappings||[]).filter(x=>String(x.product_id)===id&&validateIngredientMapping(x).valid);
  if(!m.length){unmapped.push(id);continue}
  byProduct.set(id,[...new Set(m.map(x=>String(x.ingredient_id)))]);
 }
 const usableRules=(rules||[]).filter(x=>validateClinicalRule(x).valid);
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
 return {status:unmapped.length?'incomplete':usableRules.length?'limited_approved_rule_screening':'no_approved_rules',findings,unmappedProductIds:unmapped,approvedRuleCount:usableRules.length};
}

export function clinicalReviewReadiness(mappings,rules){
 const mapRows=Array.isArray(mappings)?mappings:[];
 const ruleRows=Array.isArray(rules)?rules:[];
 const mappingProblems=mapRows.map((row,index)=>({index,problems:validateIngredientMapping(row).problems})).filter(row=>row.problems.length);
 const ruleProblems=ruleRows.map((row,index)=>({index,problems:validateClinicalRule(row).problems})).filter(row=>row.problems.length);
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
