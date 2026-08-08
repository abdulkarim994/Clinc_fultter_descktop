/// م118 — جلسة الموظف الحالي (المرحلة 1 من نظام الصلاحيات).
///
///  الجلسة بالذاكرة فقط: كل فتحٍ للتطبيق يبدأ بشاشة الدخول (قرار المالك —
///  موظفا استعلاماتٍ صباحي ومسائي يتناوبان على نفس الجهاز). المتغير العام
///  [kCurrentStaff] مرآة المزود لغير الودجتات (سجل التدقيق في المرحلة 3).
library;

import 'package:flutter_riverpod/legacy.dart';

import '../../data/audit/audit_trail.dart' show currentAuditStaff, currentAuditStaffDisplay;

typedef JMap = Map<String, Object?>;

/// الموظف الحالي — null = لا جلسة (تُعرض شاشة الدخول).
final currentStaffProvider = StateProvider<JMap?>((ref) => null);

/// مرآةٌ عامة للجلسة لغير الودجتات (تضبطها شاشة الدخول والخروج).
JMap? kCurrentStaff;

/// هل الموظف [u] إدارة؟
bool staffIsAdmin(JMap? u) => u != null && u['role'] == 'admin';

/// هل يملك الموظف [u] الصلاحية [perm]؟ الإدارة تملك كل شيء.
bool staffCan(JMap? u, String perm) {
  if (u == null) return false;
  if (staffIsAdmin(u)) return true;
  final perms = u['perms'];
  return perms is Map && perms[perm] == true;
}

/// م120 — ضبط الجلسة من نقطة واحدة: المرآة العامة + ختم سجل التدقيق.
/// (المزود يضبطه المنادي — يحتاج ref وهذه الدالة نقية بلا ودجات.)
void applyStaffSession(JMap? u) {
  kCurrentStaff = u;
  currentAuditStaff = u == null ? '' : '${u['username'] ?? ''}';
  currentAuditStaffDisplay = u == null ? '' : '${u['name'] ?? ''}';
}

/// م120 — قيمة `createdBy` للإدخالات الجديدة: اسم دخول الموظف الحالي،
/// وnull بلا جلسة (اختبارات/أدوات) فلا يُكتب الحقل أصلاً.
String? staffCreatedBy() {
  final u = '${kCurrentStaff?['username'] ?? ''}';
  return u.isEmpty ? null : u;
}

/// اسم الموظف الحالي للعرض والتدقيق ('' بلا جلسة).
String currentStaffName() => '${kCurrentStaff?['name'] ?? ''}';
