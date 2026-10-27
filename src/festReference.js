import manifest from './festManifest.json' with {type:'json'};
export {manifest as festManifest};
export const FEST_STATUS_TTL = 5 * 60 * 1000;
export const FEST_RELEVANCE = {'1':'ينبغي تجنب الجمع حسب المصدر','2':'يلزم اتخاذ احتياطات حسب المصدر','3':'لا يلزم إجراء حسب سياق المصدر؛ ليس حكماً عاماً بالأمان'};
const fail = () => {throw new Error('fest_invalid_data')};
export function validateFestIndex(index) {
 if(index?.snapshot!==manifest.snapshot||index.members?.length!==manifest.memberCount||index.records?.length!==manifest.interactionCount||index.unassessed?.length!==manifest.unassessedCount) fail();
 const ids=new Set();
 for(const m of index.members){if(!m.id||ids.has(m.id)||!Array.isArray(m.names)||!Array.isArray(m.english))fail();ids.add(m.id)}
 const validMember=n=>Number.isInteger(n)&&n>=0&&n<index.members.length;
 const records=new Set();
 for(const r of index.records){if(records.has(r.id)||!FEST_RELEVANCE[r.relevance]||!Number.isInteger(r.shard)||r.shard<0||r.shard>15||r.groups?.length!==2||r.groups.some(g=>!g.length||!g.every(validMember)))fail();records.add(r.id)}
 if(!index.unassessed.every(validMember))fail();
 return index;
}
const normalize=s=>String(s).normalize('NFKC').trim().toLocaleLowerCase('en');
export function searchFestMembers(index,query,limit=30){
 const q=normalize(query);if(q.length<2)return [];
 return index.members.filter(m=>m.selectable&&[m.id,...m.names,...m.english].some(v=>normalize(v).includes(q))).slice(0,limit);
}
// Only explicit source identities are matched. No product-name, salt or brand equivalence.
export function festIdentityMatches(selected,group){
 if(selected===group)return true;
 if(!/^atc:[A-Z]\d{2}[A-Z]{2}\d{2}$/.test(selected)||!group.startsWith('atc:'))return false;
 const code=group.slice(4);return [1,3,4,5].includes(code.length)&&selected.slice(4).startsWith(code);
}
export function findFestRecords(index,selectedIds){
 if(!Array.isArray(selectedIds)||selectedIds.length<2||selectedIds.length>8||new Set(selectedIds).size!==selectedIds.length)throw new Error('fest_selection');
 const members=new Map(index.members.map(m=>[m.id,m]));
 if(selectedIds.some(id=>!members.get(id)?.selectable))throw new Error('fest_selection');
 const matches=(id,group)=>group.some(n=>festIdentityMatches(id,index.members[n].id));
 const pairs=[];const found=new Map();
 for(let a=0;a<selectedIds.length;a++)for(let b=a+1;b<selectedIds.length;b++){
  const ids=[selectedIds[a],selectedIds[b]];
  const rows=index.records.filter(r=>(matches(ids[0],r.groups[0])&&matches(ids[1],r.groups[1]))||(matches(ids[1],r.groups[0])&&matches(ids[0],r.groups[1])));
  rows.forEach(r=>found.set(r.id,r));
  const unassessed=ids.filter(id=>index.unassessed.some(n=>festIdentityMatches(id,index.members[n].id)));
  pairs.push({ids,recordIds:rows.map(r=>r.id),unassessed,status:unassessed.length?'not_assessed':rows.length?'source_records':'no_source_record'});
 }
 return {records:[...found.values()].sort((a,b)=>Number(a.relevance)-Number(b.relevance)||a.id.localeCompare(b.id)),pairs,safeToCombine:null};
}
export function isFestStatusCurrent(status,now=Date.now()){
 const checked=Date.parse(status?.checkedAt);
 return status?.snapshot===manifest.snapshot&&status?.state==='current'&&Number.isFinite(checked)&&checked<=now+30000&&now-checked<FEST_STATUS_TTL;
}
export function safeFestUrl(url){try{const u=new URL(url);return ['http:','https:'].includes(u.protocol)&&!u.username&&!u.password?u.href:null}catch{return null}}
export async function fetchFestFile(name,{fetcher=fetch,signal}={}){
 const meta=manifest.files[name];if(!meta)fail();
 const response=await fetcher('/clinical/fest/'+name,{signal,cache:'no-cache'});
 if(!response.ok)throw new Error('fest_download');
 const bytes=await response.arrayBuffer();
 if(bytes.byteLength!==meta.bytes)fail();
 const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
 if(hash!==meta.sha256)fail();
 let text;
 if(name.endsWith('.gz')){
  if(typeof DecompressionStream==='undefined')throw new Error('fest_browser');
  text=await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'))).text();
 }else text=new TextDecoder().decode(bytes);
 const data=JSON.parse(text);if(data.snapshot!==manifest.snapshot)fail();return data;
}
export async function loadFestIndex(options){return validateFestIndex(await fetchFestFile('index.json.gz',options))}
export async function loadFestResults(index,ids,options={}){
 const plan=findFestRecords(index,ids);
 // Stage all shards before returning any result; a missing shard never looks like a negative check.
 const shards=await Promise.all([...new Set(plan.records.map(r=>r.shard))].map(async shard=>{
  const data=await fetchFestFile(`records-${shard.toString(16).padStart(2,'0')}.json.gz`,options);
  return data.records;
 }));
 const all=new Map(shards.flat().map(r=>[r.id,r]));
 const records=plan.records.map(light=>{
  const r=all.get(light.id);
  if(!r?.consequence||r.relevance?.code!==light.relevance||JSON.stringify(r.groups?.map(g=>g.members))!==JSON.stringify(light.groups))fail();return r;
 });
 return {...plan,records};
}
export const FEST_ERRORS={fest_invalid_data:'ملفات المصدر غير مكتملة أو لا تطابق الإصدار. أوقف الفحص وأعد تحميل الصفحة.',fest_download:'تعذر تنزيل بيانات المصدر. الفحص غير مكتمل.',fest_browser:'المتصفح لا يدعم فك ملفات المصدر. استخدم متصفحاً حديثاً.',fest_selection:'اختر من مادتين إلى ثماني مواد مختلفة من قائمة المصدر.'};
