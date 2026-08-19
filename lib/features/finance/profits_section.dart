/// م178 — قسم الأرباح المعاد بناؤه (قرار المالك):
///
/// • ثلاثة أقسام علوية بدل قسمين: **الشهرية / السنوية / كشف الحساب**
///   (كشف الحساب انتقل من قسمٍ مالي مستقل إلى الحبة الثالثة هنا؛ روابط
///   م108 القديمة statement تفتح هذا القسم على حبته مباشرة).
/// • الشهرية: نفس المنطق حرفياً لكن العرض **جداول منظمة** بهوية جداول
///   الخزينة (م154) بدل البطاقات — جدول أرباح العيادات + جدول الإجمالي
///   العام وفيه صف المصروفات تحت عمود ربح العيادة ثم الصافي (طرح عمودي).
/// • السنوية: تقرير أرباح وخسائر جديد كلياً فوق yearReport (م178):
///   مؤشرات السنة مع YoY، جدول 12 شهراً، جدول العيادات سنوياً، مخطط
///   الأشهر، وتفصيل كاش/تحويل/تركيبات.
/// • **الأرشيف أُلغي بالكامل** (بطاقته وقفزات الصفوف الشهرية إليه).
///
/// هذه نسخة الهاتف؛ الكمبيوتر له تخطيطه المخصص في profits_desktop.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../print/treatment_tables.dart' show formatNumber;
import 'finance_screen.dart' show financeRevProvider, financeSectionAllowed;
import 'profits_logic.dart';
import 'profits_tables.dart';
import 'statement_section.dart';
// م170 — اللقطات المالية المجمدة للعيادات المحذوفة (تبقى بالسجل المالي).
import '../settings/clinic_admin.dart' show frozenRowsForMonth;

/// م178 — صفوف اللقطات المجمدة لشهرٍ كصفوف أرباح (🔒 كما السابق).
List<ClinicProfitRow> frozenClinicProfitRows(JMap cfg, String month) => [
      for (final f in frozenRowsForMonth(cfg, month))
        ClinicProfitRow(
          '${f.clinic} 🔒',
          jsNumOr0(f.fields['revenue']),
          jsNumOr0(f.fields['doctor']),
          jsNumOr0(f.fields['clinicShare']),
        ),
    ];

class ProfitsSection extends ConsumerStatefulWidget {
  const ProfitsSection({super.key, this.initialView = 'monthly'});

  /// monthly | yearly | statement — روابط م108 تفتح الكشف مباشرة.
  final String initialView;

  @override
  ConsumerState<ProfitsSection> createState() => _ProfitsSectionState();
}

class _ProfitsSectionState extends ConsumerState<ProfitsSection> {
  late String view = widget.initialView;
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

    // م119/م178 — الحبب بصلاحيات أقسامها: الأرباح لحبتَي الشهرية/السنوية
    // وكشف الحساب لحبته — فمَن يملك إحداهما فقط يرى قسمه وحده.
    final canProfits = financeSectionAllowed('profits');
    final canStatement = financeSectionAllowed('statement');
    final pills = [
      if (canProfits) ('monthly', 'الشهرية'),
      if (canProfits) ('yearly', 'السنوية'),
      if (canStatement) ('statement', 'كشف الحساب'),
    ];
    if (pills.isNotEmpty && !pills.any((p) => p.$1 == view)) {
      view = pills.first.$1;
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Column(children: [
          if (view != 'statement')
            Row(children: [
              const Expanded(
                child: Text('أرباح الطبيب',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: BrandColors.brand900)),
              ),
              // v53 — منتقي السنة: رقاقة أنيقة بحد ذهبي وأيقونة تقويم.
              _pickerChip(
                icon: Icons.calendar_month_rounded,
                child: DropdownButton<String>(
                  key: const Key('prof-year'),
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
          if (view != 'statement') const SizedBox(height: 8),
          // م178 — ثلاث حبوب (كانت اثنتين): الشهرية/السنوية/كشف الحساب.
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: BrandColors.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              for (final p in pills) _viewPill(p.$1, p.$2),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 6),
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

  // ───────────────────────── الشهرية — جداول ─────────────────────────

  Widget _monthlyBody(
    List<JMap> records,
    List<JMap> prosthetics,
    List<JMap> debts,
    JMap cfg,
    String cur,
    List<String> clinics,
    num doctorPct,
    bool ratesOn,
  ) {
    final repos = ref.read(reposProvider);
    final month = '$selectedYear-${'${monthIdx + 1}'.padLeft(2, '0')}';
    // م170 — صفوف العيادات المحذوفة من لقطاتها المجمدة.
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
      key: const Key('profits-section'),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
      children: [
        Row(children: [
          const Expanded(
            child: Text('أرباح شهر',
                style:
                    TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          // v53 — منتقي الشهر بنفس رقاقة السنة الذهبية.
          _pickerChip(
            icon: Icons.event_rounded,
            child: DropdownButton<int>(
              key: const Key('prof-month'),
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
              onChanged: (v) => setState(() => monthIdx = v ?? monthIdx),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        // م178 — جدول أرباح العيادات المنظم (كان بطاقات).
        ProfitsClinicsTable(
          title: 'أرباح العيادات — ${arMonths[monthIdx]} $selectedYear',
          rows: rows,
          showDoctor: ratesOn,
        ),
        const SizedBox(height: 4),
        // م178 — جدول الإجمالي العام: المصروفات تحت عمود ربح العيادة.
        ProfitsGrandTable(
          revenue: grand.grandTotal + fRev,
          doctor: grand.doctorTotal + fDoc,
          clinic: grand.clinicTotal + fClin,
          expenses: ex.total,
          // م187 — قيمة المختبرات: صفّها + صفّ «صافي بعد المختبرات» يفسّران
          // فرقَ (الإيراد − الحصتين) الذي كان بلا تفسير (بلاغ المالك).
          lab: grand.prosLabCost,
          // م188 — إيراد التحاليل الثلاثية: صفٌّ تحت المصروفات يُضاف
          // لصافي العيادة وحدها (إيرادٌ خاصٌّ بها — قرار المالك).
          analyses: analysesRevenue(records, period: month),
          showDoctor: ratesOn,
        ),
      ],
    );
  }

  // ──────────────── السنوية — تقرير أرباح وخسائر م178 ────────────────

  Widget _yearlyBody(
    List<JMap> records,
    List<JMap> prosthetics,
    List<JMap> debts,
    JMap cfg,
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
    // YoY: مقارنة بالسنة السابقة إن كانت ضمن سنوات البيانات.
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
      key: const Key('profits-year-section'),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
      children: [
        // ── مؤشرات السنة (شبكة عمودين) ──
        YearKpiCards(items: [
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
        const SizedBox(height: 8),
        // ── جدول الأرباح والخسائر الشهري (قلب التقرير السنوي) ──
        YearPnlTable(report: rep, dense: true, showDoctor: ratesOn),
        const SizedBox(height: 4),
        // ── جدول العيادات سنوياً ──
        ProfitsClinicsTable(
          title: 'أرباح العيادات — سنة $selectedYear',
          rows: clinicRows,
          dense: true,
          showDoctor: ratesOn,
        ),
        const SizedBox(height: 4),
        _yearChart(rep, n),
        // م179 — بطاقة «قنوات القبض» (كاش/تحويل/تركيبات) أُلغيت بالكامل
        // من المنصتين (قرار المالك). التفصيل نفسه متاح في الخزينة.
      ],
    );
  }

  /// مخطط أشهر السنة (12 عموداً) — من صفوف التقرير نفسها فلا انحراف.
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
            height: 106,
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
                                : 64 * (m.revenue / maxBar) + 6,
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
                                  fontSize: 8.5, color: BrandColors.mut)),
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

  /// v53 — حبة مبدّل العرض بهوية أزرار أقسام المالية (صارت ثلاثاً).
  Widget _viewPill(String id, String label) {
    final on = view == id;
    return Expanded(
      child: InkWell(
        key: Key('prof-view-$id'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => view = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? BrandColors.brand600 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : BrandColors.strong)),
        ),
      ),
    );
  }

  /// v53 — رقاقة منتقٍ أنيقة: حد ذهبي + أيقونة، تحتضن DropdownButton.
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
