# Pharmacy Abdelhadi v5.13 — System Integration Fix

## التشغيل الصحيح
1. افتح `SYSTEM_V5_13_INTEGRATION_FIX.sql` في Supabase SQL Editor.
2. شغّل الملف كاملاً مرة واحدة.
3. تأكد أن التنفيذ انتهى بـ `COMMIT` بدون خطأ.
4. ارفع هذا المشروع إلى GitHub/Vercel.
5. ادخل الإدارة → الأمان → اضغط **فحص ترابط النظام**.

## ما تم إصلاحه
- إضافة hook قارئ USB Barcode المفقود الذي كان يكسر صفحات المنتجات.
- إضافة BatchForm المفقود الذي كان يكسر صفحة المخزون.
- منتجات الموقع تستخدم مصدر الإدارة نفسه مع فلترة `customer_visible`.
- POS search متوافق مع الباركود والاسم والمادة الفعالة والمخزون/الصلاحية.
- زر تحديث موحد وآمن مع حالة تحميل ورسالة خطأ.
- مرتجع الزبون يحدّث المخزون ويربط الاسترداد بالصندوق عند البيع النقدي، أو بالدين عند البيع الآجل.
- إصلاح قيد حركة المرتجع في `stock_movements`.
- إصلاح تقرير المحاسبة ومنع nested aggregate.
- إضافة حركات المرتجع النقدي إلى الصندوق والتقارير.
- تضمين دوال تفاصيل مبيعات اليوم ومرتجع المورد ضمن ملف الإصلاح حتى لا تعتمد النسخة على نجاح SQL سابق مكسور.
- إضافة `admin_system_healthcheck()` لفحص خريطة الربط.

## خريطة الربط
البيع النقدي → `sales` + `sale_items` → `batches`/`stock_movements` → `cashbox_entries` → `audit_logs` → لوحة التحكم والتقارير.

البيع بالدين → `sales` + `sale_items` → المخزون → `debtor_transactions` → كشف المتدينين والتقارير.

مرتجع الزبون النقدي → `returns` → زيادة المخزون → `stock_movements(customer_return)` → `cashbox_entries(customer_return_refund)` → `audit_logs` → التقارير.

مرتجع الزبون بالدين → `returns` → زيادة المخزون → `stock_movements(customer_return)` → تخفيض ذمة المتدين → `audit_logs`.

مرتجع المورد → `returns` → خفض الدفعة → `stock_movements(supplier_return)` → `audit_logs`، مع بقاء الفاتورة التاريخية محفوظة.

المشتريات → `purchases` + `purchase_items` → `batches` → المخزون → ديون الموردين/دفعاتهم → الصندوق عند الدفع النقدي.

## التحقق
فحصت بنية المصدر بحثاً عن مكونات/خطافات غير معرفة، وتم إصلاح `useUsbBarcodeCapture` و`BatchForm`. تم فحص ZIP بعد البناء، لكن لا يمكنني تشغيل Vite production build هنا لأن `node_modules` غير متوفر و`npm install` لم يكتمل ضمن بيئة التنفيذ. يجب إجراء Build Vercel بعد الرفع كاختبار الإنتاج النهائي.
