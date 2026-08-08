/// تبويب المختبرات — نقل بنيوي لـ LabsTab.vue فوق المنطق المنقول حرفياً:
/// قائمة المختبرات من config.labs بعدد حالات كلٍّ منها، وتفصيل المختبر
/// بحالاته (المريض/العيادة/التاريخ/النوع×الوحدات/القيمة/الحالة المالية
/// بتاريخها) مع فرز أقدم/أحدث ومجاميع الوحدات والإجمالي والمحصّل والديون
/// والصافي. الطباعة تُستكمل مع خط PDF العربي في م5.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../print/print_service.dart';
import '../print/reports.dart';
import 'labs_logic.dart';

class LabsTab extends ConsumerStatefulWidget {
  const LabsTab({super.key});

  @override
  ConsumerState<LabsTab> createState() => _LabsTabState();
}

class _LabsTabState extends ConsumerState<LabsTab> {
  String selectedLab = '';
  // م113 — الافتراضي: الأحدث أولاً (مفتاح التبديل باقٍ).
  String sortOrder = 'newest';

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(appConfigProvider);
    final labs = cfg['labs'] is List
        ? [for (final l in cfg['labs'] as List) '$l']
        : <String>[];
    final repos = ref.watch(reposProvider);
    final prosthetics = repos.prosthetics.getAll();

    if (selectedLab.isEmpty) {
      // ── قائمة المختبرات ──
      if (labs.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.biotech_rounded,
                    size: 42, color: BrandColors.brand600),
                SizedBox(height: 10),
                Text('لا توجد مختبرات',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                SizedBox(height: 4),
                Text('أضف مختبرات من الإعدادات ← إعدادات المختبرات',
                    style: TextStyle(fontSize: 12, color: BrandColors.mut)),
              ],
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
        children: [
          Row(children: [
            const Icon(Icons.biotech_rounded,
                size: 20, color: BrandColors.brand600),
            const SizedBox(width: 8),
            const Text('المختبرات',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: BrandColors.brand900)),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(
                  color: BrandColors.gold.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${labs.length}',
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 10),
          for (final lab in labs)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                key: Key('lab-$lab'),
                leading: CircleAvatar(
                  radius: 17,
                  backgroundColor:
                      BrandColors.brand600.withValues(alpha: .1),
                  child: const Icon(Icons.biotech_rounded,
                      size: 17, color: BrandColors.brand700),
                ),
                title: Text(lab,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: Text('${labCasesCount(prosthetics, lab)} حالة',
                    style: const TextStyle(fontSize: 11.5)),
                trailing: const Icon(Icons.chevron_left_rounded, size: 20),
                onTap: () => setState(() => selectedLab = lab),
              ),
            ),
        ],
      );
    }

    // ── تفصيل مختبر ──
    final cases = labCases(
      selectedLab,
      prosthetics: prosthetics,
      debts: repos.debts.getAll(),
      records: repos.records.getAll(),
      sortOrder: sortOrder,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
      children: [
        // ── v61 — رأس المختبر بالقالب الموحد: [رجوع 38×36 | الاسم
        // والعدد | طباعة كمربع ذهبي] — توأم رؤوس السجلات والمالية. ──
        Row(children: [
          Material(
            color: BrandColors.brand600.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: const Key('lab-back'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => selectedLab = ''),
              child: SizedBox(
                width: 38,
                height: 36,
                child: Icon(Icons.arrow_back_rounded,
                    size: 18, color: BrandColors.brandIcon),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selectedLab,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: BrandColors.brandText)),
                Text('${cases.length} حالة',
                    style: TextStyle(
                        fontSize: 10.5, color: BrandColors.mut2)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: BrandColors.gold.withValues(alpha: .08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                  color: BrandColors.gold.withValues(alpha: .3)),
            ),
            child: InkWell(
              key: const Key('lab-print'),
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final fonts = await loadPdfBrand(ref);
                final bytes = await labReportPdf(fonts,
                    lab: selectedLab,
                    cases: cases,
                    currency: ref.read(currencyProvider));
                final msg = await printOrSharePdf(
                    ref.read(dbDirProvider),
                    bytes,
                    'lab_$selectedLab.pdf');
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(msg)));
                }
              },
              child: const SizedBox(
                width: 38,
                height: 36,
                child: Icon(Icons.print_rounded,
                    size: 16, color: BrandColors.goldDark),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          key: const Key('lab-sort'),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: 'oldest', label: Text('الأقدم أولاً')),
            ButtonSegment(value: 'newest', label: Text('الأحدث أولاً')),
          ],
          selected: {sortOrder},
          onSelectionChanged: (s) => setState(() => sortOrder = s.first),
        ),
        const SizedBox(height: 10),

        if (cases.isEmpty)
          Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('لا توجد حالات لهذا المختبر',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: BrandColors.mut2, fontSize: 13)),
            ),
          )
        else ...[
          for (final c in cases)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c.row['name'] ?? ''}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              '${c.row['clinic'] ?? ''} • ${c.row['date'] ?? ''}',
                              style: TextStyle(
                                  fontSize: 11, color: BrandColors.mut)),
                          if ('${c.row['prosType'] ?? ''}'.isNotEmpty)
                            Text(
                              jsNumOr0(c.row['prosUnits']) > 1
                                  ? '${c.row['prosType']} × ${jsNumOr0(c.row['prosUnits']).toStringAsFixed(0)} وحدات'
                                  : '${c.row['prosType']}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: BrandColors.brand700),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                            jsNumOr0(c.row['labValue'])
                                .toStringAsFixed(0),
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: BrandColors.goldDark)),
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (c.financialStatus == 'محصّل'
                                    ? BrandColors.green
                                    : BrandColors.red)
                                .withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            c.financialStatus,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: c.financialStatus == 'محصّل'
                                  ? BrandColors.green
                                  : BrandColors.red,
                            ),
                          ),
                        ),
                        Text(c.statusDate,
                            style: TextStyle(
                                fontSize: 11, color: BrandColors.mut2)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // ── المجاميع ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                _tot('عدد الحالات', '${cases.length}'),
                _tot('إجمالي الوحدات',
                    labTotalUnits(cases).toStringAsFixed(0)),
                _tot('إجمالي المختبر',
                    labTotalAll(cases).toStringAsFixed(2)),
                _tot('المحصّل',
                    labTotalCollected(cases).toStringAsFixed(2),
                    color: BrandColors.green),
                _tot('الديون', labTotalDebt(cases).toStringAsFixed(2),
                    color: BrandColors.red),
                const Divider(height: 14),
                _tot(
                    'الصافي',
                    (labTotalCollected(cases) - labTotalDebt(cases))
                        .toStringAsFixed(2),
                    color: BrandColors.brand700,
                    big: true),
              ]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tot(String label, String value, {Color? color, bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style:
                    TextStyle(fontSize: 12.5, color: BrandColors.mut))),
        Text(value,
            style: TextStyle(
                fontSize: big ? 15 : 13,
                fontWeight: big ? FontWeight.w900 : FontWeight.w700,
                color: color ?? BrandColors.brand900)),
      ]),
    );
  }
}
