import {clinicalCsvCell} from './clinicalCsv.js';
// Read-only prioritization of catalog composition review; never changes product records.
import {parseIngredientField} from './clinicalPreviewEngine.js';
export function buildClinicalReviewQueue(products){
 const rows=Array.isArray(products)?products:[];
 return rows.filter(p=>p&&p.id!=null).map(p=>{
  const raw=String(p.active_ingredient||'').trim();
  const parsed=parseIngredientField(raw);
  const missingStrength=!String(p.strength||'').trim();
  const missingForm=!String(p.dosage_form||'').trim();
  const mixedScripts=/[\u0621-\u064A]/.test(raw)&&/[A-Za-z]/.test(raw);
  const arabic=/[\u0621-\u064A]/.test(raw);
  const reasons=[];
  if(!raw)reasons.push('missing_ingredient');
  else if(parsed.status!=='parsed')reasons.push('ingredient_requires_review');
  if(mixedScripts)reasons.push('mixed_script_ingredient');
  else if(arabic)reasons.push('arabic_alias_verification');
  if(missingStrength)reasons.push('missing_strength');
  if(missingForm)reasons.push('missing_dosage_form');
  const priority=reasons.includes('missing_ingredient')?1:reasons.includes('ingredient_requires_review')||mixedScripts?2:arabic?3:missingStrength||missingForm?4:5;
  return {product_id:p.id,product_name:String(p.name||''),barcode:String(p.barcode||''),active_ingredient:raw,
   priority,reasons,review_status:'pending',canonical_ingredient_ids:[],clinical_approved:false};
 }).sort((a,b)=>a.priority-b.priority||String(a.product_name).localeCompare(String(b.product_name),'ar'));
}
export function summarizeClinicalReviewQueue(queue){
 const rows=Array.isArray(queue)?queue:[];
 return {total:rows.length,priorities:[1,2,3,4,5].map(priority=>({priority,count:rows.filter(r=>r.priority===priority).length})),
  missingIngredient:rows.filter(r=>r.reasons.includes('missing_ingredient')).length,
  needsReview:rows.filter(r=>r.priority<5).length,approved:0};
}
export function exportClinicalReviewQueueCsv(queue){
 const columns=['product_id','product_name','barcode','active_ingredient','priority','reasons','review_status'];
 const csvCell=clinicalCsvCell;
 return '\uFEFF'+[columns.join(','),...(Array.isArray(queue)?queue:[]).map(row=>columns.map(c=>csvCell(c==='reasons'?row.reasons.join('|'):row[c])).join(','))].join('\r\n');
}
