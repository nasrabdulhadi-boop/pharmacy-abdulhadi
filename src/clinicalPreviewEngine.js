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
