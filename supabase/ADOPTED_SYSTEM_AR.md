# النظام المعتمد لإدارة التراخيص — توثيق الاعتماد (2026‑08‑05)

## القصة بسطرين
جلستا عملٍ متوازيتان للمالك بنتا نظامي تراخيص: هذه الجلسة صممت هجرات
0032–0034 (لم تُطبَّق)، وجلسة أخرى طبّقت نظاماً كاملاً بهجرات 0032–0048
على الخادم صباح 2026‑08‑05. **قرار المالك: اعتماد المطبَّق والبناء فوقه**،
فحُذفت ملفات التصميم غير المطبَّق من هذا المستودع (باقية في تاريخ git).

## خريطة النظام المعتمد (كما على الخادم)
- **الجداول**: plans · subscriptions (فيها session_epoch وtrial وlimits_override)
  · activation_codes (تجزئة code_hash + code_prefix — لا نص صريح)
  · devices · user_presence · notifications · storage_usage · admins · admin_audit
  + مخطط خاص `app_private.config` (gate/trial/license/r2) غير مكشوف لـPostgREST.
- **الدوال** (SECURITY DEFINER + search_path فارغ + حارس _admin_guard):
  is_admin · verify_license(p_device) · activate_code(p_code,p_device)
  · admin_monitor_snapshot · admin_users_page · admin_generate_codes
  · admin_set_status/expiry/plan/features/storage_quota · admin_transfer_license
  · admin_reset_license · admin_revoke_device · admin_force_logout
  · admin_send_notification · admin_get_config/set_config · admin_user_entity_counts.
- **دوال الحافة**: admin-monitor (لقطة + R2) · admin-users · admin-config
  · admin-user-op — كلها تتحقق من is_admin بمرور JWT المستدعي.
- **حالة الأعلام عند الاعتماد**: gate.enforce=false (لا إجبار بعد) ·
  trial: enabled=true, days=14 · license.grace_days=7 · r2: اعتمادات فارغة.
- **المنح**: دوال is_admin/monitor/verify/activate ممنوحة لـauthenticated —
  الحارس داخل الدالة (نفس عقيدة pull_changes).
- **دوال المزامنة الحية لم تُمسّ** (pull_changes/push_ops بلا أي إشارة
  للاشتراكات) — تطبيق العيادة v133 يعمل كما هو.

## ما نُفِّذ من هذه الجلسة فوق النظام المعتمد
- 0049: بذر المدراء الثلاثة (باعتماد المالك) — وتحقق محاكاةً بأن
  is_admin=true وadmin_monitor_snapshot تعيد أقسامها الخمسة.
- لوحة التحكم (مشروع control_panel المستقل) كُيّفت على أسماء دواله:
  is_admin + admin-monitor (حافة) بسقوط رشيق إلى admin_monitor_snapshot.

## نقاط مفتوحة موروثة عن النظام المعتمد (تُعالج في مراحلها)
1. خطط بأسماء إنجليزية (Trial/Basic/Pro) — تعريبها في مرحلة إدارة الخطط.
2. الفترة التجريبية مفعَّلة (14 يوماً) في الإعداد رغم أن الإجبار مطفأ —
   بلا أثر على المستخدمين حتى تفعيل البوابة؛ تُضبط من مرحلة التجريبية.
3. عدّاد «نشط الآن» يعتمد user_presence (فارغ حتى يبدأ تطبيق العيادة
   بنداء verify_license في مرحلة شاشة التفعيل) — بديله الحالي الصادق صفر.
4. اعتمادات R2 تُحفظ في app_private.config عبر admin_set_config —
   تُضبط من شاشة إعدادات اللوحة في مرحلة التخزين.
5. استيراد ملفات SQL للهجرات 0032–0048 من أرشيف الجلسة الأخرى إلى هذا
   المستودع حين يوفّره المالك — ليبقى المستودع مصدر الحقيقة الكامل.

## المرحلة ٧ (0054) — إدارة الخطط من اللوحة
- `admin_plans_page()` — كل الخطط (نشطة ومعطلة) بعدّادات: مشتركون/نشطون/أكواد/متاح.
- `admin_upsert_plan(p_id, p_code, p_name, p_description, p_features, p_is_active, p_sort)` — إنشاء (id فارغ) أو تعديل؛ رموز أخطاء: plan_bad_code/name/features/limit · plan_code_exists · plan_not_found · plan_protected.
- `admin_copy_plan(p_id, p_code?, p_name?)` — النسخة تبدأ معطَّلة؛ لاحقة تلقائية عند تصادم الرمز المولَّد.
- `admin_delete_plan(p_id)` — يرفض trial (محمية) وأي خطة عليها مشتركون أو أكواد (plan_in_use).
- كل الكتابات تُدقَّق في admin_audit بأفعال plan_create/plan_update/plan_copy/plan_delete.

## المرحلة ٨ (0055) — التجديد الذرّي
- `admin_renew_subscription(p_user, p_days, p_plan?, p_from_now)` — تجديد/تمديد/تغيير خطة في عملية واحدة: الأساس max(الآن، الانتهاء) أو الآن مع from_now؛ days=0 مع خطة = تغيير خطة فقط؛ الحالة تصير active؛ المحظور/المجمَّد يُرفضان (renew_banned/renew_frozen)؛ الخطط المعطلة تُرفض (plan_inactive)؛ يدعم مستخدماً بلا صف اشتراك (إدراج)؛ تدقيق admin_audit بفعل renew (قبل/بعد).

## المرحلة ٩ (0056) — سجل العمليات الشامل
- `admin_audit_page(p_action?, p_search?, p_limit, p_offset)` — قراءة مرشَّحة (بفعل و/أو بحث بريد المشرف/الهدف) ومرقَّمة لجدول admin_audit؛ يُثري target_email من auth.users حين تركته دالة قديمة فارغاً؛ سقف limit=200؛ ترتيب تنازلي بالمعرّف.
- فهرس admin_audit_action_id_idx (action, id desc) لإسناد الترتيب والفلترة.
- لا كتابة — نافذة قراءة على السجل الذي تملؤه كل دوال الكتابة أصلاً.

## المرحلة ١٠ (0057) — التصلّب الأمني النهائي
- سجل التدقيق admin_audit صار إلحاقاً فقط: مُشغِّل app_private.admin_audit_append_only يمنع UPDATE/DELETE نهائياً (تدقيق غير قابل للعبث).
- app_private.prune_rate_limit(): تشذيب نوافذ التقييد الأقدم من ٢٤ ساعة (نظافة).
- admin_security_audit(): تدقيق ذاتي قراءة-فقط للمشرفين يعيد ٧ فحوص (RLS شامل، search_path مثبَّت لكل definer، مناعة السجل، تجزئة الأكواد، تقييد تفعيل الأكواد، وجود مشرفين، فترة السماح) + posture (enforce/trial/grace/admins/gated_users/rate_limit_rows).
- الجرد أثبت أن الأساس متين مسبقاً: RLS على كل الجداول، صفر دالة definer بلا search_path، activate_code مقيَّدة (٨/ساعة) ومجزِّئة.
- ملاحظة تشغيلية وقت التسليم: gate.enforce=true، trial=false، grace=1 يوم، gated_users=2 (قرارات المالك من شاشة الإعدادات).

## المرحلة ب (0059) — حارس عدد العيادات
- العيادات مصفوفة داخل صفّ الإعدادات app.config (كيان settings). الحارس عند تطبيقه في apply_changes.
- gate.enforce_clinics (مطفأ افتراضاً) — قياس فقط حتى تفعيله.
- clinics_guard(uid,count) SECURITY DEFINER: يقرأ max_clinics من effective_features وينفّذ القرار ويسجّل clinics_over_probe (مرة/ساعة/مستخدم)؛ apply_changes يرفع الدفعة (clinics_over_limit) حين block.
- العميل يقرأ max_clinics من حمولة verify_license (features) عبر LicenseSnapshot.maxClinics + cachedMaxClinics المتزامن، ويمنع الإضافة في شاشتي الإعداد والإعدادات.

## المرحلة ج (0060) — حد الأجهزة وإدارتها
- أعمدة devices: brand · os_version · last_sync.
- verify_license (نسخة معتمدة + إضافات): يلتقط brand/os_version/last_sync؛ device_block=(enforce_devices AND NOT device_allowed)؛ يسجّل device_over_probe (مرة/ساعة) قياساً؛ يصدّر device_block/device_enforced/device_count/max_devices.
- gate.enforce_devices مطفأ افتراضاً.
- admin_user_devices أغنى (brand/os/last_sync/status)؛ admin_reset_devices يبطل كل أجهزة مستخدم + تدقيق devices_reset.
- العميل: LicenseGateResult.deviceLimit + شاشة «تجاوز حد الأجهزة»؛ _device يرسل os_version (dart:io Platform).

## المرحلة د (0061، 0062) — شاشة الاشتراك والترخيص
- get_my_subscription(): starts_at/plan_name/code_prefix/last_verified/last_sync/device_count (قراءة self).
- list_public_plans(): الباقات النشطة للمقارنة (code/name/features).
- العميل: LicenseTransport.getMySubscription + listPublicPlans؛ قسم SubscriptionSection في الإعدادات (سحابي فقط): الخطة/الحالة/التواريخ/المتبقي، العيادات والأجهزة مستخدَم/مسموح، شريط تخزين بتنبيهات 80/90/95/100، الصور/الإصدار/الكود/آخر تحقق/مزامنة، رسائل تجربة/انتهاء، تجديد+ترقية بالكود (activate)، ومقارنة باقات.

## المرحلة و (0063) — توسعة التدقيق الأمني + مصفوفة الاختراق
- admin_security_audit موسّعة: تُبقي الفحوص السبعة + posture الأصلية، وتضيف فحص enforcement_subflags وعدّادات storage_over_users/clinics_over_users/devices_over_users والمفاتيح الفرعية الثلاثة.
- tool/pentest_matrix.sql: مصفوفة اختراق مرتجعة (begin/rollback) تحاول تجاوز كل حارس وتؤكد الحجب/القياس — نجحت كاملةً على الإنتاج.
- deliver/SECURITY_REPORT.html: تقرير أمني ختامي (مصفوفة الضوابط + المنهجية + لقطة الوضع).

## المرحلة هـ (0064) — الإشعارات داخل التطبيق (بلا Firebase)
- عمود notifications.data jsonb {image_url,action_label,action_url}.
- get_my_notifications() / mark_notification_read(id): ذاتيّة.
- admin_send_notification موسّعة (p_data، مع إسقاط توقيع الأربعة) + admin_broadcast_notification (صف/مستخدم، يعيد العدد) — تُدرِجان في admin_audit مباشرةً.
- app_private.config[app_update] {enabled,version,url,notes} + get_app_update() للقراءة.
- ملاحظة: admin_audit جدولٌ إلحاقيّ لا دالة (أُصلح نداءان).

## 0065 — السماح بمفتاح app_update في admin_set_config
- admin_set_config كان يرفض app_update (unknown config key)؛ أُضيف للقائمة المسموحة. إصلاح خادمي بحت — لا يحتاج إعادة بناء اللوحة (v1.1.3 يرسل المفتاح صحيحاً أصلاً).
