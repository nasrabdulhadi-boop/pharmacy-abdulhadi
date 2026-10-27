import React,{useEffect,useMemo,useRef,useState} from 'react';
import {festManifest as manifest,FEST_RELEVANCE,FEST_ERRORS,loadFestIndex,searchFestMembers,loadFestResults,isFestStatusCurrent,safeFestUrl} from './festReference.js';
function name(m){return m.english[0]||m.names[0]||m.id}
export default function FestReferencePreview(){
 const [index,setIndex]=useState(null),[query,setQuery]=useState(''),[selected,setSelected]=useState([]),[status,setStatus]=useState(null),[busy,setBusy]=useState(false),[error,setError]=useState(''),[result,setResult]=useState(null);
 const task=useRef(0),controller=useRef(null);
 useEffect(()=>()=>{task.current++;controller.current?.abort()},[]);
 useEffect(()=>{const timer=setInterval(()=>{if(status&&!isFestStatusCurrent(status)){setResult(null);setStatus(null)}},5000);return()=>clearInterval(timer)},[status]);
 const change=(ids)=>{task.current++;controller.current?.abort();setBusy(false);setSelected(ids);setResult(null);setError('')};
 async function perform(check){
  controller.current?.abort();const c=new AbortController();controller.current=c;const id=++task.current;
  const timeout=setTimeout(()=>c.abort(),55000);setBusy(true);setError('');setResult(null);setStatus(null);
  try{
   const [data,response]=await Promise.all([index||loadFestIndex({signal:c.signal}),fetch('/api/fest-source-status',{signal:c.signal,cache:'no-store'})]);
   if(!response.ok)throw new Error('fest_status');const state=await response.json();
   if(task.current!==id)return;
   setIndex(data);setStatus(state);
   if(!isFestStatusCurrent(state))throw new Error(state.state==='stale'?'fest_stale':'fest_status');
   if(check){const value=await loadFestResults(data,selected,{signal:c.signal});if(task.current===id){if(!isFestStatusCurrent(state))throw new Error('fest_status');setResult(value)}}
  }catch(e){if(task.current===id)setError(FEST_ERRORS[e.message]||(e.message==='fest_stale'?'تغيّر ملف DMP الرسمي. أُوقف البحث حتى استيراد النسخة الجديدة.':e.name==='AbortError'?'انتهت مهلة التحميل أو أُلغي الطلب. أعد المحاولة.':'تعذر التحقق من حداثة المصدر الرسمي. الفحص غير متاح حالياً.'))}
  finally{clearTimeout(timeout);if(task.current===id)setBusy(false)}
 }
 const hits=useMemo(()=>index?searchFestMembers(index,query):[],[index,query]);
 return <section className="clinicalPreviewPanel festReference" aria-label="مرجع التداخلات FEST">
  <h3>مرجع التداخلات الدوائية — DMP / FEST</h3>
  <p>مصدر مجاني من هيئة المنتجات الطبية النرويجية: {manifest.interactionCount.toLocaleString('en')} سجل تداخل، و{manifest.unassessedCount} سجل لم يُقيَّم. يختار الصيدلي هوية المادة من المصدر يدوياً؛ لم تُربط هذه الهويات بمنتجات الصيدلية.</p>
  <p className="clinicalPreviewWarning">مرجع تجريبي للمراجعة الصيدلانية. الأسماء بالنرويجية أو الإنكليزية ورموز ATC. النصوص الطبية بالنرويجية الأصلية، ولا توجد ترجمة علاجية عربية معتمدة. لا يغطي كل الأدوية أو ظروف المريض، وعدم ظهور سجل لا يعني الأمان.</p>
  <p>ملف المصدر: <bdi>{manifest.sourceFile}</bdi> • تاريخ أساس البيانات: <bdi>{manifest.basisDate}</bdi></p>
  <button type="button" disabled={busy} onClick={()=>perform(false)}>{busy?'جارٍ التحميل والتحقق…':index?'تحديث التحقق من المصدر':'تحميل مرجع FEST والتحقق من حداثته'}</button>
  {status&&<p role="status">{isFestStatusCurrent(status)?'تطابقت بصمة الملف الرسمي مع النسخة المحلية.':'النسخة المحلية قديمة أو تعذر التحقق منها.'} آخر تحقق: <bdi>{status.checkedAt}</bdi>. يُعاد التحقق عند كل فحص.</p>}
  {error&&<p className="clinicalPreviewError" role="alert">{error}</p>}
  {index&&<>
   <label htmlFor="festSearch">ابحث عن مادة باسم المصدر أو رمز ATC</label>
   <input id="festSearch" dir="auto" value={query} maxLength={100} placeholder="مثال: Omeprazol أو B01AC04" onChange={e=>setQuery(e.target.value)}/>
   {query.trim().length>=2&&<div className="festSearchResults" aria-live="polite">
    {!hits.length&&<p>لا توجد هوية مطابقة في قائمة البحث. جرّب الاسم النرويجي أو رمز ATC؛ غياب الاسم لا يعني غياب التداخل.</p>}
    {hits.map(m=><div className="festMember" key={m.id}><span dir="auto"><b>{name(m)}</b><small>{m.names.join(' / ')} • {m.id}</small></span><button type="button" disabled={busy||selected.includes(m.id)||selected.length>=8} onClick={()=>{change([...selected,m.id]);setQuery('')}}>إضافة للمراجعة</button></div>)}
    {hits.length===30&&<p>أول 30 نتيجة؛ أدخل اسماً أو رمزاً أدق.</p>}
   </div>}
   <p>المواد المختارة ({selected.length}/8)</p>
   {selected.map(id=>{const m=index.members.find(m=>m.id===id);return <div className="festMember" key={id}><span dir="auto">{name(m)} <small>{id}</small></span><button type="button" onClick={()=>change(selected.filter(s=>s!==id))}>إزالة من الاختيار</button></div>})}
   <button type="button" disabled={busy||selected.length<2} onClick={()=>perform(true)}>البحث عن تداخلات المواد المختارة</button>
   {selected.length>0&&<button type="button" onClick={()=>change([])}>مسح الاختيار</button>}
  </>}
  {result&&<div aria-live="polite" className="festResults">
   <h4>نتيجة البحث المرجعي: {result.records.length} سجل</h4>
   <p className="clinicalPreviewWarning">هذه سجلات المصدر للمواد المختارة فقط؛ يلزم تقييم الطريق والجرعة والحالة السريرية والمراجع. ليست تصريحاً بصرف الوصفة أو حكماً بأمان الجمع.</p>
   {result.pairs.map((p,i)=><p key={i}><bdi>{p.ids.map(id=>name(index.members.find(m=>m.id===id))).join(' + ')}</bdi>: {p.status==='not_assessed'?'تتضمن مواد لم يُقيّمها المصدر؛ التغطية غير مكتملة.':p.status==='no_source_record'?'لم يُعثر على سجل في هذه النسخة. النتيجة غير حاسمة ولا تعني الأمان.':`${p.recordIds.length} سجل من المصدر.`}</p>)}
   {result.records.map(r=><article className="festRecord" key={r.id}>
    <h4>{FEST_RELEVANCE[r.relevance.code]}</h4>
    <p dir="auto">تصنيف المصدر: <bdi>{r.relevance.label} ({r.relevance.code})</bdi></p>
    {r.groups.map((g,i)=><details key={i}><summary>مجموعة المصدر {i+1}: <bdi>{g.name||g.members.map(n=>name(index.members[n])).slice(0,3).join(' / ')}</bdi></summary><p dir="auto">{g.members.map(n=>`${name(index.members[n])} [${index.members[n].id}]`).join(' / ')}</p></details>)}
    {r.situation&&<div className="clinicalPreviewWarning"><b>شرط انطباق التداخل — يجب قراءته</b><p lang="nb" dir="ltr">{r.situation}</p></div>}
    <b>النتيجة السريرية وفق المصدر</b><p lang="nb" dir="ltr">{r.consequence}</p>
    <b>الآلية</b><p lang="nb" dir="ltr">{r.mechanism||'لم يرد نص في هذا الحقل.'}</p>
    <b>التعامل مع التداخل وفق المصدر؛ يتطلب مراجعة صيدلانية</b><p lang="nb" dir="ltr">{r.management||'لم يرد نص في هذا الحقل.'}</p>
    <p>أساس الدليل: <bdi>{r.evidence?.label||'غير مذكور'} ({r.evidence?.code})</bdi></p>
    <details><summary>المراجع وهوية السجل</summary><p dir="ltr">{r.id} • {r.updatedAt}</p>
     {!r.references.length&&<p>لا توجد إحالة ببليوغرافية في هذا السجل من الملف؛ يلزم الرجوع إلى DMP.</p>}
     {r.references.map((ref,i)=><p dir="ltr" key={i}>{ref.citation} {safeFestUrl(ref.url)&&<a href={safeFestUrl(ref.url)} target="_blank" rel="noopener noreferrer">فتح المرجع</a>}</p>)}
    </details>
   </article>)}
  </div>}
  <details><summary>المصدر والترخيص وحدود التغطية</summary>
   <p dir="ltr">{manifest.attribution}</p><p><a href={manifest.sourcePage} target="_blank" rel="noopener noreferrer">المصدر وشروط DMP</a> • <a href={manifest.licenseUrl} target="_blank" rel="noopener noreferrer">NLOD 2.0</a></p>
   <p>التعديلات: استخراج سجلات التداخل والمواد غير المقيّمة وفهرستها، مع إضافة أسماء إنكليزية للبحث حيث كان الربط داخل FEST واضحاً. حُفظت النصوص الطبية الأصلية. هذا التطبيق غير معتمد أو مؤيَّد من DMP.</p>
   <p>المطابقة تستخدم هوية المصدر أو تسلسل ATC فقط؛ قد توجد المادة بأكثر من رمز، ولا ندمج الأملاح أو رموز المادة المختلفة تلقائياً. ينبغي اختيار الهوية الصحيحة والتحقق من جميع رموزها. لا يستنتج البحث أمان الجرعة أو الحمل أو الحساسية أو وظائف الكلى.</p>
   <p>تُحمّل ملفات عامة فقط؛ لا تُرسل اختياراتك أو بيانات الصيدلية إلى DMP. التحقق صالح لخمس دقائق كحد أقصى، ويوقف العرض عند انتهاء الصلاحية أو تغيّر المصدر أو تعذر الاتصال. تحديث البيانات يتم بإعادة الاستيراد الكامل.</p>
  </details>
 </section>
}
