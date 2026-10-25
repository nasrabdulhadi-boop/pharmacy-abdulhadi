// Client-side only CSV intake. Never sends reviewed mappings to the database.
import {inspectBilingualReviewPackage} from './clinicalAliasReviewPackage.js';
const headers=['alias','language','canonical_ingredient_id','status','source_reference_id','source_version','source_url','source_document_id','reviewer_id','reviewed_at'];
export function parseBilingualReviewCsv(text){
 const input=String(text||'').replace(/^\uFEFF/,'');
 if(input.length>5*1024*1024)throw new Error('CSV exceeds 5 MB limit');
 const records=[];let cells=[],cell='',state='start';
 const finishCell=()=>{cells.push(cell);cell='';state='start'};
 const finishRow=()=>{finishCell();if(cells.some(x=>x!==''))records.push(cells);cells=[]};
 for(let i=0;i<input.length;i++){
  const c=input[i];
  if(state==='quoted'){
   if(c==='"'&&input[i+1]==='"'){cell+='"';i++}
   else if(c==='"')state='closed';
   else cell+=c;
  }else if(c===','){finishCell()}
  else if(c==='\n'||c==='\r'){
   if(c==='\r'&&input[i+1]==='\n')i++;
   finishRow();
  }else if(c==='"'){
   if(state!=='start')throw new Error('Malformed CSV quotation');
   state='quoted';
  }else{
   if(state==='closed')throw new Error('Unexpected text after CSV quotation');
   cell+=c;state='plain';
  }
 }
 if(state==='quoted')throw new Error('Unclosed CSV quotation');
 finishRow();
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
 return {total:records.length,acceptedCount:result.accepted.length,sandboxAliases:result.accepted,rejected:result.rejected,
  unrecognized:result.unrecognized,conflicts:result.conflicts,clinicalRulesActivated:0,
  productionEnabled:false};
}
