// Structural checks only: these cannot verify authorship, source contents or license rights.
export const nonemptyText=value=>typeof value==='string'&&value.trim().length>0;
export const validClinicalId=value=>nonemptyText(value)&&value===value.trim()&&value.length<=256&&!/[\s\u0000-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2066-\u2069]/.test(value);
export function validReviewDate(value){
 if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}(?:T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,3})?(?:Z|[+-](?:0\d|1[0-4]):[0-5]\d))?$/.test(value))return false;
 const date=new Date(value.slice(0,10)+'T00:00:00Z');
 return Number.isFinite(Date.parse(value))&&Number.isFinite(date.getTime())&&date.toISOString().slice(0,10)===value.slice(0,10);
}
export function validSourceUrl(value){
 if(!nonemptyText(value))return false;
 try{const url=new URL(value);return ['https:','http:'].includes(url.protocol)&&Boolean(url.hostname)&&!url.username&&!url.password}
 catch{return false}
}
export function hasSourceLocator(row){
 return Boolean(row&&(nonemptyText(row.source_url)?validSourceUrl(row.source_url):nonemptyText(row.source_document_id)));
}
export function hasReviewMetadata(row){
 return Boolean(row&&nonemptyText(row.reviewer_id)&&validReviewDate(row.reviewed_at));
}
