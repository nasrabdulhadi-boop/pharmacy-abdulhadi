// Client-side only CSV intake. Never sends reviewed mappings to the database.
import {inspectBilingualReviewPackage} from './clinicalAliasReviewPackage.js';
const headers=['alias','language','canonical_ingredient_id','status','source_reference_id','source_version','source_url','source_document_id','reviewer_id','reviewed_at'];
export function parseBilingualReviewCsv(text){
 const input=String(text||'').replace(/^\uFEFF/,'');
 const records=[];let cells=[],cell='',quoted=false;
 for(let i=0;i<input.length;i++){
  const c=input[i];
  if(c==='"'){
   if(quoted&&input[i+1]==='"'){cell+='"';i++}
   else if(!quoted&&cell==='')quoted=true;
   else if(quoted)quoted=false;
   else throw new Error('Malformed CSV quotation');
  }else if(c===','&&!quoted){cells.push(cell);cell=''}
  else if((c==='\n'||c==='\r')&&!quoted){
   if(c==='\r'&&input[i+1]==='\n')i++;
   cells.push(cell);if(cells.some(x=>x!==''))records.push(cells);
   cells=[];cell='';
  }else cell+=c;
 }
 if(quoted)throw new Error('Unclosed CSV quotation');
 cells.push(cell);if(cells.some(x=>x!==''))records.push(cells);
 if(!records.length)throw new Error('Empty CSV');
 const [head,...body]=records;
 if(head.length!==headers.length||head.some((x,i)=>x!==headers[i]))throw new Error('Unexpected CSV headers');
 if(body.length>25000)throw new Error('CSV exceeds review limit');
 return body.map((cells,index)=>{
  if(cells.length!==headers.length)throw new Error('Invalid column count at row '+(index+2));
  return Object.fromEntries(headers.map((key,i)=>[key,cells[i]]));
 });
}
export function inspectBilingualReviewCsv(text,candidates){
 const records=parseBilingualReviewCsv(text);
 const result=inspectBilingualReviewPackage(records,candidates);
 return {total:records.length,acceptedCount:result.accepted.length,rejected:result.rejected,
  unrecognized:result.unrecognized,conflicts:result.conflicts,clinicalRulesActivated:0,
  productionEnabled:false};
}
