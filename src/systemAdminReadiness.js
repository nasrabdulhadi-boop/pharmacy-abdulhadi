// Static, honest readiness model. Does not query or mutate production resources.
export const ADMIN_READINESS=Object.freeze([
 {id:'preview_layout',title:'تنسيق مركز الإدارة',state:'implemented',detail:'واجهة تجريبية متجاوبة مع تنقل أفقي'},
 {id:'session_identity',title:'التحقق من هوية الحساب',state:'implemented',detail:'قراءة هوية الجلسة من Supabase Auth دون تعديلها'},
 {id:'role_preview',title:'عرض الأدوار والصلاحيات',state:'implemented',detail:'عرض مقيد وفق دور الحساب؛ ليس بديلاً عن حماية الخادم'},
 {id:'preferences',title:'إعدادات اللغة والكثافة',state:'implemented',detail:'ترجمة أقسام المركز محفوظة على الجهاز؛ لا تغيّر لغة بقية النظام'},
 {id:'support_isolation',title:'عزل حساب الدعم الفني',state:'implemented',detail:'اجتازت مسارات الحسابات والتصدير المحدد اختبارات HTTP على QA؛ لا تشمل كل دوال النظام'},
 {id:'account_recovery',title:'استرداد الحساب وتغيير البريد',state:'verification_required',detail:'طلب الاسترداد وتغيير البريد مبرمجان على QA؛ تسليم البريد والتأكيد النهائي يحتاجان اختباراً فعلياً'},
 {id:'profile_controls',title:'اسم العرض وكلمة المرور والجلسات',state:'implemented',detail:'حفظ اسم العرض وتغيير كلمة المرور وإلغاء الجلسات الأخرى اختُبرت بحساب اصطناعي'},
 {id:'account_management',title:'إدارة الحسابات وحماية المالك',state:'implemented',detail:'تغيير الأدوار وإلغاء الجلسات ومنع رفع الصلاحية اجتازت اختبارات QA'},
 {id:'backup_export',title:'تصدير تطبيق QA المشفر',state:'implemented',detail:'خدمة للمالك فقط؛ نجح تصدير QA الكامل وفحص التشفير ودقة الأرقام'},
 {id:'backup_restore',title:'النسخ الاحتياطي والاستعادة',state:'not_implemented',detail:'نجحت إعادة بناء قاعدة التطبيق محلياً؛ استعادة خدمات المنصة وAuth غير مختبرة'},
 {id:'live_diagnostics',title:'مراقبة صحة الخدمات',state:'implemented',detail:'مجسات QA مباشرة ومخرجات منقحة؛ لا تثبت صحة النشر أو وصول البريد'},
 {id:'end_to_end',title:'اختبارات التكامل المرئية',state:'verification_required',detail:'يلزم فحص المتصفح وسيناريوهات الأدوار والتوافق'}
]);
export function readinessSummary(items=ADMIN_READINESS){return {total:items.length,implemented:items.filter(x=>x.state==='implemented').length,verificationRequired:items.filter(x=>x.state==='verification_required').length,notImplemented:items.filter(x=>x.state==='not_implemented').length};}
