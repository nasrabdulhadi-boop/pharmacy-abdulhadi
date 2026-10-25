// Research-only bilingual alias candidate discovery. Candidates are never approved.
import {normalizeIngredientName,parseIngredientField} from './clinicalPreviewEngine.js';
export function buildIngredientAliasCandidates(products){
 const groups=new Map();
 for(const product of Array.isArray(products)?products:[]){
  if(!product||product.id==null)continue;
  const raw=String(product.active_ingredient||'').trim();
  const parsed=parseIngredientField(raw);
  if(parsed.status!=='parsed')continue;
  for(const component of parsed.components){
   const key=normalizeIngredientName(component);
   if(!key)continue;
   const script=/[\u0621-\u064A]/.test(component)?(/[A-Za-z]/.test(component)?'mixed':'ar'):/[A-Za-z]/.test(component)?'en':'other';
   const groupKey=script+'::'+key;
   if(!groups.has(groupKey))groups.set(groupKey,{alias:component,normalized_alias:key,script,product_ids:new Set(),examples:new Set()});
   const row=groups.get(groupKey);
   row.product_ids.add(String(product.id));
   if(product.name)row.examples.add(String(product.name));
  }
 }
 return [...groups.values()].map(row=>({
  alias:row.alias,normalized_alias:row.normalized_alias,language:row.script,
  product_count:row.product_ids.size,example_products:[...row.examples].slice(0,5),
  canonical_ingredient_id:null,source_reference_id:null,source_version:null,
  reviewer_id:null,reviewed_at:null,status:'candidate',clinical_approved:false
 })).sort((a,b)=>b.product_count-a.product_count||a.normalized_alias.localeCompare(b.normalized_alias));
}
export function summarizeIngredientAliasCandidates(rows){
 const candidates=Array.isArray(rows)?rows:[];
 return {total:candidates.length,arabic:candidates.filter(r=>r.language==='ar').length,
  english:candidates.filter(r=>r.language==='en').length,mixed:candidates.filter(r=>r.language==='mixed').length,
  approved:0,automaticallyTranslated:0};
}
export function exportIngredientAliasCandidatesCsv(rows){
 const columns=['alias','normalized_alias','language','product_count','example_products','canonical_ingredient_id','source_reference_id','source_version','reviewer_id','reviewed_at','status'];
 const cell=value=>'"'+String(value??'').replace(/"/g,'""').replace(/^[=+\-@\t\r]/,"'$&")+'"';
 return '\uFEFF'+[columns.join(','),...(Array.isArray(rows)?rows:[]).map(r=>columns.map(c=>cell(c==='example_products'?r.example_products.join(' | '):r[c])).join(','))].join('\r\n');
}
