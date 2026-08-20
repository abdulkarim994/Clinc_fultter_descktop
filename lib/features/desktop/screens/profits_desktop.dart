/// م178 — الأرباح لسطح المكتب: تخطيط مخصص عريض (لا استعارة مكبرة لواجهة
/// الهاتف — قرار المالك):
///
/// • ترويسة واحدة: شرائح الأقسام الثلاثة (الشهرية/السنوية/كشف الحساب)
///   بنمط شرائح المالية المكتبية + منتقيا السنة والشهر في الطرف المقابل.
/// • الشهرية: جدول أرباح العيادات وجدول الإجمالي العام **جنباً إلى جنب**.
/// • السنوية: شريط مؤشرات أفقي (إيراد/صافي/طبيب/عيادة/مصروفات/هامش مع
///   YoY) ثم جدول الأرباح والخسائر الشهري بعرضٍ مريح وبجواره عمود:
///   جدول العيادات سنوياً + مخطط الأشهر + قنوات القبض.
/// • كشف الحساب: القسم بكامل العرض (فلاتره ورأسه كما هما — st-*).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/js_compat.dart';
import '../../finance/finance_screen.dart'
    show financeRevProvider, financeSectionAllowed;
import '../../finance/profits_logic.dart';
import '../../finance/profits_section.dart' show frozenClinicProfitRows;
import '../../finance/profits_tables.dart';
import '../../finance/statement_section.dart' show StatementSection;
import '../../print/treatment_tables.dart' show formatNumber;

typedef _JMap = Map<String, Object?>;

/// القسم النشط في أرباح سطح المكتب (monthly/yearly/statement).
final desktopProfitsViewProvider =
    StateProvider<String>((ref) => 'monthly');

class DesktopProfitsScreen extends ConsumerStatefulWidget {
  const DesktopProfitsScreen({super.key});

  @override
  ConsumerState<DesktopProfitsScreen> createState() =>
      _DesktopProfitsScreenState();
}

class _DesktopProfitsScreenState
    extends ConsumerState<DesktopProfitsScreen> {
  String selectedYear = '${DateTime.now().year}';
  int monthIdx = DateTime.now().month - 1;

  @override
  Widget build(BuildContext context) {
    ref.watch(financeRevProvider);
    final repos = ref.watch(reposProvider);
    final records = repos.records.getAll();
    final prosthetics = repos.prosthetics.getAll();
    final debts = repos.debts.getAll();
    final cfg = ref.watch(appConfigProvider);
    final cur = ref.watch(currencyProvider);
    final clinics = ref.watch(clinicsProvider);
    // م180 — ميزة النسب: مطفأة ⇒ نسبة الطبيب الحية صفر (السجلات القديمة
    // بلقطاتها المجمّدة لا تتأثر) وتختفي أعمدة الحصص من كل الجداول.
    final ratesOn = ref.watch(ratesEnabledProvider);
    final doctorPct =
        ratesOn ? jsNumOr0(jsOr(cfg['doctorPct'], 50)) : 0;
    final years = profitYears(records, prosthetics);
    if (!years.contains(selectedYear)) selectedYear = years.first;

    final canProfits = financeSectionAllowed('profits');
    final canStatement = financeSectionAllowed('statement');
    final sections = [
      if (canProfits)
        (id: 'monthly', label: 'الأرباح الشهرية', icon: Icons.table_chart_rounded),
      if (canProfits)
        (id: 'yearly', label: 'الأرباح السنوية', icon: Icons.insights_rounded),
      if (canStatement)
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
    var view = ref.watch(desktopProfitsViewProvider);
    if (!sections.any((s) => s.id == view)) view = sections.first.id;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Row(children: [
          for (final s in sections)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                key: Key('desk-prof-${s.id}'),
                avatar: Icon(
                  s.icon,
                  size: 16,
                  color:
                      view == s.id ? Colors.white : BrandColors.brandIcon,
                ),
                label: Text(s.label),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: view == s.id ? Colors.white : BrandColors.ink,
                ),
                selected: view == s.id,
                selectedColor: BrandColors.brand600,
                backgroundColor: BrandColors.surface,
                showCheckmark: false,
                onSelected: (_) => ref
                    .read(desktopProfitsViewProvider.notifier)
                    .state = s.id,
              ),
            ),
          const Spacer(),
          if (view == 'monthly') ...[
            _pickerChip(
              icon: Icons.event_rounded,
              child: DropdownButton<int>(
                key: const Key('desk-prof-month'),
                value: monthIdx,
                underline: const SizedBox.shrink(),
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.goldDark),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: BrandColors.goldDark),
                items: [
                  for (var i = 0; i < 12; i++)
                    DropdownMenuItem(value: i, child: Text(arMonths[i])),
                ],
                onChanged: (v) =>
                    setState(() => monthIdx = v ?? monthIdx),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (view != 'statement')
            _pickerChip(
              icon: Icons.calendar_month_rounded,
              child: DropdownButton<String>(
                key: const Key('desk-prof-year'),
                value: selectedYear,
                underline: const SizedBox.shrink(),
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.goldDark),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: BrandColors.goldDark),
                items: [
                  for (final y in years)
                    DropdownMenuItem(value: y, child: Text(y)),
                ],
                onChanged: (v) =>
                    setState(() => selectedYear = v ?? selectedYear),
              ),
            ),
        ]),
      ),
      Expanded(
        child: switch (view) {
          'statement' => const StatementSection(),
          'yearly' => _yearlyBody(records, prosthetics, debts, cfg, cur,
              clinics, doctorPct, ratesOn),
          _ => _monthlyBody(records, prosthetics, debts, cfg, cur,
              clinics, doctorPct, ratesOn),
        },
      ),
    ]);
  }

  // ───────────── الشهرية: جدولان جنباً إلى جنب ─────────────

  Widget _monthlyBody(
    List<_JMap> records,
    List<_JMap> prosthetics,
    List<_JMap> debts,
    _JMap cfg,
    String cur,
    List<String> clinics,
    num doctorPct,
    bool ratesOn,
  ) {
    final repos = ref.read(reposProvider);
    final month = '$selectedYear-${'${monthIdx + 1}'.padLeft(2, '0')}';
    final frozen = frozenClinicProfitRows(cfg, month);
    final rows = [
      ...monthlyClinicRows(
        month,
        records: records,
        prosthetics: prosthetics,
        debts: debts,
        clinics: clinics,
        doctorPct: doctorPct,
      ),
      ...frozen,
    ];
    final grand =
        getMonthlyReport(records, prosthetics, debts, month, doctorPct);
    num fRev = 0, fDoc = 0, fClin = 0;
    for (final f in frozen) {
      fRev += f.revenue;
      fDoc += f.doctor;
      fClin += f.clinicShare;
    }
    final ex = repos.expenses.monthExpenseTotals(month);

    return ListView(
      key: const Key('desk-prof-monthly-body'),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: ProfitsClinicsTable(
              title:
                  'أرباح العيادات — ${arMonths[monthIdx]} $selectedYear',
              rows: rows,
              showDoctor: ratesOn,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ProfitsGrandTable(
              revenue: grand.grandTotal + fRev,
              doctor: grand.doctorTotal + fDoc,
              clinic: grand.clinicTotal + fClin,
              expenses: ex.total,
              // م187 — صفّا المختبرات (توأم نسخة الهاتف حرفياً).
              lab: grand.prosLabCost,
              // م188 — صفّ إيراد التحاليل (توأم نسخة الهاتف حرفياً).
              analyses: analysesRevenue(records, period: month),
              showDoctor: ratesOn,
            ),
          ),
        ]),
      ],
    );
  }

  // ───────────── السنوية: مؤشرات + جدولان وعمود جانبي ─────────────

  Widget _yearlyBody(
    List<_JMap> records,
    List<_JMap> prosthetics,
    List<_JMap> debts,
    _JMap cfg,
    String cur,
    List<String> clinics,
    num doctorPct,
    bool ratesOn,
  ) {
    final repos = ref.read(reposProvider);
    final n = formatNumber;
    num expensesOf(String m) => repos.expenses.monthExpenseTotals(m).total;
    List<ClinicProfitRow> frozenOf(String m) =>
        frozenClinicProfitRows(cfg, m);

    final rep = yearReport(
      selectedYear,
      records: records,
      prosthetics: prosthetics,
      debts: debts,
      doctorPct: doctorPct,
      expensesOf: expensesOf,
      frozenRowsOf: frozenOf,
    );
    final prevYear = '${int.parse(selectedYear) - 1}';
    final years = profitYears(records, prosthetics);
    final prev = years.contains(prevYear)
        ? yearReport(
            prevYear,
            records: records,
            prosthetics: prosthetics,
            debts: debts,
            doctorPct: doctorPct,
            expensesOf: expensesOf,
            frozenRowsOf: frozenOf,
          )
        : null;
    final clinicRows = yearlyClinicRows(
      selectedYear,
      records: records,
      prosthetics: prosthetics,
      debts: debts,
      clinics: clinics,
      doctorPct: doctorPct,
      frozenRowsOf: frozenOf,
    );

    return ListView(
      key: const Key('desk-prof-yearly-body'),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        // ── شريط المؤشرات الأفقي ──
        YearKpiCards(wide: true, items: [
          // م180 — الميزة مطفأة: الصافي = الإيراد − المصروفات (كله
          // للعيادة) وتغيب بطاقتا الطبيب/العيادة كلياً.
          YearKpi('إجمالي الإيراد', '${n(rep.revenue)} $cur',
              BrandColors.goldDark,
              keyId: 'prof-year-grand',
              yoy: prev == null ? null : yoyPct(rep.revenue, prev.revenue)),
          YearKpi(
              ratesOn ? 'صافي ربح العيادة' : 'صافي العيادة',
              '${n(ratesOn ? rep.net : rep.netOff)} $cur',
              BrandColors.brand900,
              keyId: 'prof-year-net',
              yoy: prev == null
                  ? null
                  : yoyPct(
                      // م188 — تعبيرٌ واحد (netOff) للمؤشر والجدول معاً:
                      // كان المؤشر يُغفل المعمل فيخالف سطر السنة.
                      ratesOn ? rep.net : rep.netOff,
                      ratesOn ? prev.net : prev.netOff)),
          // م190 — مؤشّرٌ يوحّد قراءة المؤشرات مع الجدول الجديد: الإيراد
          // أعلاه إجماليٌّ، وهذا صافيه بعد كلفة المعمل — وهو الرقم الذي
          // تُقسَم عليه النِّسَب فعلاً (طلب المالك).
          if (rep.lab > 0)
            YearKpi('صافي بعد المختبرات', '${n(rep.afterLab)} $cur',
                BrandColors.brand900,
                keyId: 'prof-year-after-lab',
                yoy: prev == null
                    ? null
                    : yoyPct(rep.afterLab, prev.afterLab)),
          if (ratesOn)
            YearKpi('ربح الطبيب', '${n(rep.doctor)} $cur',
                BrandColors.green,
                keyId: 'prof-year-doctor'),
          if (ratesOn)
            YearKpi('ربح العيادة', '${n(rep.clinic)} $cur',
                BrandColors.brand600,
                keyId: 'prof-year-clinic'),
          YearKpi('المصروفات', '${n(rep.expenses)} $cur', BrandColors.red,
              keyId: 'prof-year-exp'),
          YearKpi(
              'هامش الصافي',
              '${(ratesOn ? rep.marginPct : (rep.revenue == 0 ? 0 : rep.netOff / rep.revenue * 100)).toStringAsFixed(1)}٪',
              BrandColors.goldDark,
              keyId: 'prof-year-margin'),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // جدول الأرباح والخسائر — عمود الصدارة بعرض مريح.
          // م190 — نصيبه من العرض ازداد (6:3 بدل 5:4) لأن أعمدته صارت
          // تسعة: أعمدةٌ مريحة **بلا تمريرٍ أفقي** (اختيار المالك).
          Expanded(
              flex: 6,
              child: YearPnlTable(report: rep, showDoctor: ratesOn)),
          const SizedBox(width: 10),
          // العمود الجانبي: العيادات سنوياً + مخطط الأشهر.
          Expanded(
            flex: 3,
            child: Column(children: [
              ProfitsClinicsTable(
                title: 'أرباح العيادات — سنة $selectedYear',
                rows: clinicRows,
                dense: true,
                showDoctor: ratesOn,
              ),
              const SizedBox(height: 4),
              _yearChart(rep, n),
              // م179 — بطاقة «قنوات القبض» أُلغيت بالكامل (قرار المالك).
            ]),
          ),
        ]),
      ],
    );
  }

  /// مخطط أشهر السنة — من صفوف التقرير نفسها فلا انحراف.
  Widget _yearChart(YearReport rep, String Function(num) n) {
    final now = DateTime.now();
    final nowM = '${now.year}-${'${now.month}'.padLeft(2, '0')}';
    final maxBar = rep.months
        .fold<num>(1, (mx, m) => m.revenue > mx ? m.revenue : mx);
    String kFmt(num v) => v >= 1000
        ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k'
        : n(v);
    return Card(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(children: [
          Text('إيراد أشهر سنة ${rep.year}',
              style: TextStyle(fontSize: 11, color: BrandColors.mut)),
          const SizedBox(height: 8),
          SizedBox(
            height: 118,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final m in rep.months)
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (m.revenue >= maxBar && m.revenue > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(kFmt(m.revenue),
                                  style: const TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      color: BrandColors.goldDark)),
                            ),
                          Container(
                            height: m.revenue <= 0
                                ? 3.0
                                : 74 * (m.revenue / maxBar) + 6,
                            decoration: BoxDecoration(
                              color: m.revenue <= 0
                                  ? BrandColors.line
                                  : m.month == nowM
                                      ? BrandColors.gold
                                      : BrandColors.brand600
                                          .withValues(alpha: .35),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(arMonths[m.idx].substring(0, 3),
                              style: TextStyle(
                                  fontSize: 8.5,
                                  color: BrandColors.mut)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pickerChip({required IconData icon, required Widget child}) =>
      Container(
        padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
        decoration: BoxDecoration(
          color: BrandColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: BrandColors.gold, width: 1.2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: BrandColors.goldDark),
          const SizedBox(width: 4),
          child,
        ]),
      );
}
