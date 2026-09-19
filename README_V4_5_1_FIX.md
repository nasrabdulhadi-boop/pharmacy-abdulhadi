# Pharmacy Abdelhadi v4.5.1 — إصلاح حفظ المشتريات والتمرير

## الإصلاحات
1. إصلاح خطأ حفظ فاتورة الشراء: جدول `audit_logs` يستخدم `user_id` وليس `created_by`. تم تصحيح دالة `admin_create_purchase` لتسجل `auth.uid()` في `user_id`.
2. إصلاح التمرير في لوحة الإدارة على الكمبيوتر والهاتف بإزالة أي قيود على scroll وإضافة `overflow-y:auto` للصفحة ولوحة الإدارة.

## المطلوب
شغّل ملف `V4_5_1_FIX.sql` في Supabase SQL Editor ثم ارفع ملفات المشروع إلى GitHub.
