# Pharmacy Abdelhadi V6.3.8 FINAL CHECK

## إصلاحات هذه النسخة
1. إصلاح خطأ PostgreSQL: `column reference "quantity" is ambiguous` داخل `admin_list_sale_items` عبر تأهيل `returns.quantity` بالاسم المستعار `r0.quantity`.
2. الحفاظ على سطر `sale_items` التاريخي وعدم حذفه من قاعدة البيانات؛ عند اكتمال المرتجع يختفي الصنف من قائمة الأصناف القابلة للإرجاع.
3. `admin_customer_return` يسجل المرتجع، يعيد الكمية للدفعة، ويسجل `customer_return` في `stock_movements`، ويعالج استرداد النقد/تعديل دين الزبون، ويسجل audit.
4. لوحة التحكم لم تعد تفشل بالكامل إذا فشل استعلام فرعي واحد. كل مصدر بيانات يعالج بشكل مستقل، ويظهر الخطأ للمستخدم بدلاً من ترك اللوحة فارغة بصمت.
5. لوحة التحكم تعتمد على `admin_get_products` و`admin_get_inventory` بدلاً من استعلامات مباشرة قد تتأثر بـRLS، مع الحفاظ على RPCs المالية.
6. الربح وصافي المبيعات في لوحة التحكم يأخذان قيمة `admin_dashboard_day_details`/`admin_dashboard_financial_summary` بعد إصلاح المرتجعات.
7. مخطط آخر 7 أيام يستمر بالعمل حتى لو فشل يوم واحد؛ الأيام المتاحة تستخدم RPC، وغير المتاح يعود لبيانات المبيعات الشهرية.

## تحقق محلي
- JSX/TypeScript transpilation: PASS.
- عدد الأقواس `{}` في `src/main.jsx`: متطابق.
- فحص SQL النصي للمرجع الغامض `SUM(quantity) returned_qty`: PASS — لم يعد موجوداً.
- فحص وجود تسجيل حركة `customer_return`: PASS.
- فحص وجود استرداد الصندوق: PASS.
- فحص إخفاء السطر بعد اكتمال المرتجع: PASS.
- أرشيف ZIP يجب أن يمر `unzip -t` قبل التسليم.

## ملاحظة مهمة
لم يتم تنفيذ Supabase حي أو Browser E2E من هذه البيئة، لذلك لا يُدّعى أن النشر الإنتاجي تم اختباره. بعد رفع النسخة، يجب تشغيل ملف SQL الجديد فقط:
`V6_3_8_DASHBOARD_RETURNS_INTEGRITY_FIX.sql`
ولا تشغّل ملفات SQL التاريخية دفعة واحدة.
