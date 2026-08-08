/// م119 — بوابة فرض الصلاحيات (المرحلة 2 من نظام الموظفين).
///
///  • [staffAllowed]: فحصٌ صامت لصلاحية الجلسة الحالية (الإدارة كل شيء،
///    ولا جلسة — كما في الاختبارات النقية — يعني سماحاً كي لا يتغير سلوك
///    المنطق خارج التطبيق الحي).
///  • [gateStaff]: فحصٌ للواجهات — عند المنع يعرض رسالة موحدة باسم
///    الصلاحية الناقصة ويعيد false.
///  • [requestAdminSignature]: «توقيع الإدارة» للعمليات الحساسة (قرار
///    المالك: حذف مصروف الدرج والسحوبات يتطلب الإدارة حصراً لمنع
///    التلاعب): حوار كلمة مرور حسابِ إدارةٍ نشط، يتحقق عبر مسار الدخول
///    نفسه (فيرث قفلَ المحاولات الفاشلة المتصاعد)، ويسجل النجاح والفشل
///    في سجل التدقيق باسمي الموظف والإدارة معاً.
library;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/audit/audit_trail.dart' show recordAudit;
import '../../data/db/local_db.dart' show LocalDb;
import '../../data/repositories/settings_repository.dart';
import 'staff_session.dart';
import 'staff_store.dart';

/// تسمية الصلاحية للعرض في رسالة المنع.
String staffPermLabel(String perm) {
  for (final p in kStaffPerms) {
    if (p.key == perm) return p.label;
  }
  return perm;
}

/// هل تملك الجلسة الحالية الصلاحية [perm]؟
/// بلا جلسة (اختبارات/أدوات خارجية) يُسمح — البوابة الفعلية شاشة الدخول.
bool staffAllowed(String perm) =>
    kCurrentStaff == null || staffCan(kCurrentStaff, perm);

/// فحص صلاحية مع رسالة منعٍ موحدة عند الرفض.
bool gateStaff(BuildContext context, String perm) {
  if (staffAllowed(perm)) return true;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('تتطلب صلاحية «${staffPermLabel(perm)}» — راجع الإدارة'),
    backgroundColor: BrandColors.red,
  ));
  return false;
}

/// «توقيع الإدارة» — يعيد اسم الإدارة الموقِّعة أو null عند الإلغاء/الفشل.
///
/// الإدارة الحالية توقّع بنفسها بلا حوار. الموظف يحتاج كلمة مرور حسابِ
/// إدارةٍ نشط (تختارها الإدارة وتكتبها بنفسها على الجهاز).
Future<String?> requestAdminSignature(
  BuildContext context,
  SettingsRepository settings,
  LocalDb db, {
  required String reason,
}) async {
  if (staffIsAdmin(kCurrentStaff)) return currentStaffName();
  final store = StaffStore(settings);
  // الوضع الفردي (نظام الموظفين غير مُفعَّل): المستخدم هو المالك ضمناً
  // بصلاحياتٍ كاملة، فلا توقيع إدارةٍ مطلوب (لا حساب إدارةٍ أصلاً).
  if (!store.hasAnyUser) return 'المالك';
  final admins =
      [for (final u in store.listActive()) if (u['role'] == 'admin') u];
  if (admins.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا يوجد حساب إدارة نشط — لا يمكن إتمام العملية')));
    return null;
  }
  String adminId = '${admins.first['id']}';
  final passCtl = TextEditingController();
  String? error;
  bool busy = false;
  final signed = await showDialog<Map<String, Object?>>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setSt) => AlertDialog(
        title: const Text('توقيع الإدارة مطلوب',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(reason,
                style: TextStyle(
                    fontSize: 12.5, height: 1.6, color: BrandColors.mut)),
            const SizedBox(height: 12),
            if (admins.length > 1)
              DropdownButtonFormField<String>(
                key: const Key('admin-sign-user'),
                isExpanded: true,
                initialValue: adminId,
                decoration: const InputDecoration(labelText: 'حساب الإدارة'),
                items: [
                  for (final a in admins)
                    DropdownMenuItem(
                        value: '${a['id']}', child: Text('${a['name']}')),
                ],
                onChanged: (v) => setSt(() => adminId = v ?? adminId),
              ),
            if (admins.length > 1) const SizedBox(height: 10),
            TextField(
              key: const Key('admin-sign-pass'),
              controller: passCtl,
              obscureText: true,
              autofocus: true,
              decoration:
                  const InputDecoration(labelText: 'كلمة مرور الإدارة'),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: BrandColors.red)),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx),
              child: const Text('إلغاء')),
          FilledButton(
            key: const Key('admin-sign-ok'),
            style:
                FilledButton.styleFrom(backgroundColor: BrandColors.brand600),
            onPressed: busy
                ? null
                : () async {
                    setSt(() {
                      busy = true;
                      error = null;
                    });
                    // مهلة قصيرة ترسم الانشغال قبل PBKDF2 الثقيل عمداً.
                    await Future<void>.delayed(
                        const Duration(milliseconds: 30));
                    final a = admins
                        .firstWhere((e) => '${e['id']}' == adminId);
                    final res =
                        store.login('${a['username']}', passCtl.text);
                    if (!dctx.mounted) return;
                    if (res.status == StaffLoginStatus.ok) {
                      Navigator.pop(dctx, res.user);
                      return;
                    }
                    recordAudit(db,
                        action: 'admin.sign.fail',
                        entity: 'staff',
                        entityId: '${a['id']}',
                        detail: {
                          'admin': '${a['username']}',
                          'reason': reason,
                        });
                    setSt(() {
                      busy = false;
                      error = res.status == StaffLoginStatus.locked
                          ? 'الحساب مقفول مؤقتاً — أعد المحاولة بعد ${res.lockedForSeconds} ثانية'
                          : 'كلمة المرور خاطئة';
                    });
                  },
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('توقيع'),
          ),
        ],
      ),
    ),
  );
  passCtl.dispose();
  if (signed == null) return null;
  recordAudit(db,
      action: 'admin.sign',
      entity: 'staff',
      entityId: '${signed['id']}',
      detail: {
        'admin': '${signed['username']}',
        'reason': reason,
      });
  return '${signed['name']}';
}
