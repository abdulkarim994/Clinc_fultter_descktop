/// شاشة الأرشيف — نقل بنيوي لـ ArchiveTab.vue فوق month_stats المنقولة
/// حرفياً: قائمة الأشهر تنازلياً ببطاقات (كاش/تحويل/تركيبات + الإجمالي)،
/// وتفصيل الشهر ببطاقات الملخص وقائمة سجلاته مرتبة بالأحدث (byNewestFirst).
/// المصدر: القاعدة المحلية كاملة (أوفلاين أولاً) — التحديث السحابي الخلفي
/// يأتي مع نقل Supabase في م5، وكذلك طباعة الشهر.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../print/print_service.dart';
import '../print/reports.dart';
import '../print/treatment_tables.dart';
import 'month_stats.dart';

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  String? detailMonth;

  @override
  Widget build(BuildContext context) {
    final repos = ref.watch(reposProvider);
    final records = repos.records.getAll();
    final prosthetics = repos.prosthetics.getAll();
    final debts = repos.debts.getAll();

    MonthData dataOf(String m) => monthData(m,
        records: records, prosthetics: prosthetics, debts: debts);

    if (detailMonth == null) {
      final months = monthsOf(records, prosthetics);
      return Scaffold(
        appBar: AppBar(title: const Text('الأرشيف')),
        body: months.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_outlined,
                        size: 52, color: BrandColors.goldDark),
                    SizedBox(height: 10),
                    Text('لا توجد بيانات مسجلة',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
                children: [
                  for (final m in months)
                    Builder(builder: (context) {
                      final d = dataOf(m);
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        child: InkWell(
                          key: Key('arch-month-$m'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => detailMonth = m),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                Row(children: [
                                  const Icon(Icons.calendar_month_rounded,
                                      size: 18,
                                      color: BrandColors.goldDark),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(m,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: BrandColors.brand700)),
                                  ),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Text(d.total.toStringAsFixed(2),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                              color:
                                                  BrandColors.goldDark)),
                                      Text('إجمالي الدخل',
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: BrandColors.mut2)),
                                    ],
                                  ),
                                ]),
                                const SizedBox(height: 10),
                                Row(children: [
                                  _MiniStat('كاش',
                                      d.cash.toStringAsFixed(2)),
                                  _MiniStat('تحويل',
                                      d.xfer.toStringAsFixed(2)),
                                  _MiniStat('تركيبات',
                                      d.prosTotal.toStringAsFixed(2)),
                                ]),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
      );
    }

    // ── تفصيل شهر ──
    final m = detailMonth!;
    final d = dataOf(m);
    final recs = detailRecords(m,
        records: records, prosthetics: prosthetics, debts: debts);

    return Scaffold(
      appBar: AppBar(
        title: Text('الأرشيف — $m'),
        leading: IconButton(
          key: const Key('arch-back'),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => setState(() => detailMonth = null),
        ),
        actions: [
          IconButton(
            key: const Key('arch-print'),
            tooltip: 'طباعة',
            icon: const Icon(Icons.print_rounded),
            onPressed: () async {
              // printMonth حرفياً: المعالجات = النقدية + دفعات الديون
              // العادية مرتبة بالتاريخ (بتطبيع الأرقام العربية للصفوف
              // القديمة)، والتركيبات كل صفوف الشهر، والديون المعلقة كلها.
              String norm(Object? s) => '$s'
                  .replaceAllMapped(RegExp('[٠-٩]'),
                      (m) => '${'٠١٢٣٤٥٦٧٨٩'.indexOf(m[0]!)}')
                  .replaceAll('/', '-');
              // م114 — الأحدث أولاً في طباعة الشهر.
              int byDate(Map a, Map b) =>
                  norm(b['date']).compareTo(norm(a['date']));
              final allRecs = [
                ...getMonthRecs(records, debts, m),
                ...getMonthRegDebtPays(records, debts, m),
              ]..sort(byDate);
              final mp = [...getMonthPros(prosthetics, m)]..sort(byDate);
              final cfg = ref.read(appConfigProvider);
              final tables = buildTreatmentTables(allRecs,
                  fallbackPct: jsNumber(jsOr(cfg['doctorPct'], 50)));
              final pending = [
                for (final dd in debts)
                  if (dd['status'] != 'paid') dd,
              ];
              final fonts = await loadPdfBrand(ref);
              final bytes = await monthlyReportPdf(
                fonts,
                month: m,
                centerName: '${jsOr(cfg['centerName'], '')}',
                currency: ref.read(currencyProvider),
                data: d,
                recTables: tables,
                prosRows: mp,
                pendingDebts: pending,
              );
              final msg = await printOrSharePdf(
                  ref.read(dbDirProvider), bytes, 'report_$m.pdf');
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(msg)));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(children: [
                    _MiniStat('كاش', d.cash.toStringAsFixed(2)),
                    _MiniStat('تحويل', d.xfer.toStringAsFixed(2)),
                    _MiniStat('تركيبات', d.prosTotal.toStringAsFixed(2)),
                  ]),
                  const Divider(height: 20),
                  Text('الإجمالي الكلي',
                      style:
                          TextStyle(fontSize: 11.5, color: BrandColors.mut2)),
                  Text(d.total.toStringAsFixed(2),
                      key: const Key('arch-total'),
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.goldDark)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('سجلات الشهر',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: BrandColors.brand900)),
          const SizedBox(height: 4),
          if (recs.isEmpty)
            Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('لا توجد سجلات',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: BrandColors.mut2)),
              ),
            )
          else
            for (final r in recs)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  dense: true,
                  title: Text('${r['name'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${r['date'] ?? ''} | ${r['service'] ?? ''}',
                      style: const TextStyle(fontSize: 11)),
                  trailing: Text(
                    jsNumOr0(jsOr(r['amount'], r['doctorShare']))
                        .toStringAsFixed(2),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.green),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(fontSize: 11.5, color: BrandColors.mut2)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.brand700)),
        ],
      ),
    );
  }
}
