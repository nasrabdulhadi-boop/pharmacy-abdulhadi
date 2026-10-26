// Source review only. Format checks do not verify licensing or clinical correctness.
import {inspectEvidenceCandidates,validateEvidenceCandidate} from './clinicalEvidenceIntake.js';
import {validReviewDate} from './clinicalProvenance.js';
import {clinicalCsvCell} from './clinicalCsv.js';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function officialSource(row){
 try{
  const page=new URL(row.source_url),xml=new URL(row.source_xml_url);
  return [page,xml].every(u=>u.protocol==='https:'&&u.hostname==='dailymed.nlm.nih.gov'&&!u.port&&!u.username&&!u.password&&!u.hash)&&
   page.pathname==='/dailymed/drugInfo.cfm'&&[...page.searchParams.keys()].join(',')==='setid'&&page.searchParams.get('setid')===row.label_set_id&&
   xml.pathname==='/dailymed/services/v2/spls/'+row.label_set_id+'.xml'&&!xml.search;
 }catch{return false}
}
export function reviewPrimaryLabelPacket(packet){
 const result={cases:[],rejectedCount:0,conflictCount:0,clinicalRulesActivated:0,clinicallyApproved:false,productionEnabled:false,sourceVerification:'format_only'};
 if(packet?.mode!=='primary_label_review_candidates'||packet.clinicalRulesActivated!==0||packet.productionEnabled!==false||!Array.isArray(packet.cases))return {...result,rejectedCount:1};
 const eligible=[];
 for(const row of packet.cases){
  const effective=String(row?.effective_time||'');
  const date=effective.slice(0,4)+'-'+effective.slice(4,6)+'-'+effective.slice(6,8);
  const retrieved=String(row?.retrieved_at||'');
  const valid=validateEvidenceCandidate(row).valid&&row.source_id==='DailyMed-SPL'&&officialSource(row)&&
   uuid.test(row.label_set_id)&&uuid.test(row.label_document_id)&&uuid.test(row.section_id)&&
   row.source_record_id===row.label_document_id+':'+row.section_id&&/^\d+$/.test(row.source_version)&&
   /^\d{8}$/.test(effective)&&validReviewDate(date)&&validReviewDate(retrieved)&&
   /^[0-9a-f]{64}$/.test(row.source_sha256)&&typeof row.section_title==='string'&&row.section_title.trim()&&
   row.original_text.trim().split(/\s+/).length<=25&&row.excerpt_is_not_full_guidance===true&&
   row.source_check==='excerpt_matched_primary_spl'&&row.review_status==='pending'&&row.clinical_approved===false&&
   row.negative_safety_claim_allowed===false;
  if(!valid){result.rejectedCount++;continue}
  eligible.push(row);
 }
 const inspected=inspectEvidenceCandidates(eligible);
 result.cases=inspected.accepted;result.conflictCount=inspected.quarantinedRecordCount;
 result.rejectedCount+=inspected.invalid.length;
 return result;
}
export function exportPrimaryLabelReviewCsv(review){
 const headers=['source_id','source_record_id','ingredient_a','ingredient_b','source_version','effective_time','source_url','section_title','original_text','source_sha256','license_status','review_status','reviewer_id','reviewed_at','review_notes'];
 const rows=(review?.cases||[]).map(row=>headers.map(field=>['reviewer_id','reviewed_at','review_notes'].includes(field)?'':field==='review_status'?'pending':row[field]));
 return '\uFEFF'+[headers,...rows].map(row=>row.map(clinicalCsvCell).join(',')).join('\r\n');
}
