// Preview-only deterministic ingredient parsing. Not a clinical interaction engine.
// Never infer synonyms, salts, equivalence, dose or safety from text matching.
export function normalizeIngredientName(value){
 return String(value||'').normalize('NFKC')
  .replace(/([a-z])([A-Z])/g,'$1 $2')
  .replace(/[أإآ]/g,'ا').replace(/[\u064B-\u065F\u0670]/g,'')
  .replace(/[_\-]+/g,' ').replace(/\s+/g,' ').trim().toLowerCase();
}
export function parseIngredientField(value){
 const raw=String(value||'').trim();
 if(!raw)return {components:[],status:'missing',reason:'المادة الفعالة غير مسجلة'};
 // Only an explicit + is treated as a combination separator. Slashes and commas
 // can be part of dose expressions, so flag them for manual review.
 if(/[\/،,;؛]/.test(raw))return {components:[],status:'review',reason:'صيغة تركيب غير قياسية؛ تحتاج مراجعة بشرية'};
 const parts=raw.split(/\s*\+\s*/);
 if(parts.some(x=>!x.trim()))return {components:[],status:'review',reason:'تركيب غير مكتمل'};
 const components=[...new Set(parts.map(normalizeIngredientName))];
 if(components.some(x=>!x||/\d/.test(x)))return {components:[],status:'review',reason:'المادة الفعالة تحتوي تركيزاً أو رقماً؛ يلزم التحقق'};
 return {components,status:'parsed',reason:parts.length>1?'تركيب متعدد المواد':'اسم مادة مفردة'};
}
export function screenExactIngredientOverlap(products){
 const parsed=products.map(p=>({...p,parsed:parseIngredientField(p.active_ingredient)}));
 const overlaps=[];
 for(let i=0;i<parsed.length;i++)for(let j=i+1;j<parsed.length;j++){
  const a=parsed[i],b=parsed[j];
  if(a.parsed.status!=='parsed'||b.parsed.status!=='parsed')continue;
  const shared=a.parsed.components.filter(x=>b.parsed.components.includes(x));
  if(shared.length)overlaps.push({a:{id:a.id,name:a.name},b:{id:b.id,name:b.name},shared});
 }
 return {overlaps,unresolved:parsed.filter(p=>p.parsed.status!=='parsed').map(p=>({id:p.id,name:p.name,reason:p.parsed.reason})),reviewed:parsed.length};
}

export function auditClinicalCatalog(products){
 const rows=(Array.isArray(products)?products:[]).map(p=>({
  id:p.id,name:p.name||'',ingredient:p.active_ingredient||'',strength:p.strength||'',form:p.dosage_form||'',
  parsed:parseIngredientField(p.active_ingredient)
 }));
 const counts={total:rows.length,missingIngredient:0,manualReview:0,missingStrength:0,missingForm:0,parseable:0};
 for(const r of rows){
  if(r.parsed.status==='missing')counts.missingIngredient++;
  if(r.parsed.status==='review')counts.manualReview++;
  if(r.parsed.status==='parsed')counts.parseable++;
  if(!String(r.strength).trim())counts.missingStrength++;
  if(!String(r.form).trim())counts.missingForm++;
 }
 return {counts,issues:rows.filter(r=>r.parsed.status!=='parsed'||!String(r.strength).trim()||!String(r.form).trim()).slice(0,60)};
}

export function buildIngredientReviewQueue(products){
 const grouped=new Map();
 for(const p of Array.isArray(products)?products:[]){
  const parsed=parseIngredientField(p.active_ingredient);
  if(parsed.status!=='parsed')continue;
  for(const component of parsed.components){
   const row=grouped.get(component)||{normalized:component,productCount:0,examples:[],variants:new Set()};
   row.productCount++;
   row.variants.add(String(p.active_ingredient||'').trim());
   if(row.examples.length<3)row.examples.push(String(p.name||''));
   grouped.set(component,row);
  }
 }
 return [...grouped.values()].map(row=>({...row,variants:[...row.variants].slice(0,5),status:'unverified'}))
  .sort((a,b)=>b.productCount-a.productCount||a.normalized.localeCompare(b.normalized));
}
export function clinicalAuditCsv(products){
 const rows=(Array.isArray(products)?products:[]).map(p=>{
  const parsed=parseIngredientField(p.active_ingredient);
  return [p.id||'',p.name||'',p.active_ingredient||'',parsed.components.join(' + '),parsed.status,parsed.reason,p.strength||'',p.dosage_form||''];
 });
 const csvCell=v=>'"'+String(v??'').replace(/"/g,'""').replace(/^[=+@\-\t\r]/,m=>"'"+m)+'"';
 return '\uFEFF'+[['product_id','product_name','raw_ingredient','normalized_components','status','reason','strength','dosage_form'],...rows].map(row=>row.map(csvCell).join(',')).join('\r\n');
}

export function prioritizeClinicalReview(products){
 const rows=[];
 for(const p of Array.isArray(products)?products:[]){
  const parsed=parseIngredientField(p.active_ingredient);
  const missingStrength=!String(p.strength||'').trim();
  const missingForm=!String(p.dosage_form||'').trim();
  const reasons=[];
  if(parsed.status==='missing')reasons.push('المادة الفعالة مفقودة');
  else if(parsed.status==='review')reasons.push('صيغة المادة الفعالة غامضة');
  if(missingStrength)reasons.push('التركيز مفقود');
  if(missingForm)reasons.push('الشكل الدوائي مفقود');
  if(!reasons.length)continue;
  const score=(parsed.status==='missing'?100:parsed.status==='review'?80:0)+(missingStrength?10:0)+(missingForm?5:0);
  rows.push({id:p.id,name:p.name||'',score,reasons});
 }
 return rows.sort((a,b)=>b.score-a.score||String(a.name).localeCompare(String(b.name))||String(a.id).localeCompare(String(b.id)));
}
