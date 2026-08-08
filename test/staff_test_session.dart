/// م133 — جلسة إدارةٍ جاهزة لاختبارات الواجهة (دعم اختبارات، ليس اختباراً).
///
/// **لماذا وُجد هذا الملف.** م118 وضع بوابة دخول الموظفين في رأس `AppShell`:
/// ```dart
/// if (ref.watch(currentStaffProvider) == null) return const StaffLoginScreen();
/// ```
/// والجلسة بالذاكرة فقط (قرار المالك: موظفان يتناوبان على الجهاز). فصار كل
/// اختبار واجهةٍ يُقلع `DentalApp` يقف عند شاشة **«إنشاء حساب الإدارة»** بدل
/// الصدفة — 124 اختباراً في 42 ملفاً، وهي أعطال اختباراتٍ متقادمة لا أعطال
/// منتج: البوابة تعمل كما صُمّمت تماماً.
///
/// **ما يفعله هذا التجاوز.** يمنح الاختبار جلسة إدارة — التوأم الاختباري
/// لدخول المالك بحسابه، لا تعطيلاً للبوابة. البوابة نفسها تبقى مُختبَرةً في
/// ملفات نظام الصلاحيات التي تقودها قصداً.
///
/// **ولماذا لا يُلمس `kCurrentStaff`.** المرآة العامة تحكم `staffAllowed`،
/// وقاعدتها `kCurrentStaff == null ⇒ اسمح بكل شيء` (مسار الاختبارات
/// والأدوات). إبقاؤها فارغةً يحفظ سلوك كل اختبارٍ قائم حرفياً: الصلاحيات
/// مفتوحة كما كانت، و`staffCreatedBy()` يبقى null فلا يُكتب حقلٌ لم يكن
/// يُكتب. المتغيَّر الوحيد هو ظهور الصدفة بدل شاشة الدخول.
library;

import 'package:dental_clinic_flutter/features/staff/staff_session.dart';
// م133 — `Override` تُصدَّر من `misc.dart` في Riverpod 3 لا من الجذر
// (نفس ما يفعله `m97_lock_defaults_test` أصلاً).
import 'package:flutter_riverpod/misc.dart' show Override;

/// موظف الإدارة الاختباري — `role: admin` فيملك كل الصلاحيات بلا تعداد.
const testAdminStaff = <String, Object?>{
  'id': 'test-admin',
  'username': 'admin',
  'name': 'الإدارة',
  'role': 'admin',
  'perms': <String, Object?>{},
};

/// تجاوزٌ يُدرَج في `ProviderScope.overrides` (أو `ProviderContainer`)
/// فيقلع التطبيق داخل الصدفة مباشرةً.
Override staffAdminSession() =>
    currentStaffProvider.overrideWith((ref) => testAdminStaff);
