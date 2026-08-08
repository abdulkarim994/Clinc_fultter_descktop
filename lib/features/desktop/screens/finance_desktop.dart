/// نسخة سطح المكتب — «المالية» بعد رفع الخزينة والديون إلى تبويبين
/// مستقلين: بقي هنا قسمان — الأرباح وكشف الحساب — بمبدّل شرائح علوي
/// (لا قائمة بطاقات وسيطة كالهاتف: النقرة الأولى تعرض المحتوى مباشرة).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/theme/app_theme.dart';
import '../../finance/profits_section.dart' show ProfitsSection;
import '../../finance/statement_section.dart' show StatementSection;
import '../../staff/staff_session.dart'
    show currentStaffProvider, staffCan, staffIsAdmin;
import '_mobile_host.dart';

/// القسم النشط في مالية سطح المكتب (profits/statement).
final desktopFinanceSectionProvider =
    StateProvider<String>((ref) => 'profits');

class DesktopFinanceScreen extends ConsumerWidget {
  const DesktopFinanceScreen({super.key});

  bool _allowed(Map<String, Object?>? u, String id) {
    if (u == null || staffIsAdmin(u)) return true;
    final legacy = staffCan(u, 'finance.view');
    return switch (id) {
      'profits' => staffCan(u, 'profits.view') || legacy,
      'statement' => staffCan(u, 'statement.view') || legacy,
      _ => legacy,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(currentStaffProvider);
    final sections = [
      if (_allowed(u, 'profits'))
        (id: 'profits', label: 'الأرباح', icon: Icons.trending_up_rounded),
      if (_allowed(u, 'statement'))
        (
          id: 'statement',
          label: 'كشف الحساب',
          icon: Icons.receipt_long_rounded
        ),
    ];
    if (sections.isEmpty) {
      return Center(
        child: Text('لا صلاحية لعرض الأقسام المالية',
            style: TextStyle(color: BrandColors.mut)),
      );
    }
    var active = ref.watch(desktopFinanceSectionProvider);
    if (!sections.any((s) => s.id == active)) active = sections.first.id;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Row(
            children: [
              for (final s in sections)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(
                    key: Key('desk-fin-${s.id}'),
                    avatar: Icon(
                      s.icon,
                      size: 16,
                      color: active == s.id
                          ? Colors.white
                          : BrandColors.brandIcon,
                    ),
                    label: Text(s.label),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color:
                          active == s.id ? Colors.white : BrandColors.ink,
                    ),
                    selected: active == s.id,
                    selectedColor: BrandColors.brand600,
                    backgroundColor: BrandColors.surface,
                    showCheckmark: false,
                    onSelected: (_) => ref
                        .read(desktopFinanceSectionProvider.notifier)
                        .state = s.id,
                  ),
                ),
              const Spacer(),
            ],
          ),
        ),
        Expanded(
          child: MobileHost(
            maxWidth: 860,
            child: active == 'statement'
                ? const StatementSection()
                : const ProfitsSection(),
          ),
        ),
      ],
    );
  }
}
