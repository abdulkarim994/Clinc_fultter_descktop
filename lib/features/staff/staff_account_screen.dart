/// م124 — «حساب الموظف»: بطاقة الجلسة الحالية + تبديل المستخدم/الخروج.
///
///  قرار المالك (ترتيب الهيدر): حُذف زر المستخدم من الترويسة، وصارت
///  وظائف الحساب هنا — زر الترس يفتح للإدارة شاشة الإعدادات الكاملة
///  (وبأعلاها هذه البطاقة)، ولغير الإدارة [StaffAccountScreen] المصغرة
///  التي لا تعرض أي إعدادٍ آخر إطلاقاً.
///
///  كلا الفعلين يُسجَّل في سجل النشاط **قبل** مسح الجلسة فيحمل القيد
///  ختم `by` لصاحبها، وتُغلق الشاشات المدفوعة للعودة لجذر الصدفة حيث
///  تظهر شاشة الدخول.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/audit/audit_trail.dart' show recordAudit;
import 'staff_session.dart';

/// بطاقة الحساب المشتركة — تُعرض أعلى الإعدادات (إدارة) وفي الشاشة
/// المصغرة (موظف).
class StaffAccountCard extends ConsumerWidget {
  const StaffAccountCard({super.key});

  void _end(BuildContext context, WidgetRef ref, String action) {
    final u = kCurrentStaff;
    // القيد قبل مسح الجلسة كي يحمل ختم صاحبها.
    recordAudit(ref.read(reposProvider).db,
        action: action, entity: 'staff', entityId: '${u?['id'] ?? ''}');
    // العودة لجذر الصدفة أولاً — فبوابة الدخول تعيش تحت الشاشات المدفوعة.
    Navigator.of(context).popUntil((r) => r.isFirst);
    applyStaffSession(null);
    ref.read(currentStaffProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(currentStaffProvider);
    final shift = '${u?['shift'] ?? ''}'.trim();
    final role = u?['role'] == 'admin' ? 'إدارة' : 'موظف';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: BrandColors.brandGradient,
              shape: BoxShape.circle,
              border: Border.all(
                  color: const Color.fromRGBO(201, 162, 75, .4)),
            ),
            child: Icon(Icons.account_circle_rounded,
                size: 26, color: BrandColors.goldLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${u?['name'] ?? '—'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.brandText)),
                Text(shift.isEmpty ? role : '$role • وردية $shift',
                    style:
                        TextStyle(fontSize: 11.5, color: BrandColors.mut)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('acct-switch'),
              style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.brand600,
                  foregroundColor: Colors.white),
              onPressed: () => _end(context, ref, 'staff.switch'),
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('تبديل المستخدم'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              key: const Key('acct-logout'),
              style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.red,
                  foregroundColor: Colors.white),
              onPressed: () => _end(context, ref, 'staff.logout'),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('تسجيل الخروج'),
            ),
          ),
        ]),
      ],
    );
  }
}

/// الشاشة المصغرة لغير الإدارة: بطاقة الحساب فقط — لا إعدادات.
class StaffAccountScreen extends StatelessWidget {
  const StaffAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.paper,
      appBar: AppBar(
        title: const Text('حساب الموظف'),
        backgroundColor: BrandColors.brand,
        foregroundColor: BrandColors.goldLight,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: BrandColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: BrandColors.line),
                ),
                child: const StaffAccountCard(),
              ),
              const SizedBox(height: 10),
              Text(
                'بقية الإعدادات تديرها الإدارة حصراً.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: BrandColors.mut2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
