/// ============================================================================
///  المصروفات — نسخة سطح المكتب: تخطيط عمودين احترافي
/// ============================================================================
///
///  (قرار المالك): ترقية من الهيكل المؤقت إلى تخطيط سطح مكتب حقيقي:
///    • العمود الأيمن: تبويبات الأقسام + قائمة/جدول بنود الشهر مع بحث فوري.
///    • العمود الأيسر: إجمالي الشهر + ملخّص الفئات + إجراءات الطباعة.
///    • الرواتب مدمجة تعمل كما هي (SalariesSection داخل عمود الأيمن).
///    • كل أفعال الهاتف تعمل: إضافة/حذف/تقرير — بواباتها نفسها.
///
///  منطق البيانات من expenses_screen.dart / expense_list_section.dart /
///  salaries_section.dart بلا أي تعديل — يُستهلَك كما هو.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/js_compat.dart' show getCurrentDate;
import '../../expenses/expense_list_section.dart';
import '../../expenses/expenses_report.dart' show buildDailyConsumption;
import '../../expenses/expenses_screen.dart'
    show expensesRefreshProvider, expensesSectionProvider;
import '../../expenses/salaries_section.dart';
import '../../print/print_service.dart' show loadPdfBrand, printOrSharePdf;
import '../../print/reports.dart' show simpleTablePdf;

// ── الأقسام ─────────────────────────────────────────────────────────────────

class _Section {
  const _Section(this.id, this.label, this.icon, this.category);
  final String id;
  final String label;
  final IconData icon;
  final String? category;
}

const _sections = <_Section>[
  _Section('salaries', 'الرواتب', Icons.groups_rounded, 'salary_withdrawal'),
  _Section('cleaning', 'التنظيف', Icons.cleaning_services_rounded, 'cleaning'),
  _Section('dental', 'المواد السنية', Icons.medical_services_rounded, 'dental'),
  _Section('other', 'أخرى', Icons.receipt_long_rounded, 'other'),
];

// ── الشاشة الرئيسية ──────────────────────────────────────────────────────────

class DesktopExpensesScreen extends ConsumerWidget {
  const DesktopExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    ref.watch(expensesRefreshProvider);
    final repos = ref.watch(reposProvider);
    final cur = ref.watch(currencyProvider);

    // إجمالي الشهر من الجدول الحقيقي.
    final monthRows = repos.expenses.getByMonth(month);
    final totalMonth = sumMoney(monthRows, 'amount');

    // مجاميع فرعية بالفئات.
    final catTotals = {
      for (final s in _sections.where((s) => s.id != 'salaries'))
        s: repos.expenses.categoryTotal(month, s.category ?? ''),
    };
    final salariesTotal =
        repos.expenses.categoryTotal(month, 'salary_withdrawal');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── العمود الأيمن: قائمة الأقسام + المحتوى ─────────────────────
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // شريط الأقسام.
              _DeskSectionBar(),
              Divider(height: 1, color: BrandColors.line),
              // محتوى القسم النشط.
              Expanded(
                child: Consumer(
                  builder: (ctx, ref2, _) {
                    final section = ref2.watch(expensesSectionProvider);
                    final sec =
                        _sections.firstWhere((s) => s.id == section);
                    if (sec.id == 'salaries') {
                      return const SalariesSection();
                    }
                    return ExpenseListSection(
                        category: sec.category ?? 'other',
                        label: sec.label);
                  },
                ),
              ),
            ],
          ),
        ),

        // ── الفاصل ──────────────────────────────────────────────────────
        Container(width: 1, color: BrandColors.line),

        // ── العمود الأيسر: الإجمالي + ملخّص + طباعة ────────────────────
        SizedBox(
          width: 280,
          child: _DeskExpensesSidebar(
            month: month,
            total: totalMonth,
            cur: cur,
            catTotals: catTotals,
            salariesTotal: salariesTotal,
          ),
        ),
      ],
    );
  }
}

// ── شريط الأقسام المكتبي ────────────────────────────────────────────────────

class _DeskSectionBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(expensesSectionProvider);
    return Container(
      color: BrandColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final s in _sections)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: _SectionChip(
                  section: s,
                  on: s.id == active,
                  onTap: () =>
                      ref.read(expensesSectionProvider.notifier).state = s.id,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.section,
    required this.on,
    required this.onTap,
  });

  final _Section section;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? BrandColors.brand : BrandColors.surface2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(section.icon,
                  size: 15,
                  color: on ? BrandColors.goldLight : BrandColors.mut),
              const SizedBox(width: 6),
              Text(section.label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: on ? Colors.white : BrandColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── العمود الأيسر: الإجمالي + ملخّص الفئات + الطباعة ──────────────────────

class _DeskExpensesSidebar extends ConsumerWidget {
  const _DeskExpensesSidebar({
    required this.month,
    required this.total,
    required this.cur,
    required this.catTotals,
    required this.salariesTotal,
  });

  final String month;
  final num total;
  final String cur;
  final Map<_Section, num> catTotals;
  final num salariesTotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // بطاقة الإجمالي.
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: BrandColors.brandGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      color: BrandColors.goldLight, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('إجمالي مصروفات $month',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: BrandColors.goldLight,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  total.toStringAsFixed(2),
                  key: const Key('expenses-total'),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(cur,
                    style: const TextStyle(
                        color: BrandColors.goldLight,
                        fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ملخّص الفئات.
          Container(
            decoration: BoxDecoration(
              color: BrandColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: BrandColors.line),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(children: [
                    Icon(Icons.pie_chart_outline_rounded,
                        size: 14, color: BrandColors.brand600),
                    const SizedBox(width: 6),
                    Text('ملخّص الأقسام',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.brandText)),
                  ]),
                ),
                Divider(height: 1, color: BrandColors.line),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    // الرواتب.
                    _CatRow(
                        icon: Icons.groups_rounded,
                        label: 'الرواتب',
                        value: salariesTotal,
                        cur: cur,
                        color: BrandColors.brand600),
                    // باقي الأقسام.
                    for (final entry in catTotals.entries)
                      _CatRow(
                          icon: entry.key.icon,
                          label: entry.key.label,
                          value: entry.value,
                          cur: cur,
                          color: BrandColors.goldDark),
                  ]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // أزرار الطباعة.
          Text('التقارير والطباعة',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: BrandColors.mut2)),
          const SizedBox(height: 8),
          _PrintBtn(
            key: const Key('expenses-print-month'),
            icon: Icons.calendar_month_rounded,
            label: 'طباعة مصروفات $month',
            onTap: () => _printMonth(context, ref),
          ),
          const SizedBox(height: 6),
          _PrintBtn(
            key: const Key('expenses-print-today'),
            icon: Icons.print_rounded,
            label: 'طباعة استهلاك اليوم',
            onTap: () => _printToday(context, ref),
          ),
        ],
      ),
    );
  }

  // ── طباعة مصروفات الشهر (نفس دالة expenses_screen.dart) ─────────────────

  Future<void> _printMonth(BuildContext context, WidgetRef ref) async {
    final repos = ref.read(reposProvider);
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
            content: Text(
                items.isEmpty ? 'لا مصروفات هذا الشهر — $msg' : msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذّرت الطباعة: $e')));
      }
    }
  }

  // ── طباعة استهلاك اليوم (نفس دالة expenses_screen.dart) ─────────────────

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
            content:
                Text(items.isEmpty ? 'لا مصروفات اليوم — $msg' : msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذّرت الطباعة: $e')));
      }
    }
  }
}

// ── صف فئة مصروف ─────────────────────────────────────────────────────────────

class _CatRow extends StatelessWidget {
  const _CatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.cur,
    required this.color,
  });

  final IconData icon;
  final String label;
  final num value;
  final String cur;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12, color: BrandColors.brandText))),
        Text(
          '${value.toStringAsFixed(2)} $cur',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ]),
    );
  }
}

// ── زر طباعة ─────────────────────────────────────────────────────────────────

class _PrintBtn extends StatelessWidget {
  const _PrintBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: BrandColors.brandText,
        side: BorderSide(color: BrandColors.line),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        alignment: AlignmentDirectional.centerStart,
      ),
      icon: Icon(icon, size: 16, color: BrandColors.brandIcon),
      label: Text(label,
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w700)),
    );
  }
}
