/// م161 — قسم المختبر بهوية الخزينة (قرار المالك): قائمة المختبرات
/// بطاقاتٍ صفّية صغيرة (اسم المختبر + قيمة الشهر يساراً) تصفر تلقائياً
/// مطلع كل شهر لأنها مربوطة بمبدّل الشهر القائم، فوقها بحثٌ وزر «طباعة
/// قيم كل المعامل». الضغط على مختبرٍ يفتح شاشةً مستقلة (رجوع بزر) فيها
/// بحثٌ وزر طباعة بخيارين (كل عيادة/كل العيادات) وجدولٌ بهوية الخزينة:
/// التاريخ/الاسم/العيادة/نوع التركيب/الوحدات/القيمة — الأحدث أولاً —
/// وصف إجمالي (مجموع الوحدات + مجموع القيم). القيمة = قيمة المختبر.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../print/print_service.dart';
import '../print/reports.dart';
import '../print/treatment_tables.dart' show formatNumber;
import 'lab_logo.dart';
import '../patients/patients_tab.dart' show patientsRevProvider;
import 'labs_logic.dart';

class LabsTab extends ConsumerWidget {
  const LabsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(appConfigProvider);
    final labs = cfg['labs'] is List
        ? [for (final l in cfg['labs'] as List) '$l']
        : <String>[];

    if (labs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LabLogo(size: 42, color: BrandColors.brand600),
              const SizedBox(height: 10),
              const Text('لا توجد مختبرات',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text('أضف مختبرات من الإعدادات ← إعدادات المختبرات',
                  style: TextStyle(fontSize: 12, color: BrandColors.mut)),
            ],
          ),
        ),
      );
    }
    return const _LabsLanding();
  }
}

/// قائمة المختبرات — بطاقات صفّية بهوية الخزينة + بحث + طباعة الكل.
class _LabsLanding extends ConsumerStatefulWidget {
  const _LabsLanding();

  @override
  ConsumerState<_LabsLanding> createState() => _LabsLandingState();
}

class _LabsLandingState extends ConsumerState<_LabsLanding> {
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(patientsRevProvider);
    final cfg = ref.watch(appConfigProvider);
    final labs = cfg['labs'] is List
        ? [for (final l in cfg['labs'] as List) '$l']
        : <String>[];
    final month = ref.watch(selectedMonthProvider);
    final cur = ref.watch(currencyProvider);
    final n = formatNumber;
    final repos = ref.watch(reposProvider);
    final prosthetics = repos.prosthetics.getAll();

    final q = _searchCtl.text.trim();
    final cards = [
      for (final k in labCards(labs, prosthetics: prosthetics, month: month))
        if (q.isEmpty || k.name.contains(q)) k,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
      children: [
        Row(children: [
          const LabLogo(size: 19, color: BrandColors.brand600),
          const SizedBox(width: 8),
          Expanded(
            child: Text('المختبرات — $month',
                style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: BrandColors.brand900)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                key: const Key('labs-search'),
                controller: _searchCtl,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'بحث باسم المختبر…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 16),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: BrandColors.gold.withValues(alpha: .08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: BrandColors.gold.withValues(alpha: .3)),
            ),
            child: InkWell(
              key: const Key('labs-print-all'),
              borderRadius: BorderRadius.circular(10),
              onTap:
                  cards.isEmpty ? null : () => _printAllValues(cards, month),
              child: const SizedBox(
                width: 38,
                height: 36,
                child: Icon(Icons.print_rounded,
                    size: 16, color: BrandColors.goldDark),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (cards.isEmpty)
          Padding(
            padding: const EdgeInsets.all(22),
            child: Center(
              child: Text('لا مختبرات مطابقة',
                  style: TextStyle(fontSize: 12.5, color: BrandColors.mut2)),
            ),
          )
        else
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _labCard(cards[i], cur, n),
          ],
      ],
    );
  }

  /// بطاقة المختبر الصفّية — توأم TreasuryMasterRow: اللوغو + الاسم
  /// يميناً وقيمة الشهر يساراً + سهم الدخول.
  Widget _labCard(LabCard k, String cur, String Function(Object?) n) {
    return Material(
      color: BrandColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: BrandColors.line, width: .8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('lab-${k.name}'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LabDetailScreen(lab: k.name),
        )),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(27, 94, 71, .1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Center(
                  child: LabLogo(size: 17, color: BrandColors.brand)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(k.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.brandText)),
                  const SizedBox(height: 2),
                  Text('${k.count} حالة هذا الشهر',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.1,
                          color: BrandColors.ink.withValues(alpha: .65))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('${n(k.monthValue)} $cur',
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: BrandColors.goldDark,
                    fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(width: 4),
            Icon(Icons.chevron_left_rounded, size: 17, color: BrandColors.mut),
          ]),
        ),
      ),
    );
  }

  Future<void> _printAllValues(List<LabCard> cards, String month) async {
    final fonts = await loadPdfBrand(ref);
    final bytes = await labsValuesPdf(
      fonts,
      subtitle: month,
      currency: ref.read(currencyProvider),
      cards: cards,
    );
    final msg = await printOrSharePdf(
        ref.read(dbDirProvider), bytes, 'labs_values.pdf');
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

/// شاشة مختبرٍ مستقلة (م161) — بحث + طباعة بخيارين + جدول بهوية الخزينة.
class LabDetailScreen extends ConsumerStatefulWidget {
  const LabDetailScreen({super.key, required this.lab});

  final String lab;

  @override
  ConsumerState<LabDetailScreen> createState() => _LabDetailScreenState();
}

class _LabDetailScreenState extends ConsumerState<LabDetailScreen> {
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(patientsRevProvider);
    final month = ref.watch(selectedMonthProvider);
    final cur = ref.watch(currencyProvider);
    final n = formatNumber;
    final repos = ref.watch(reposProvider);
    final allRows = labMonthRows(widget.lab,
        prosthetics: repos.prosthetics.getAll(), month: month);
    final q = _searchCtl.text.trim();
    final rows = [
      for (final r in allRows)
        if (q.isEmpty || r.name.contains(q) || r.clinic.contains(q)) r,
    ];
    final totUnits = rows.fold<num>(0, (t, r) => t + r.units);
    final totValue = rows.fold<num>(0, (t, r) => t + r.value);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text('${widget.lab} — $month',
              style: const TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    key: const Key('lab-detail-search'),
                    controller: _searchCtl,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'بحث بالاسم أو العيادة…',
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: 16),
                      prefixIconConstraints: const BoxConstraints(
                          minWidth: 30, minHeight: 30),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
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
                child: PopupMenuButton<String>(
                  key: const Key('lab-detail-print'),
                  tooltip: 'طباعة',
                  enabled: rows.isNotEmpty,
                  onSelected: (v) =>
                      _print(rows, month, byClinic: v == 'byClinic'),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: 'all',
                        child: Text('كل العيادات معاً',
                            style: TextStyle(fontSize: 12.5))),
                    PopupMenuItem(
                        value: 'byClinic',
                        child: Text('كل عيادة على حدة',
                            style: TextStyle(fontSize: 12.5))),
                  ],
                  child: const SizedBox(
                    width: 38,
                    height: 36,
                    child: Icon(Icons.print_rounded,
                        size: 16, color: BrandColors.goldDark),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('لا حالات لهذا المختبر هذا الشهر',
                      style: TextStyle(
                          fontSize: 12.5, color: BrandColors.mut2)),
                ),
              )
            else
              _table(rows, totUnits, totValue, cur, n),
          ],
        ),
      ),
    );
  }

  /// جدول المختبر بهوية جداول الخزينة — 6 أعمدة + صف الإجمالي.
  Widget _table(List<LabRow> rows, num totUnits, num totValue, String cur,
      String Function(Object?) n) {
    TextStyle head() => TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: BrandColors.mut2);
    const wDate = 74.0, wUnits = 44.0, wVal = 78.0;

    Widget dcell(String v) => SizedBox(
        width: wDate,
        child: Text(v,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: BrandColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()])));

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.line, width: .8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(children: [
              SizedBox(width: wDate, child: Text('التاريخ', style: head())),
              const SizedBox(width: 6),
              Expanded(child: Text('الاسم', style: head())),
              const SizedBox(width: 6),
              Expanded(child: Text('العيادة', style: head())),
              const SizedBox(width: 6),
              Expanded(child: Text('نوع التركيب', style: head())),
              const SizedBox(width: 6),
              SizedBox(
                  width: wUnits,
                  child: Text('الوحدات',
                      style: head(), textAlign: TextAlign.center)),
              const SizedBox(width: 6),
              SizedBox(
                  width: wVal,
                  child: Text('القيمة',
                      style: head(), textAlign: TextAlign.center)),
            ]),
          ),
          Divider(height: 1, color: BrandColors.line),
          for (final r in rows) ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(children: [
                dcell(r.date),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(r.name.isEmpty ? '—' : r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(r.clinic.isEmpty ? '—' : r.clinic,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11, color: BrandColors.mut)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(r.prosType,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.strong)),
                ),
                const SizedBox(width: 6),
                SizedBox(
                    width: wUnits,
                    child: Text(n(r.units),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700))),
                const SizedBox(width: 6),
                SizedBox(
                  width: wVal,
                  child: Text('${n(r.value)} $cur',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.goldDark,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ]),
            ),
            Divider(height: 1, color: BrandColors.line),
          ],
          Container(
            key: const Key('lab-detail-total'),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(201, 162, 75, .10),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: const Color.fromRGBO(201, 162, 75, .30)),
            ),
            child: Row(children: [
              Expanded(
                child: Text('الإجمالي (${rows.length} حالة)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.strong)),
              ),
              SizedBox(
                  width: wUnits,
                  child: Text(n(totUnits),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.strong))),
              const SizedBox(width: 6),
              SizedBox(
                width: wVal,
                child: Text('${n(totValue)} $cur',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.goldDark,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _print(List<LabRow> rows, String month,
      {required bool byClinic}) async {
    final fonts = await loadPdfBrand(ref);
    final bytes = await labMonthReportPdf(
      fonts,
      lab: widget.lab,
      subtitle: month,
      currency: ref.read(currencyProvider),
      rows: rows,
      byClinic: byClinic,
    );
    final msg = await printOrSharePdf(
        ref.read(dbDirProvider), bytes, 'lab_${widget.lab}.pdf');
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
