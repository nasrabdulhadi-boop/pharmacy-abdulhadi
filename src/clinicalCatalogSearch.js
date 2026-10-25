// Read-only search of the last complete catalog audit; never establishes ingredient identity.
export function normalizeClinicalSearch(value){
 return String(value??'').normalize('NFKC').replace(/([a-z])([A-Z])/g,'$1 $2')
  .replace(/[أإآٱ]/g,'ا').replace(/[\u064B-\u065F\u0670ـ]/g,'')
  .replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-0x660))
  .replace(/[۰-۹]/g,c=>String(c.charCodeAt(0)-0x6f0))
  .replace(/\s+/g,' ').trim().toLowerCase();
}
export function buildClinicalSearchIndex(products){
 const rows=Array.isArray(products)?products:[];
 const idCounts=new Map();
 for(const p of rows)if(p?.id!=null)idCounts.set(String(p.id),(idCounts.get(String(p.id))||0)+1);
 return rows.filter(p=>p&&p.id!=null&&String(p.id).trim()&&idCounts.get(String(p.id))===1&&p.active!==false).map(product=>{
  const names=[product.name,product.name_ar,product.name_en].filter(Boolean).map(normalizeClinicalSearch);
  const ingredient=normalizeClinicalSearch(product.active_ingredient);
  const barcodes=[product.barcode,...(Array.isArray(product.additional_barcodes)?product.additional_barcodes:[])].filter(x=>typeof x==='string').map(normalizeClinicalSearch);
  return {product,names,ingredient,barcodes,text:[...names,ingredient,normalizeClinicalSearch(product.strength),normalizeClinicalSearch(product.dosage_form)].join(' ')};
 });
}
export function searchClinicalCatalog(index,query,limit=20){
 const q=normalizeClinicalSearch(query);
 if(!q||q.length>128)return [];
 const tokens=q.split(' '),ranked=[];
 for(const row of Array.isArray(index)?index:[]){
  let rank;
  if(row.barcodes.includes(q))rank=0;
  else if(row.names.includes(q))rank=1;
  else if(row.names.some(n=>n.startsWith(q)))rank=2;
  else if(row.names.some(n=>n.includes(q)))rank=3;
  else if(row.ingredient.includes(q))rank=4;
  else if(tokens.every(token=>row.text.includes(token)))rank=5;
  else continue;
  ranked.push({product:row.product,rank});
 }
 return ranked.sort((a,b)=>a.rank-b.rank||String(a.product.name||'').localeCompare(String(b.product.name||''),'ar')||String(a.product.id).localeCompare(String(b.product.id)))
  .slice(0,Math.max(1,Math.min(Number.isFinite(limit)?Math.floor(limit):20,100))).map(row=>row.product);
}
export function mergeClinicalSearchResults(live,local,limit=20){
 const seen=new Set(),results=[];
 for(const row of [...(Array.isArray(live)?live:[]),...(Array.isArray(local)?local:[])]){
  if(!row||row.id==null||seen.has(String(row.id)))continue;
  seen.add(String(row.id));results.push(row);
  if(results.length>=limit)break;
 }
 return results;
}
