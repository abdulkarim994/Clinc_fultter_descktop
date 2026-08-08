/// م120 — «سجل النشاط»: شاشة سجل التدقيق للإدارة حصراً (المرحلة 3).
///
///  تقرأ قيود `audit_events` — قيودٌ **تُضاف ولا تُعدَّل ولا تُحذف**
///  (سياسة الجدول محلياً وخادمياً إدراجٌ فقط) — بفلاتر: الموظف (ختم
///  `by` الذي تضيفه recordAudit تلقائياً من الجلسة)، فئة العملية،
///  والمدى الزمني. القيم العربية في detail محجوبة أصلاً بحاجب PHI،
///  فالعرض يبني ملخصاً من الحقول الناجية (المبالغ، أسماء الدخول، النوع).
library;

import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/display_prefs.dart' show appDigits, formatClockHm;
import '../../core/theme/app_theme.dart';
import 'staff_store.dart';

/// فئات الفلترة — بادئات أفعال سجل التدقيق.
const List<({String id, String label, List<String> prefixes})>
    kAuditCategories = [
  (id: 'all', label: 'كل العمليات', prefixes: []),
  (id: 'auth', label: 'الدخول والحسابات', prefixes: ['staff.', 'auth.']),
  (id: 'sign', label: 'توقيعات الإدارة', prefixes: ['admin.sign']),
  (
    id: 'records',
    label: 'السجلات والزيارات',
    prefixes: ['record.', 'edit.record', 'delete.record']
  ),
  (
    id: 'money',
    label: 'المصروفات والسحوبات',
    prefixes: ['expense.', 'salary.', 'employee.']
  ),
  (id: 'day', label: 'قفل اليوم والورديات', prefixes: ['day.', 'shift.']),
  (id: 'export', label: 'الطباعة والتصدير', prefixes: ['export.']),
  (id: 'view', label: 'الاطّلاع', prefixes: ['view.']),
];

/// تسمية عربية لفعل التدقيق.
String auditActionLabel(String a) => switch (a) {
      'staff.setup' => 'تأسيس حساب الإدارة',
      'staff.login' => 'دخول موظف',
      'staff.login.fail' => 'محاولة دخول فاشلة',
      'staff.switch' => 'تبديل مستخدم',
      'staff.logout' => 'خروج موظف',
      'staff.add' => 'إضافة موظف',
      'staff.edit' => 'تعديل موظف/صلاحيات',
      'admin.sign' => 'توقيع إدارة',
      'admin.sign.fail' => 'توقيع إدارة فاشل',
      'expense.add' => 'إضافة مصروف',
      'expense.edit' => 'تعديل مصروف',
      'expense.delete' => 'حذف مصروف',
      'salary.withdraw' => 'سحب راتب',
      'salary.withdraw.delete' => 'حذف سحب راتب',
      'employee.add' => 'إضافة موظف رواتب',
      'employee.edit' => 'تعديل موظف رواتب',
      'employee.delete' => 'حذف موظف رواتب',
      'shift.report' => 'تقرير تسليم وردية',
      'day.close' => 'قفل اليوم',
      'day.reopen' => 'إعادة فتح اليوم',
      'record.add' => 'إضافة سجل',
      'record.edit' => 'تعديل سجل',
      'record.replace' => 'تعديل سجل (استبدال)',
      'edit.record' => 'تعديل سجل',
      'delete.record' => 'حذف سجل',
      'export.pdf' => 'طباعة/تصدير PDF',
      'view.patient' => 'فتح ملف مريض',
      'view.xray' => 'عرض صورة أشعة',
      'auth.login' => 'دخول الحساب',
      'auth.logout' => 'خروج الحساب',
      'auth.unlock' => 'فتح القفل',
      'auth.account_switch' => 'تبديل الحساب',
      _ => a,
    };

class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() =>
      _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen> {
  String staffFilter = ''; // '' = الكل (اسم دخول)
  String catFilter = 'all';
  int daysBack = 7; // 1 اليوم، 7 أسبوع، 30 شهر، 0 الكل

  @override
  Widget build(BuildContext context) {
    final repos = ref.watch(reposProvider);
    final staff = StaffStore(repos.settings).listAll();
    final nameOf = {
      for (final u in staff) '${u['username']}': '${u['name']}'
    };

    // القراءة: مدى زمني + حد سخي ثم فلترة الفئة/الموظف في الذاكرة
    // (بضع مئات القيود — أرخص من فهارس إضافية).
    final since = daysBack == 0
        ? 0
        : DateTime.now()
            .subtract(Duration(days: daysBack))
            .millisecondsSinceEpoch;
    final rows = repos.db.query(
      'SELECT * FROM audit_events WHERE at >= ? ORDER BY at DESC LIMIT 600',
      [since],
    );
    final cat = kAuditCategories.firstWhere((c) => c.id == catFilter);
    final filtered = <Map<String, Object?>>[];
    for (final r in rows) {
      final action = '${r['action'] ?? ''}';
      if (cat.prefixes.isNotEmpty &&
          !cat.prefixes.any(action.startsWith)) {
        continue;
      }
      Map<String, Object?> detail = const {};
      final dRaw = r['detail'];
      if (dRaw is String && dRaw.isNotEmpty) {
        try {
          final d = jsonDecode(dRaw);
          if (d is Map) detail = Map<String, Object?>.from(d);
        } catch (_) {/* قيد قديم بغير JSON */}
      }
      final by = '${detail['by'] ?? ''}';
      if (staffFilter.isNotEmpty && by != staffFilter) continue;
      filtered.add({...Map<String, Object?>.from(r), '_detail': detail});
    }

    return Scaffold(
      backgroundColor: BrandColors.paper,
      appBar: AppBar(
        title: const Text('سجل النشاط'),
        backgroundColor: BrandColors.brand,
        foregroundColor: BrandColors.goldLight,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              // ── الفلاتر ──
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const Key('act-staff-filter'),
                          isExpanded: true,
                          initialValue: staffFilter,
                          decoration:
                              const InputDecoration(labelText: 'الموظف'),
                          items: [
                            const DropdownMenuItem(
                                value: '', child: Text('كل الموظفين')),
                            for (final u in staff)
                              DropdownMenuItem(
                                  value: '${u['username']}',
                                  child: Text('${u['name']}',
                                      style: const TextStyle(
                                          fontSize: 13))),
                          ],
                          onChanged: (v) =>
                              setState(() => staffFilter = v ?? ''),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: const Key('act-cat-filter'),
                          isExpanded: true,
                          initialValue: catFilter,
                          decoration:
                              const InputDecoration(labelText: 'العملية'),
                          items: [
                            for (final c in kAuditCategories)
                              DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.label,
                                      style: const TextStyle(
                                          fontSize: 13))),
                          ],
                          onChanged: (v) =>
                              setState(() => catFilter = v ?? 'all'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      key: const Key('act-range'),
                      style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 11.5)),
                      segments: const [
                        ButtonSegment(value: 1, label: Text('اليوم')),
                        ButtonSegment(value: 7, label: Text('أسبوع')),
                        ButtonSegment(value: 30, label: Text('شهر')),
                        ButtonSegment(value: 0, label: Text('الكل')),
                      ],
                      selected: {daysBack},
                      onSelectionChanged: (v) =>
                          setState(() => daysBack = v.first),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(children: [
                  Icon(Icons.verified_user_rounded,
                      size: 13, color: BrandColors.mut2),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                        'قيود تُضاف ولا تُعدَّل ولا تُحذف — '
                        '${appDigits('${filtered.length}')} قيد',
                        style: TextStyle(
                            fontSize: 10.5, color: BrandColors.mut2)),
                  ),
                ]),
              ),
              // ── القائمة ──
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text('لا قيود مطابقة للفلاتر',
                            style: TextStyle(
                                fontSize: 13, color: BrandColors.mut)))
                    : ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(14, 8, 14, 24),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) =>
                            _entry(filtered[i], nameOf),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entry(Map<String, Object?> r, Map<String, String> nameOf) {
    final action = '${r['action'] ?? ''}';
    final detail = r['_detail'] as Map<String, Object?>? ?? const {};
    final by = '${detail['by'] ?? ''}';
    final byName = by.isEmpty ? '' : (nameOf[by] ?? by);
    final at = (r['at'] as num?)?.toInt() ?? 0;
    final dt = DateTime.fromMillisecondsSinceEpoch(at);
    final date =
        '${dt.year}-${'${dt.month}'.padLeft(2, '0')}-${'${dt.day}'.padLeft(2, '0')}';
    final destructive = action.contains('delete') ||
        action.contains('fail') ||
        action == 'day.reopen';
    // ملخص الحقول الناجية من حاجب PHI (المبالغ، أسماء الدخول، الأنواع).
    final bits = <String>[];
    final amount = detail['amount'];
    if (amount is num) bits.add('المبلغ ${appDigits('$amount')}');
    final admin = '${detail['admin'] ?? ''}';
    if (admin.isNotEmpty) {
      bits.add('بتوقيع: ${nameOf[admin] ?? admin}');
    }
    final username = '${detail['username'] ?? ''}';
    if (username.isNotEmpty && username != by) bits.add('الحساب: $username');
    final cat = '${detail['category'] ?? ''}';
    if (cat.isNotEmpty && !cat.contains('<')) bits.add(cat);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.line),
      ),
      child: Row(
        children: [
          Icon(
            destructive
                ? Icons.warning_amber_rounded
                : Icons.history_rounded,
            size: 18,
            color: destructive ? BrandColors.red : BrandColors.goldDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(auditActionLabel(action),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: destructive
                            ? BrandColors.red
                            : BrandColors.brandText)),
                if (byName.isNotEmpty || bits.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                        [
                          if (byName.isNotEmpty) 'الموظف: $byName',
                          ...bits,
                        ].join(' • '),
                        style: TextStyle(
                            fontSize: 11, color: BrandColors.mut)),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatClockHm('${dt.hour}:${dt.minute}'),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: BrandColors.brandText)),
              Text(appDigits(date),
                  style:
                      TextStyle(fontSize: 10, color: BrandColors.mut2)),
            ],
          ),
        ],
      ),
    );
  }
}
