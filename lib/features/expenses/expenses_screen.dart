/// شاشة «المصروفات» — تُفتح من قائمة «إضافي».
///
/// هذه الدفعة (المرحلة 2): الهيكل + طبقة البيانات فقط. الرأس يعرض إجمالي
/// الشهر المختار (يقرأ جدول `expenses` الجديد فعلاً — إثباتُ عمل الكيان)،
/// وشريط الأقسام الأربعة حيّ، وكل قسم بحالة فارغة. المنطق الكامل يأتي:
///   • الرواتب (موظفون + سحوبات + متبقٍّ شهري) — المرحلة 3.
///   • التنظيف/المواد السنية/أخرى + الطباعة اليومية — المرحلة 4.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart' show getCurrentDate;
import '../print/print_service.dart' show loadPdfBrand, printOrSharePdf;
import '../print/reports.dart' show simpleTablePdf;
import 'expense_list_section.dart';
import 'expenses_report.dart' show buildDailyConsumption;
import 'salaries_section.dart';

/// القسم النشط داخل شاشة المصروفات.
final expensesSectionProvider = StateProvider<String>((ref) => 'salaries');

/// عدّاد إعادة بناء — يُحرَّك بعد أي تعديل على المصروفات/الرواتب لأن
/// المستودعات غير تفاعلية (تُعاد القراءة عند كل بناء).
final expensesRefreshProvider = StateProvider<int>((ref) => 0);

class _Section {
  const _Section(this.id, this.label, this.icon, this.category);
  final String id;
  final String label;
  final IconData icon;

  /// فئة `expenses.category` المقابلة (null لقسم الرواتب — مصدره مختلف).
  final String? category;
}

const _sections = <_Section>[
  _Section('salaries', 'الرواتب', Icons.groups_rounded, 'salary_withdrawal'),
  _Section('cleaning', 'التنظيف', Icons.cleaning_services_rounded, 'cleaning'),
  _Section('dental', 'المواد السنية', Icons.medical_services_rounded, 'dental'),
  _Section('other', 'أخرى', Icons.receipt_long_rounded, 'other'),
];

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final section = ref.watch(expensesSectionProvider);
    ref.watch(expensesRefreshProvider);
    final repos = ref.watch(reposProvider);
    // يقرأ الجدول الجديد فعلياً — يثبت أن الكيان أُنشئ وأصبح قابلاً للاستعلام.
    final monthRows = repos.expenses.getByMonth(month);
    final total = sumMoney(monthRows, 'amount');

    return Scaffold(
      backgroundColor: BrandColors.paper,
      appBar: AppBar(
        title: const Text('المصروفات'),
        backgroundColor: BrandColors.brand,
        foregroundColor: BrandColors.goldLight,
        actions: [
          IconButton(
            key: const Key('expenses-print-month'),
            tooltip: 'طباعة مصروفات الشهر',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () => _printMonth(context, ref),
          ),
          IconButton(
            key: const Key('expenses-print-today'),
            tooltip: 'طباعة استهلاك اليوم',
            icon: const Icon(Icons.print_rounded),
            onPressed: () => _printToday(context, ref),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              _TotalHeader(month: month, total: total),
              _SectionBar(active: section),
              Expanded(
                child: Builder(
                  builder: (_) {
                    final sec = _sections.firstWhere((s) => s.id == section);
                    if (sec.id == 'salaries') return const SalariesSection();
                    return ExpenseListSection(
                        category: sec.category ?? 'other', label: sec.label);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// رأس الإجمالي — إجمالي مصروفات الشهر المختار (كل الأقسام، شاملاً السحوبات).
class _TotalHeader extends StatelessWidget {
  const _TotalHeader({required this.month, required this.total});
  final String month;
  final num total;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: BrandColors.brandGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_rounded,
              color: BrandColors.goldLight, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('إجمالي مصروفات $month',
                    style: const TextStyle(
                        color: BrandColors.goldLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(total.toStringAsFixed(2),
                    key: const Key('expenses-total'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// شريط الأقسام الأربعة.
class _SectionBar extends ConsumerWidget {
  const _SectionBar({required this.active});
  final String active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          for (final s in _sections)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _SectionChip(
                section: s,
                on: s.id == active,
                onTap: () =>
                    ref.read(expensesSectionProvider.notifier).state = s.id,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip(
      {required this.section, required this.on, required this.onTap});
  final _Section section;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? BrandColors.brand : BrandColors.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: on ? BrandColors.brand : BrandColors.line),
          ),
          child: Row(
            children: [
              Icon(section.icon,
                  size: 16,
                  color: on ? BrandColors.goldLight : BrandColors.mut),
              const SizedBox(width: 6),
              Text(section.label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: on ? Colors.white : BrandColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

/// طباعة مصروفات الشهر المختار — كل بنود الشهر (شاملاً سحوبات الرواتب) في
/// جدول RTL عربي، بنفس مسار الطباعة/المشاركة/الحفظ المُدقَّق.
Future<void> _printMonth(BuildContext context, WidgetRef ref) async {
  final repos = ref.read(reposProvider);
  final month = ref.read(selectedMonthProvider);
  final items = repos.expenses.getByMonth(month);
  final data =
      buildDailyConsumption(items, currency: ref.read(currencyProvider));
  final centerName = ref.read(centerNameProvider);
  try {
    final fonts = await loadPdfBrand(ref);
    final bytes = await simpleTablePdf(
      fonts,
      title: 'مصروفات الشهر $month',
      subtitle: centerName,
      headers: data.headers,
      rows: data.rows,
      totRow: data.totRow,
    );
    final msg = await printOrSharePdf(
      ref.read(dbDirProvider),
      bytes,
      'expenses_month_$month.pdf',
      auditDb: repos.db,
      auditEntity: 'expenses',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(items.isEmpty ? 'لا مصروفات هذا الشهر — $msg' : msg)));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّرت الطباعة: $e')));
    }
  }
}

/// طباعة استهلاك اليوم — كل بنود مصروفات تاريخ اليوم (شاملاً سحوبات الرواتب)
/// في جدول RTL عربي عبر [simpleTablePdf]، ثم طباعة/مشاركة/حفظ عبر
/// [printOrSharePdf] (الذي يسجّل حدث التصدير في التدقيق).
Future<void> _printToday(BuildContext context, WidgetRef ref) async {
  final repos = ref.read(reposProvider);
  final today = getCurrentDate();
  final items = repos.expenses.getByDay(today);
  final data =
      buildDailyConsumption(items, currency: ref.read(currencyProvider));
  final centerName = ref.read(centerNameProvider);
  try {
    final fonts = await loadPdfBrand(ref);
    final bytes = await simpleTablePdf(
      fonts,
      title: 'استهلاك العيادة اليوم',
      subtitle: '$centerName • $today',
      headers: data.headers,
      rows: data.rows,
      totRow: data.totRow,
    );
    final msg = await printOrSharePdf(
      ref.read(dbDirProvider),
      bytes,
      'expenses_$today.pdf',
      auditDb: repos.db,
      auditEntity: 'expenses',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(items.isEmpty ? 'لا مصروفات اليوم — $msg' : msg)));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّرت الطباعة: $e')));
    }
  }
}
