// Static, honest readiness model. Does not query or mutate production resources.
export const ADMIN_READINESS=Object.freeze([
 {id:'preview_layout',title:'تنسيق مركز الإدارة',state:'implemented',detail:'واجهة تجريبية متجاوبة مع تنقل أفقي'},
 {id:'session_identity',title:'التحقق من هوية الحساب',state:'implemented',detail:'قراءة هوية الجلسة من Supabase Auth دون تعديلها'},
 {id:'role_preview',title:'عرض الأدوار والصلاحيات',state:'implemented',detail:'عرض مقيد وفق دور الحساب؛ ليس بديلاً عن حماية الخادم'},
 {id:'preferences',title:'إعدادات اللغة والكثافة',state:'implemented',detail:'محفوظة على الجهاز فقط؛ الترجمة الكاملة غير مكتملة'},
 {id:'support_isolation',title:'عزل حساب الدعم الفني',state:'verification_required',detail:'يلزم اختبار رفض الوصول بحساب دعم فني حقيقي في بيئة معزولة'},
 {id:'account_recovery',title:'استرداد الحساب وتغيير البريد',state:'not_implemented',detail:'لم تُفعّل مسارات البريد والتحقق من الملكية'},
 {id:'backup_restore',title:'النسخ الاحتياطي والاستعادة',state:'not_implemented',detail:'يلزم خادم آمن واختبار استعادة على بيانات تجريبية'},
 {id:'live_diagnostics',title:'مراقبة صحة الخدمات',state:'not_implemented',detail:'لا توجد حالياً مجسات خادم مباشرة معتمدة'},
 {id:'end_to_end',title:'اختبارات التكامل المرئية',state:'verification_required',detail:'يلزم فحص المتصفح وسيناريوهات الأدوار والتوافق'}
]);
export function readinessSummary(items=ADMIN_READINESS){return {total:items.length,implemented:items.filter(x=>x.state==='implemented').length,verificationRequired:items.filter(x=>x.state==='verification_required').length,notImplemented:items.filter(x=>x.state==='not_implemented').length};}
