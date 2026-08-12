/// قسم الأرباح — نقل بنيوي لـ ProfitsTab.vue فوق profits_logic الحرفي:
/// مبدّل شهري/سنوي مع منتقي السنة؛ الشهري: منتقي الشهر العربي وصف أرباح
/// لكل عيادة (إيراد/طبيب/عيادة عبر getMonthlyReport) + الإجمالي العام؛
/// السنوي: مخطط مقارنة آخر 6 أشهر، بطاقات كاش/تحويل السنة وحصة طبيب
/// التركيبات (كاش/تحويل)، الإجمالي السنوي، والتفاصيل الشهرية القافزة
/// للأرشيف؛ وبطاقة الأرشيف أسفل القسم (المدخل الأصلي بعد Phase 5).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../archive/archive_screen.dart';
import '../print/treatment_tables.dart' show formatNumber;
import 'finance_screen.dart';
import 'profits_logic.dart';
// م170 — اللقطات المالية المجمدة للعيادات المحذوفة (تبقى بالسجل المالي).
import '../settings/clinic_admin.dart' show frozenRowsForMonth;
import '../staff/staff_gate.dart' show gateStaff;

class ProfitsSection extends ConsumerStatefulWidget {
  const ProfitsSection({super.key});

  @override
  ConsumerState<ProfitsSection> createState() => _ProfitsSectionState();
}

class _ProfitsSectionState extends ConsumerState<ProfitsSection> {
  String view = 'monthly'; // monthly | yearly
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
    final doctorPct = jsNumOr0(jsOr(cfg['doctorPct'], 50));
    final n = formatNumber;
    final years = profitYears(records, prosthetics);
    if (!years.contains(selectedYear)) selectedYear = years.first;

    final month =
        '$selectedYear-${'${monthIdx + 1}'.padLeft(2, '0')}';

    return ListView(
      key: const Key('profits-section'),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
      children: [
        Row(children: [
          const Expanded(
            child: Text('أرباح الطبيب',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: BrandColors.brand900)),
          ),
          // v53 — منتقي السنة: رقاقة أنيقة بحد ذهبي وأيقونة تقويم
          // بدل القائمة العارية.
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
        const SizedBox(height: 8),
        // v53 — مبدّل الشهرية/السنوية بحبوب هوية التطبيق (توأم أزرار
        // الخزينة/الديون/الأرباح) بدل SegmentedButton الافتراضي.
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: BrandColors.surface2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            _viewPill('monthly', 'الأرباح الشهرية'),
            _viewPill('yearly', 'الأرباح السنوية'),
          ]),
        ),
        const SizedBox(height: 10),

        if (view == 'monthly') ...[
          Row(children: [
            const Expanded(
              child: Text('أرباح شهر',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
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
                onChanged: (v) =>
                    setState(() => monthIdx = v ?? monthIdx),
              ),
            ),
          ]),
          Builder(builder: (context) {
            // م170 — صفوف العيادات المحذوفة من لقطاتها المجمدة (السجل
            // المالي القديم يبقى عادياً بعد الحذف — قرار المالك).
            final cfg = ref.watch(appConfigProvider);
            final frozenRows = frozenRowsForMonth(cfg, month);
            final rows = [
              ...monthlyClinicRows(
                month,
                records: records,
                prosthetics: prosthetics,
                debts: debts,
                clinics: clinics,
                doctorPct: doctorPct,
              ),
              for (final f in frozenRows)
                ClinicProfitRow(
                  '${f.clinic} 🔒',
                  jsNumOr0(f.fields['revenue']),
                  jsNumOr0(f.fields['doctor']),
                  jsNumOr0(f.fields['clinicShare']),
                ),
            ];
            final grand = getMonthlyReport(
                records, prosthetics, debts, month, doctorPct);
            // الإجمالي العام مع المجمد (كي يطابق الشهر التاريخي حرفياً).
            num frozenRevenue = 0, frozenDoctor = 0, frozenClinic = 0;
            for (final f in frozenRows) {
              frozenRevenue += jsNumOr0(f.fields['revenue']);
              frozenDoctor += jsNumOr0(f.fields['doctor']);
              frozenClinic += jsNumOr0(f.fields['clinicShare']);
            }
            final ex = repos.expenses.monthExpenseTotals(month);
            return Column(children: [
              if (rows.isEmpty)
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('لا توجد بيانات لهذا الشهر',
                      style:
                          TextStyle(fontSize: 12, color: BrandColors.mut2)),
                )
              else
                for (final row in rows)
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.business_rounded,
                                size: 16, color: BrandColors.brand600),
                            const SizedBox(width: 6),
                            Text(row.name,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: BrandColors.brand700)),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            _ProfCell('إجمالي الإيرادات', n(row.revenue),
                                BrandColors.goldDark),
                            _ProfCell('ربح الطبيب', n(row.doctor),
                                BrandColors.green),
                            _ProfCell('ربح العيادة', n(row.clinicShare),
                                BrandColors.brand600),
                          ]),
                        ],
                      ),
                    ),
                  ),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(
                      color: BrandColors.gold, width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    const Text('الإجمالي العام لجميع العيادات',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.goldDark)),
                    const SizedBox(height: 8),
                    Row(children: [
                      _ProfCell('إجمالي الإيرادات',
                          n(grand.grandTotal + frozenRevenue),
                          BrandColors.goldDark,
                          key: const Key('prof-grand-revenue')),
                      _ProfCell('ربح الطبيب',
                          n(grand.doctorTotal + frozenDoctor),
                          BrandColors.green,
                          key: const Key('prof-grand-doctor')),
                      _ProfCell('ربح العيادة',
                          n(grand.clinicTotal + frozenClinic),
                          BrandColors.brand600,
                          key: const Key('prof-grand-clinic')),
                    ]),
                    // ── المصروفات وصافي ربح العيادة (دفعة المصروفات) ──
                    if (ex.total != 0) ...[
                      const Divider(height: 18),
                      Row(children: [
                        _ProfCell('المصروفات', n(ex.total), BrandColors.red),
                        _ProfCell(
                            'صافي ربح العيادة',
                            n(grand.clinicTotal + frozenClinic - ex.total),
                            BrandColors.brand700,
                            key: const Key('prof-grand-clinic-net')),
                      ]),
                    ],
                  ]),
                ),
              ),
            ]);
          }),
        ] else ...[
          // ── السنوي — v53: بطاقة البطل ثم مخطط السنة ثم التفاصيل ──
          Builder(builder: (context) {
            final y = yearTotals(selectedYear,
                records: records, prosthetics: prosthetics, debts: debts);
            final now = DateTime.now();
            final nowM =
                '${now.year}-${'${now.month}'.padLeft(2, '0')}';
            // أعمدة أشهر السنة المحددة كاملة (12) — نفس دالة الشهر
            // الواحد المستعملة في التفاصيل، فلا انحراف بين العرضين.
            final bars = <({String label, String month, num total})>[
              for (var i = 0; i < 12; i++)
                (
                  label: arMonths[i].substring(0, 3),
                  month: '$selectedYear-${'${i + 1}'.padLeft(2, '0')}',
                  total: monthGrandFor(
                      '$selectedYear-${'${i + 1}'.padLeft(2, '0')}',
                      records: records,
                      prosthetics: prosthetics,
                      debts: debts),
                ),
            ];
            final maxBar = bars.fold<num>(
                1, (mx, b) => b.total > mx ? b.total : mx);
            // اختصار قيمة العمود الأعلى (80,762 ← 80.8k).
            String kFmt(num v) => v >= 1000
                ? '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k'
                : n(v);
            return Column(children: [
              // ── بطاقة البطل: إجمالي السنة + الصف الثلاثي المفصول ──
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(
                      color: BrandColors.gold, width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Text('إجمالي سنة $selectedYear',
                        style: TextStyle(
                            fontSize: 11.5, color: BrandColors.mut)),
                    Text('${n(y.grand)} $cur',
                        key: const Key('prof-year-grand'),
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: BrandColors.goldDark)),
                    const Divider(height: 22),
                    Row(children: [
                      _ProfCell('كاش', n(y.cash), BrandColors.green,
                          key: const Key('prof-year-cash')),
                      Container(
                          width: 1,
                          height: 26,
                          color: BrandColors.line),
                      _ProfCell('تحويل', n(y.xfer), BrandColors.brand600,
                          key: const Key('prof-year-xfer')),
                      Container(
                          width: 1,
                          height: 26,
                          color: BrandColors.line),
                      // م117 — التركيبات بالمقبوض الكامل ليطابق مجموع
                      // الخلايا الإجمالي (كاش + تحويل + تركيبات = الإجمالي)؛
                      // حصة الطبيب تُعرض تفصيلاً أدناه لا في هذه الخلية.
                      _ProfCell('تركيبات (مقبوض)', n(y.prosPaid),
                          BrandColors.goldDark,
                          key: const Key('prof-year-prospaid')),
                    ]),
                    if (y.prosDoc > 0) ...[
                      const SizedBox(height: 8),
                      // تفصيل تركيبات الطبيب مدمج بدل بطاقة مستقلة.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: BrandColors.surface2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Text('تفصيل تركيبات الطبيب',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: BrandColors.mut2)),
                          ),
                          Text('كاش ${n(y.prosCash)}',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: BrandColors.green)),
                          const SizedBox(width: 10),
                          Text('تحويل ${n(y.prosXfer)}',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: BrandColors.brand600)),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              // ── مخطط أشهر السنة المحددة كاملة (12 عموداً) ──
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                  child: Column(children: [
                    Text('أشهر سنة $selectedYear',
                        style: TextStyle(
                            fontSize: 11, color: BrandColors.mut)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 106,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final b in bars)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 1.5),
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.end,
                                  children: [
                                    // قيمة أعلى عمود بالسنة — مختصرة.
                                    if (b.total >= maxBar &&
                                        b.total > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 2),
                                        child: Text(kFmt(b.total),
                                            style: const TextStyle(
                                                fontSize: 8.5,
                                                fontWeight:
                                                    FontWeight.w800,
                                                color: BrandColors
                                                    .goldDark)),
                                      ),
                                    Container(
                                      height: b.total <= 0
                                          ? 3.0
                                          : 64 * (b.total / maxBar) + 6,
                                      decoration: BoxDecoration(
                                        color: b.total <= 0
                                            ? BrandColors.line
                                            : b.month == nowM
                                                ? BrandColors.gold
                                                : BrandColors.brand600
                                                    .withValues(
                                                        alpha: .35),
                                        borderRadius:
                                            const BorderRadius.vertical(
                                                top: Radius.circular(4)),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(b.label,
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
              ),
              const SizedBox(height: 10),
              // ── التفاصيل الشهرية — أشرطة نسبية أنيقة ──
              const Align(
                alignment: Alignment.centerRight,
                child: Text('التفاصيل الشهرية',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < 12; i++)
                Builder(builder: (context) {
                  final m =
                      '$selectedYear-${'${i + 1}'.padLeft(2, '0')}';
                  final total = bars[i].total;
                  if (total <= 0) return const SizedBox.shrink();
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: InkWell(
                      key: Key('prof-month-$m'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        // م119 — الأرشيف صلاحية مستقلة.
                        if (!gateStaff(context, 'archive.view')) return;
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const ArchiveScreen()));
                      },
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(arMonths[i],
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 5),
                                // شريط نسبة الشهر من أعلى شهر بالسنة.
                                Container(
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: BrandColors.line,
                                    borderRadius:
                                        BorderRadius.circular(3),
                                  ),
                                  alignment:
                                      AlignmentDirectional.centerStart,
                                  child: FractionallySizedBox(
                                    widthFactor: (total / maxBar)
                                        .clamp(.04, 1)
                                        .toDouble(),
                                    heightFactor: 1,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                            colors: [
                                              BrandColors.goldDark,
                                              BrandColors.gold,
                                            ]),
                                        borderRadius:
                                            BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('${n(total)} $cur',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: BrandColors.goldDark)),
                          Icon(Icons.chevron_left_rounded,
                              size: 16, color: BrandColors.mut2),
                        ]),
                      ),
                    ),
                  );
                }),
            ]);
          }),
        ],

        const SizedBox(height: 10),
        // ── الأرشيف (مدخله الأصلي هنا) ──
        Card(
          child: ListTile(
            key: const Key('fin-archive'),
            leading: const Icon(Icons.folder_rounded,
                color: BrandColors.goldDark),
            title: const Text('الأرشيف',
                style:
                    TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            subtitle: const Text('كل الأشهر المسجلة بملخصاتها وسجلاتها',
                style: TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () {
              // م119 — الأرشيف صلاحية مستقلة.
              if (!gateStaff(context, 'archive.view')) return;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ArchiveScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  /// v53 — حبة مبدّل العرض (شهري/سنوي) بهوية أزرار أقسام المالية.
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

class _ProfCell extends StatelessWidget {
  const _ProfCell(this.label, this.value, this.color, {super.key});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: BrandColors.mut2)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}

// v53 — _YearCard أُزيلت: بطاقات السنة اندمجت في بطاقة البطل الموحدة.
