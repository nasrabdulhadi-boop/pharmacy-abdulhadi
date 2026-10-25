// Local preview presentation only. No database access or clinical approval.
export function createLatestPreviewTask(){
 let generation=0;
 return {
  invalidate(){generation++},
  async run(work,{success,error,settled}={}){
   const request=++generation;
   const isCurrent=()=>request===generation;
   try{const value=await work(isCurrent);if(isCurrent())success?.(value)}
   catch(problem){if(isCurrent())error?.(problem)}
   finally{if(isCurrent())settled?.()}
  }
 };
}

const messages={
 'CSV exceeds 5 MB limit':'حجم ملف CSV يتجاوز الحد المسموح (5 ميغابايت)',
 'Malformed CSV quotation':'تنسيق علامات الاقتباس في CSV غير صالح',
 'Unexpected text after CSV quotation':'توجد أحرف غير متوقعة بعد إغلاق علامات الاقتباس',
 'Unclosed CSV quotation':'توجد علامة اقتباس غير مغلقة في ملف CSV',
 'Empty CSV':'ملف CSV فارغ',
 'Unexpected CSV headers':'عناوين أعمدة CSV غير مطابقة للنموذج',
 'CSV exceeds review limit':'ملف CSV يتجاوز حد 25 ألف سجل',
 'missing canonical ingredient':'معرّف المادة الفعالة الموحّد مفقود',
 'unsupported language':'اللغة يجب أن تكون ar أو en',
 'missing alias':'اسم المرادف مفقود',
 'alias not approved':'المرادف لم يستكمل حالة المراجعة المطلوبة في الملف',
 'missing pharmacist review':'بيانات الصيدلاني المراجع أو تاريخ المراجعة مفقودة',
 'missing source traceability':'بيانات المصدر أو الإصدار أو رابط التوثيق مفقودة',
 'duplicate alias in review package':'المرادف مكرر ضمن ملف المراجعة',
 'missing_ingredient':'المادة الفعالة مفقودة',
 'ingredient_requires_review':'صيغة المادة الفعالة تحتاج مراجعة',
 'mixed_script_ingredient':'المادة مكتوبة بمزيج من العربية والإنكليزية',
 'arabic_alias_verification':'الاسم العربي يحتاج توثيق مطابقته',
 'missing_strength':'التركيز مفقود',
 'missing_dosage_form':'الشكل الدوائي مفقود'
};
export function clinicalPreviewMessage(value){
 const message=String(value||'تعذر قراءة الملف');
 return messages[message]||message.replace(/^Invalid column count at row (\d+)$/,'عدد الأعمدة غير صحيح في السجل $1');
}

export function clinicalReviewIssueMessages(result,limit=50){
 if(!result)return [];
 const rows=[
  ...(result.rejected||[]).map(row=>`السجل ${row.index+2}: ${(row.problems||[]).map(clinicalPreviewMessage).join('، ')}`),
  ...(result.unrecognized||[]).map(row=>`السجل ${row.index+2}: الاسم «${row.alias}» غير موجود ضمن مرشحات التدقيق`),
  ...(result.conflicts||[]).map(row=>`تعارض مرادف «${row.alias}» بين المعرّفين ${row.first||'غير محدد'} و${row.second||'غير محدد'}`)
 ];
 return rows.slice(0,limit);
}
