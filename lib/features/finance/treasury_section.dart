/// قسم الخزينة — نقل بنيوي كامل لـ TreasuryTab.vue فوق treasury_logic
/// الحرفي: لكل عيادة ثلاث بطاقات (كاش/تحويل/تركيبات مدفوعة) تفتح التفصيل،
/// وبطاقة ديون معلقة تقفز لقسم الديون بفلتر العيادة؛ ثم بطاقة الإجمالي
/// (كاش/تحويل/تركيبات + الدخل الفعلي المحصّل + رصيد الديون غير المحصّل).
/// التفصيل: تبويبات الفئات، بحث بالاسم، نطاق تاريخ قابل للطي، أنماط الفرز
/// الأربعة بالتدوير، قائمة العناصر أو بطاقات التركيبات المجمّعة بالمريض
/// القابلة للتوسّع بدفعاتها وحالة دينها، وحوار الدفعات العابرة للشهور،
/// وطباعة الفئة PDF.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../print/print_service.dart';
import '../print/reports.dart'
    show prostheticsReportPdf, simpleTablePdf, treatmentTablesPdf;
import '../print/treatment_tables.dart'
    show buildTreatmentTables, formatNumber;
import 'debts_section.dart' show debtsClinicFilterProvider;
import 'finance_screen.dart' hide JMap;
import 'treasury_logic.dart';
import '../staff/staff_gate.dart' show staffAllowed;

class TreasurySection extends ConsumerStatefulWidget {
  const TreasurySection({super.key});

  @override
  ConsumerState<TreasurySection> createState() => _TreasurySectionState();
}

class _TreasurySectionState extends ConsumerState<TreasurySection> {
  String? detailView; // cash | xfer | pros
  String detailCli = '';
  final nameCtl = TextEditingController();
  String filterFrom = '';
  String filterTo = '';
  bool showDateRange = false;
  String sortMode = 'date-desc';
  final expandedPros = <String>{};

  @override
  void dispose() {
    nameCtl.dispose();
    super.dispose();
  }

  TreasurySlice _slice() {
    ref.watch(financeRevProvider);
    final repos = ref.watch(reposProvider);
    return TreasurySlice(
      ref.watch(selectedMonthProvider),
      records: repos.records.getAll(),
      prosthetics: repos.prosthetics.getAll(),
      debts: repos.debts.getAll(),
    );
  }

  void _showDetail(String type, String cli) => setState(() {
        detailView = type;
        detailCli = cli;
        nameCtl.clear();
        filterFrom = '';
        filterTo = '';
      });

  void _goDebts(String? clinic) {
    ref.read(debtsClinicFilterProvider.notifier).state = clinic ?? '';
    ref.read(financeSectionProvider.notifier).state = 'debts';
  }

  @override
  Widget build(BuildContext context) {
    final s = _slice();
    final cur = ref.watch(currencyProvider);
    final clinics = ref.watch(clinicsProvider);
    final n = formatNumber;

    // م121 — بلا صلاحية «تفاصيل الخزينة»: المجموع الكلي (المحصّل) فقط،
    // وتُحجب بطاقات العيادات والخلايا التفصيلية وبطاقة الإجماليات.
    final det = staffAllowed('treasury.details');
    if (detailView == null) {
      final t = treasuryTotals(s);
      final ex =
          ref.watch(reposProvider).expenses.monthExpenseTotals(s.month);
      return ListView(
        key: const Key('treasury-main'),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
        children: [
          // م125 — بطاقات العيادات وتفاصيلها للجميع (تصحيح المالك):
          // المحجوب بلا الصلاحية هو المجاميع الإجمالية لا التفاصيل.
          for (final cli in clinics) ...[
            Text(cli,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: BrandColors.brand900)),
            const SizedBox(height: 6),
            // نظام «التحاليل» — أربع بطاقات الآن؛ لُفّت بـ Wrap لتفادي
            // الضيق على الشاشات الصغيرة (كاش/تحويل صفٌّ، تركيبات/تحاليل صفٌّ).
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                // م126 — بلا صلاحية المجاميع: شرطة بدل الرقم على وجه
                // البطاقة، والنقر لتفاصيلها متاح كما هو (تصحيح المالك).
                _WrapStatCard(
                  key: Key('tr-cash-$cli'),
                  label: 'كاش',
                  value: det ? n(clinicCash(s, cli)) : '—',
                  unit: cur,
                  color: BrandColors.green,
                  onTap: () => _showDetail('cash', cli),
                ),
                _WrapStatCard(
                  key: Key('tr-xfer-$cli'),
                  label: 'تحويل',
                  value: det ? n(clinicXfer(s, cli)) : '—',
                  unit: cur,
                  color: BrandColors.brand600,
                  onTap: () => _showDetail('xfer', cli),
                ),
                _WrapStatCard(
                  key: Key('tr-pros-$cli'),
                  label: 'تركيبات',
                  value: det ? n(clinicProsTotalPaid(s, cli)) : '—',
                  unit: cur,
                  color: BrandColors.goldDark,
                  onTap: () => _showDetail('pros', cli),
                ),
                // نظام «التحاليل» — بطاقة الدخل المخبري المعزول للعيادة.
                _WrapStatCard(
                  key: Key('tr-anal-$cli'),
                  label: 'تحاليل',
                  value: det ? n(clinicAnalyses(s, cli).total) : '—',
                  unit: cur,
                  color: BrandColors.green,
                  onTap: () => _showDetail('anal', cli),
                ),
              ],
            ),
            // v52 — بطاقة «ديون معلقة» أسفل كل عيادة أُزيلت نهائياً
            // بطلب المالك (إجمالي الديون في بطاقة الإجمالي بالأحمر).
            const SizedBox(height: 14),
          ],

          // ── م109 — بطاقة الإجمالي: شبكة خانات متوازية تُقرأ من نظرة ──
          //   صف الدخل (كاش | تحويل | تركيبات)، «المحصّل» بطلاً في شريط
          //   ذهبي، صف المصروفات (كاش | تحويل | الإجمالي)، شريط الصوافي
          //   الأخضر (صافي الكاش | صافي الخزينة)، وذيل الديون الأحمر
          //   ينقر لقسم الديون — نفس الأرقام والمفاتيح حرفياً.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Text('إجمالي ${s.month}',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.brandText)),
                  ),
                  const SizedBox(height: 10),
                  if (det) ...[
                    _rowLabel('الدخل (المدفوع)'),
                    Row(children: [
                      _GridCell(label: 'كاش', value: n(t.cash)),
                      const SizedBox(width: 6),
                      _GridCell(label: 'تحويل', value: n(t.xfer)),
                      const SizedBox(width: 6),
                      _GridCell(label: 'تركيبات', value: n(t.prosPaid)),
                    ]),
                    const SizedBox(height: 10),
                  ],
                  if (det)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(201, 162, 75, .10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color.fromRGBO(201, 162, 75, .30)),
                    ),
                    child: Column(children: [
                      Text('الدخل الفعلي (المحصّل)',
                          style: TextStyle(
                              fontSize: 11, color: BrandColors.mut2)),
                      Text('${n(t.grand)} $cur',
                          key: const Key('tr-grand'),
                          style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: BrandColors.goldDark,
                              fontFeatures: [
                                FontFeature.tabularFigures()
                              ])),
                    ]),
                  ),
                  // م125 — صف المصروفات يظهر للجميع (قرار المالك).
                  if (ex.total != 0) ...[
                    const SizedBox(height: 10),
                    _rowLabel('المصروفات'),
                    Row(children: [
                      _GridCell(
                          label: 'كاش',
                          value: n(ex.cash),
                          color: BrandColors.red,
                          bg: const Color.fromRGBO(192, 57, 43, .06)),
                      const SizedBox(width: 6),
                      _GridCell(
                          label: 'تحويل',
                          value: n(ex.xfer),
                          color: BrandColors.red,
                          bg: const Color.fromRGBO(192, 57, 43, .06)),
                      const SizedBox(width: 6),
                      _GridCell(
                          label: 'الإجمالي',
                          value: n(ex.total),
                          color: BrandColors.red,
                          bg: const Color.fromRGBO(192, 57, 43, .06)),
                    ]),
                    if (det) const SizedBox(height: 10),
                    // م125 — القيمة النهائية والصوافي تُخفى بلا الصلاحية.
                    if (det)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(46, 125, 90, .08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                const Color.fromRGBO(46, 125, 90, .25)),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(children: [
                            Text('صافي الكاش',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: BrandColors.mut2)),
                            const SizedBox(height: 2),
                            Text(n(t.cash - ex.cash),
                                key: const Key('tr-cash-net'),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: BrandColors.green,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ])),
                          ]),
                        ),
                        Container(
                            width: 1,
                            height: 30,
                            color:
                                const Color.fromRGBO(46, 125, 90, .25)),
                        Expanded(
                          child: Column(children: [
                            Text('صافي الخزينة (بعد الخصم)',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: BrandColors.mut2)),
                            const SizedBox(height: 2),
                            Text('${n(t.grand - ex.total)} $cur',
                                key: const Key('tr-grand-net'),
                                style: const TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w900,
                                    color: BrandColors.brand900,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ])),
                          ]),
                        ),
                      ]),
                    ),
                  ],
                  if (det) const SizedBox(height: 10),
                  if (det)
                  Material(
                    color: const Color.fromRGBO(192, 57, 43, .07),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: const Key('tr-open-debts'),
                      onTap: () => _goDebts(null),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        child: Row(children: [
                          const Icon(Icons.receipt_long_rounded,
                              size: 16, color: BrandColors.red),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text('إجمالي الديون (غير المحصّلة)',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: BrandColors.strong)),
                          ),
                          Text(n(t.debtRem),
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: BrandColors.red,
                                  fontFeatures: [
                                    FontFeature.tabularFigures()
                                  ])),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_left_rounded,
                              size: 18, color: BrandColors.mut),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // ── التفصيل ──
    final doctorPct = jsNumOr0(
        jsOr(ref.watch(appConfigProvider)['doctorPct'], 50));
    final labels = {
      'cash': 'كاش',
      'xfer': 'تحويل',
      'pros': 'تركيبات',
      'anal': 'تحاليل',
    };
    final items = filteredDetailItems(
      s,
      detailView!,
      detailCli,
      name: nameCtl.text.trim(),
      from: filterFrom,
      to: filterTo,
      sort: sortMode,
    );
    final groups = detailView == 'pros'
        ? _filteredGroups(s, doctorPct)
        : const <ProsGroup>[];
    final detailTotal = detailView == 'pros'
        ? groups.fold<num>(0, (t, g) => t + g.docTotal)
        : filteredDetailTotal(items);

    return ListView(
      key: const Key('treasury-detail'),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
      children: [
        // ── v60 — صف موحد بقالب السجلات (v59): [رجوع | العيادة+الفئة
        // | بحث ممتد | قمع أدوات واحد (فرز/نطاق تاريخ/طباعة)]. ──
        Row(children: [
          Material(
            color: BrandColors.brand600.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              key: const Key('tr-back'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => detailView = null),
              child: SizedBox(
                width: 38,
                height: 36,
                child: Icon(Icons.arrow_back_rounded,
                    size: 18, color: BrandColors.brandIcon),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(detailCli,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.brandText)),
                  Text('${labels[detailView]}',
                      style: TextStyle(
                          fontSize: 10.5, color: BrandColors.mut2)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                key: const Key('tr-search'),
                controller: nameCtl,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'بحث بالاسم...',
                  hintStyle: TextStyle(
                      fontSize: 12, color: BrandColors.mut2),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 16, color: BrandColors.mut2),
                  filled: true,
                  fillColor: BrandColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: BrandColors.line, width: .8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: BrandColors.line, width: .8),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // قمع الأدوات الواحد — يتلون عند تفعيل نطاق التاريخ.
          Builder(builder: (context) {
            final dateActive = showDateRange ||
                filterFrom.isNotEmpty ||
                filterTo.isNotEmpty;
            return Material(
              color: BrandColors.gold
                  .withValues(alpha: dateActive ? .18 : .08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                    color: BrandColors.gold.withValues(alpha: .3)),
              ),
              child: PopupMenuButton<String>(
                key: const Key('tr-tools'),
                tooltip: 'أدوات التفصيل',
                onSelected: (v) {
                  if (v == 'daterange') {
                    setState(() => showDateRange = !showDateRange);
                  } else if (v == 'print') {
                    _printDetail(items, groups, cur);
                  } else if (v.startsWith('sort:')) {
                    setState(() => sortMode = v.substring(5));
                  }
                },
                itemBuilder: (context) => [
                  for (final m in sortModes)
                    CheckedPopupMenuItem(
                      key: Key('tr-sort-$m'),
                      value: 'sort:$m',
                      checked: sortMode == m,
                      child: Text('${sortLabels[m]}',
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  const PopupMenuDivider(height: 6),
                  CheckedPopupMenuItem(
                    key: const Key('tr-daterange'),
                    value: 'daterange',
                    checked: dateActive,
                    child: const Text('نطاق تاريخ',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  const PopupMenuDivider(height: 6),
                  PopupMenuItem(
                    key: const Key('tr-print'),
                    value: 'print',
                    child: const Row(children: [
                      Icon(Icons.print_rounded,
                          size: 15, color: BrandColors.goldDark),
                      SizedBox(width: 8),
                      Text('طباعة',
                          style: TextStyle(fontSize: 12.5)),
                    ]),
                  ),
                ],
                child: const SizedBox(
                  width: 38,
                  height: 36,
                  child: Icon(Icons.filter_alt_outlined,
                      size: 16, color: BrandColors.goldDark),
                ),
              ),
            );
          }),
        ]),
        const SizedBox(height: 8),

        // تبويبات الفئات (+ «تحاليل» — نظام التحاليل المعزول)
        Row(children: [
          for (final cat in const [
            ('cash', 'كاش'),
            ('xfer', 'تحويل'),
            ('pros', 'تركيبات'),
            ('anal', 'تحاليل'),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Material(
                  color: detailView == cat.$1
                      ? BrandColors.goldDark
                      : BrandColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                        color: detailView == cat.$1
                            ? BrandColors.goldDark
                            : BrandColors.line),
                  ),
                  child: InkWell(
                    key: Key('tr-cat-${cat.$1}'),
                    borderRadius: BorderRadius.circular(24),
                    onTap: () =>
                        setState(() => detailView = cat.$1),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 9),
                      child: Center(
                        child: Text(cat.$2,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: detailView == cat.$1
                                    ? Colors.white
                                    : BrandColors.mut)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 8),

        // v60 — صف الفلاتر القديم أُزيل: البحث صعد للصف الموحد،
        // والفرز/نطاق التاريخ/الطباعة في قمع الأدوات.
        if (showDateRange)
          Row(children: [
            Expanded(
                child: _DateField(
                    key: const Key('tr-from'),
                    label: 'من',
                    value: filterFrom,
                    onPick: (v) => setState(() => filterFrom = v))),
            const SizedBox(width: 8),
            Expanded(
                child: _DateField(
                    key: const Key('tr-to'),
                    label: 'إلى',
                    value: filterTo,
                    onPick: (v) => setState(() => filterTo = v))),
            if (filterFrom.isNotEmpty || filterTo.isNotEmpty)
              TextButton(
                  onPressed: () => setState(() {
                        filterFrom = '';
                        filterTo = '';
                      }),
                  child: const Text('مسح')),
          ]),
        if (sortMode != 'date-desc')
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text('ترتيب: ${sortLabels[sortMode]}',
                style:
                    TextStyle(fontSize: 11.5, color: BrandColors.mut2)),
          ),
        const SizedBox(height: 6),

        // المحتوى
        if (detailView == 'pros')
          ..._prosCards(s, groups, cur, n)
        else if (items.isEmpty)
          Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('لا عناصر',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: BrandColors.mut2, fontSize: 12.5)),
            ),
          )
        // نظام «التحاليل» — بنودٌ قابلة للتعديل (القيمة/الطريقة) والحذف.
        else if (detailView == 'anal')
          for (final r in items) _analDetailTile(r, cur, n)
        else
          for (final r in items)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                dense: true,
                title: Text('${r['name'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${r['date'] ?? ''} · ${r['service'] ?? ''}',
                    style: const TextStyle(fontSize: 11)),
                trailing: Text('${n(jsNumOr0(r['amount']))} $cur',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.brand700)),
              ),
            ),

        // مجموع الفئة
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Text(
                    detailView == 'pros'
                        ? 'مجموع حصة الطبيب (تركيبات)'
                        : 'المجموع',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              Text('${n(detailTotal)} $cur',
                  key: const Key('tr-detail-total'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.goldDark)),
            ]),
          ),
        ),
      ],
    );
  }

  List<ProsGroup> _filteredGroups(TreasurySlice s, num doctorPct) {
    var groups = prosGrouped(s, detailCli, doctorPct);
    final q = nameCtl.text.trim();
    if (q.isNotEmpty || filterFrom.isNotEmpty || filterTo.isNotEmpty) {
      groups = [
        for (final g in groups)
          if (matchName(g.name, q))
            _refilterGroup(g, doctorPct),
      ].whereType<ProsGroup>().toList();
    }
    if (sortMode == 'name-asc') {
      groups.sort((a, b) => a.name.compareTo(b.name));
    } else if (sortMode == 'name-desc') {
      groups.sort((a, b) => b.name.compareTo(a.name));
    }
    return groups;
  }

  ProsGroup? _refilterGroup(ProsGroup g, num doctorPct) {
    final items = [
      for (final r in g.items)
        if (matchDate(r['date'] as String?, filterFrom, filterTo)) r,
    ];
    if (items.isEmpty) return null;
    final out = ProsGroup(g.name)..items.addAll(items);
    for (final r in items) {
      out.total += jsNumOr0(r['total']);
      if (r['_t'] == 'p' && jsTruthy(r['isDebt'])) continue;
      if (jsTruthy(r['isDebtPayment'])) {
        out.labTotal += prosPayLab(r, doctorPct);
        out.docTotal += prosPayDoc(r, doctorPct);
        out.clinTotal += prosPayClin(r, doctorPct);
      } else {
        out.labTotal += jsNumOr0(r['labValue']);
        out.docTotal += jsNumOr0(r['doctorShare']);
        out.clinTotal += jsNumOr0(r['clinicShare']);
      }
    }
    return out;
  }

  List<Widget> _prosCards(TreasurySlice s, List<ProsGroup> groups,
      String cur, String Function(Object?) n) {
    if (groups.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('لا تركيبات',
                textAlign: TextAlign.center,
                style: TextStyle(color: BrandColors.mut2, fontSize: 12.5)),
          ),
        ),
      ];
    }
    final repos = ref.read(reposProvider);
    final allRecords = repos.records.getAll();
    final allDebts = repos.debts.getAll();
    return [
      for (final g in groups)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            ListTile(
              key: Key('tr-prosgroup-${g.name}'),
              dense: true,
              title: Text(g.name,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.goldDark)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(spacing: 10, children: [
                  _hdStat('إجمالي', n(g.total), BrandColors.ink),
                  _hdStat('معمل', n(g.labTotal),
                      const Color(0xFFEA580C)),
                  _hdStat('طبيب', n(g.docTotal),
                      const Color(0xFF065F46)),
                  _hdStat('عيادة', n(g.clinTotal),
                      const Color(0xFF047857)),
                ]),
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (crossMonthPayments(g, allRecords, allDebts, s.month)
                    .isNotEmpty)
                  IconButton(
                    key: Key('tr-crossmonth-${g.name}'),
                    tooltip: 'دفعات بأشهر أخرى',
                    icon: const Icon(Icons.error_outline_rounded,
                        size: 17, color: BrandColors.goldDark),
                    onPressed: () => _showCrossMonth(
                        g, allRecords, allDebts, s.month, cur, n),
                  ),
                Icon(
                    expandedPros.contains(g.name)
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 19),
              ]),
              onTap: () => setState(() {
                if (!expandedPros.remove(g.name)) {
                  expandedPros.add(g.name);
                }
              }),
            ),
            if (expandedPros.contains(g.name))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Column(children: [
                  for (final cg in getCasesWithPayments(
                      g.items, allDebts, allRecords)) ...[
                    // ── رأس الحالة: النوع × الوحدات + إجمالي · معمل ──
                    Container(
                      key: Key('tr-case-${cg.pros['id']}'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color:
                            BrandColors.gold.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: BrandColors.gold
                                .withValues(alpha: .22)),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            '${jsOr(cg.pros['prosType'], 'تركيبة')}'
                            '${jsNumOr0(jsOr(cg.pros['prosUnits'], 1)) > 1 ? ' × ${jsNumOr0(cg.pros['prosUnits']).toStringAsFixed(0)}' : ''}',
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: BrandColors.goldDark),
                          ),
                        ),
                        Text(
                          'إجمالي: ${n(jsNumOr0(cg.pros['total']))} · معمل: ${n(jsNumOr0(cg.pros['labValue']))}',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: BrandColors.mut),
                        ),
                      ]),
                    ),
                    // ── شريط الدين المتبقي ──
                    if (jsTruthy(cg.pros['isDebt']) &&
                        cg.remaining > 0)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              BrandColors.red.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                              text: 'الدين المتبقي: ',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: BrandColors.mut)),
                          TextSpan(
                              text: n(cg.remaining),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: BrandColors.red)),
                          TextSpan(
                              text: ' $cur',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: BrandColors.mut2)),
                        ])),
                      ),
                    // ── كاش: بطاقة واحدة بحصص الصف ──
                    if (!jsTruthy(cg.pros['isDebt']))
                      _prosPayCard(
                        key: Key('tr-cash-${cg.pros['id']}'),
                        badge: '${jsOr(cg.pros['payment'], 'كاش')}',
                        badgeColor: const Color(0xFF16A34A),
                        amount: n(jsNumOr0(cg.pros['total'])),
                        date: '${jsOr(cg.pros['date'], '—')}',
                        parts: [
                          if (jsNumOr0(cg.pros['labValue']) > 0)
                            (
                              'معمل',
                              n(jsNumOr0(cg.pros['labValue'])),
                              const Color(0xFFEA580C)
                            ),
                          (
                            'طبيب',
                            n(jsNumOr0(cg.pros['doctorShare'])),
                            const Color(0xFF065F46)
                          ),
                          if (jsNumOr0(cg.pros['clinicShare']) > 0)
                            (
                              'عيادة',
                              n(jsNumOr0(cg.pros['clinicShare'])),
                              const Color(0xFF047857)
                            ),
                        ],
                      ),
                    // ── دفعات الدين المرقمة بأجزائها المجمدة ──
                    for (final pay in cg.payments)
                      _prosPayCard(
                        key: Key('tr-pay-${pay['id']}'),
                        badge: 'دفعة ${jsNumOr0(pay['_seq']).toStringAsFixed(0)}',
                        badgeColor: const Color(0xFF16A34A),
                        amount: n(jsNumOr0(
                            jsOr(pay['_fullAmount'], pay['amount']))),
                        date: '${jsOr(pay['date'], '—')}',
                        indent: true,
                        parts: [
                          if (prosPayLab(pay, doctorPctOf(ref)) > 0)
                            (
                              'معمل',
                              n(prosPayLab(pay, doctorPctOf(ref))),
                              const Color(0xFFEA580C)
                            ),
                          if (prosPayDoc(pay, doctorPctOf(ref)) > 0)
                            (
                              'طبيب',
                              n(prosPayDoc(pay, doctorPctOf(ref))),
                              const Color(0xFF065F46)
                            ),
                          if (prosPayClin(pay, doctorPctOf(ref)) > 0)
                            (
                              'عيادة',
                              n(prosPayClin(pay, doctorPctOf(ref))),
                              const Color(0xFF047857)
                            ),
                        ],
                      ),
                    // ── المدفوع/المتبقي للحالة (الدين فقط) ──
                    if (jsTruthy(cg.pros['isDebt']))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          Expanded(
                            child: Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: 'المدفوع: ',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: BrandColors.mut)),
                              TextSpan(
                                  text: n(cg.paid),
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF065F46))),
                            ])),
                          ),
                          Text.rich(TextSpan(children: [
                            TextSpan(
                                text: 'المتبقي: ',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: BrandColors.mut)),
                            TextSpan(
                                text: n(cg.remaining),
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: cg.remaining > 0
                                        ? BrandColors.red
                                        : const Color(0xFF065F46))),
                          ])),
                        ]),
                      ),
                  ],
                  // ── تذييل الأربع خانات ──
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: BrandColors.surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: BrandColors.line),
                    ),
                    child: Row(children: [
                      _totBox('إجمالي', n(g.total), BrandColors.ink),
                      _totBox('معمل', n(g.labTotal),
                          const Color(0xFFEA580C)),
                      _totBox('طبيب', n(g.docTotal),
                          const Color(0xFF065F46)),
                      _totBox('عيادة', n(g.clinTotal),
                          const Color(0xFF047857)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
    ];
  }

  /// نسبة الطبيب العامة (احتياط الدفعات القديمة بلا أجزاء مجمدة).
  static num doctorPctOf(WidgetRef ref) =>
      jsNumOr0(jsOr(ref.read(appConfigProvider)['doctorPct'], 50));

  Widget _hdStat(String label, String value, Color color) =>
      Text.rich(TextSpan(children: [
        TextSpan(
            text: '$label: ',
            style: TextStyle(fontSize: 11, color: BrandColors.mut2)),
        TextSpan(
            text: value,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color)),
      ]));

  Widget _totBox(String label, String value, Color color) => Expanded(
        child: Column(children: [
          Text(label,
              style:
                  TextStyle(fontSize: 11.5, color: BrandColors.mut2)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ]),
      );

  /// بطاقة دفعة/كاش — pros-pay-card حرفياً: شارة + أجزاء يمين، مبلغ +
  /// تاريخ يسار، وحد أيمن ذهبي للدفعات المزاحة.
  Widget _prosPayCard({
    required Key key,
    required String badge,
    required Color badgeColor,
    required String amount,
    required String date,
    required List<(String, String, Color)> parts,
    bool indent = false,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      margin: EdgeInsets.only(top: 4, right: indent ? 12 : 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BrandColors.line),
      ),
      foregroundDecoration: indent
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border(
                  right: BorderSide(
                      color: BrandColors.gold.withValues(alpha: .35),
                      width: 2)),
            )
          : null,
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badge,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: badgeColor)),
              ),
              if (parts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Wrap(spacing: 8, children: [
                    for (final part in parts)
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: '${part.$1}: ',
                            style: TextStyle(
                                fontSize: 11,
                                color: BrandColors.mut2)),
                        TextSpan(
                            text: part.$2,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: part.$3)),
                      ])),
                  ]),
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(amount,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w900)),
            Text(date,
                style: TextStyle(
                    fontSize: 11.5, color: BrandColors.mut2)),
          ],
        ),
      ]),
    );
  }

  // ── نظام «التحاليل» — بند تفصيلٍ قابل للتعديل والحذف ─────────────────────

  /// بطاقة بند تحليلٍ: الاسم/التاريخ + القيمة والطريقة، مع زرّي تعديل وحذف
  /// خاضعين لصلاحيات records.edit/records.delete (والعرض خلف treasury.details).
  Widget _analDetailTile(JMap r, String cur, String Function(Object?) n) {
    final canEdit = staffAllowed('records.edit');
    final canDel = staffAllowed('records.delete');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        title: Text('${r['name'] ?? ''}',
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700)),
        subtitle: Text(
            '${r['date'] ?? ''} · ${r['analysisName'] ?? r['service'] ?? ''}'
            ' · ${r['payment'] ?? ''}',
            style: const TextStyle(fontSize: 11)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${n(jsNumOr0(r['amount']))} $cur',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: BrandColors.green)),
          if (canEdit)
            IconButton(
              key: Key('tr-anal-edit-${r['id']}'),
              visualDensity: VisualDensity.compact,
              tooltip: 'تعديل',
              icon: Icon(Icons.edit_rounded,
                  size: 15, color: BrandColors.brandIcon),
              onPressed: () => _editAnalysis(r),
            ),
          if (canDel)
            IconButton(
              key: Key('tr-anal-del-${r['id']}'),
              visualDensity: VisualDensity.compact,
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_rounded,
                  size: 15, color: BrandColors.red),
              onPressed: () => _deleteAnalysis(r),
            ),
        ]),
      ),
    );
  }

  /// تعديل قيمة/طريقة تحليلٍ عبر records.update (يبقى صفاً محروساً isAnalysis).
  Future<void> _editAnalysis(JMap r) async {
    final id = '${r['id']}';
    final priceCtl =
        TextEditingController(text: jsNumOr0(r['amount']).toStringAsFixed(0));
    var pay = '${r['payment'] ?? 'كاش'}';
    if (pay != 'كاش' && pay != 'تحويل') pay = 'كاش';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) => AlertDialog(
          title: Text('تعديل تحليل — ${r['name'] ?? ''}',
              style: const TextStyle(fontSize: 14)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('tr-anal-edit-price'),
              controller: priceCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'القيمة', isDense: true),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('tr-anal-edit-pay'),
              initialValue: pay,
              decoration: const InputDecoration(
                  labelText: 'طريقة الدفع', isDense: true),
              items: const [
                DropdownMenuItem(value: 'كاش', child: Text('كاش')),
                DropdownMenuItem(value: 'تحويل', child: Text('تحويل')),
              ],
              onChanged: (v) => setLocal(() => pay = v ?? 'كاش'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                key: const Key('tr-anal-edit-save'),
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    priceCtl.dispose();
    if (ok != true) return;
    final price = jsNumOr0(priceCtl.text);
    if (price <= 0) return;
    ref.read(reposProvider).records.updateLocal(id, {
      'amount': price,
      'payment': pay,
    });
    ref.read(financeRevProvider.notifier).state++;
    if (mounted) setState(() {});
  }

  /// حذف صف تحليلٍ (records.delete نظيف — لا دين ولا دفعات متسلسلة).
  Future<void> _deleteAnalysis(JMap r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('حذف التحليل', style: TextStyle(fontSize: 14)),
        content: Text(
            'حذف تحليل «${r['analysisName'] ?? r['name'] ?? ''}» بقيمة '
            '${jsNumOr0(r['amount']).toStringAsFixed(0)}؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              key: const Key('tr-anal-del-confirm'),
              style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.red),
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(reposProvider).records.delete('${r['id']}');
    ref.read(financeRevProvider.notifier).state++;
    if (mounted) setState(() {});
  }

  void _showCrossMonth(ProsGroup g, List<JMap> records, List<JMap> debts,
      String month, String cur, String Function(Object?) n) {
    final items = crossMonthPayments(g, records, debts, month);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('دفعات ${g.name} بأشهر أخرى'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(
                      child: Text('${r['date'] ?? ''}',
                          style: const TextStyle(fontSize: 12))),
                  Text('${n(jsNumOr0(r['amount']))} $cur',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Future<void> _printDetail(
      List<JMap> items, List<ProsGroup> groups, String cur) async {
    final fonts = await loadPdfBrand(ref);
    final labels = {
      'cash': 'كاش',
      'xfer': 'تحويل',
      'pros': 'تركيبات',
      'anal': 'تحاليل',
    };
    // نظام «التحاليل» — طباعة جدولٍ بسيط (التاريخ/التحليل/الطريقة/القيمة).
    if (detailView == 'anal') {
      final n = formatNumber;
      num sum = 0;
      final tableRows = <List<String>>[];
      for (final r in items) {
        final amt = jsNumOr0(r['amount']);
        sum += amt;
        tableRows.add([
          '${r['date'] ?? ''}',
          '${r['name'] ?? ''}',
          '${r['analysisName'] ?? r['service'] ?? ''}',
          '${r['payment'] ?? ''}',
          '${n(amt)} $cur',
        ]);
      }
      final bytes = await simpleTablePdf(
        fonts,
        title: '$detailCli — تحاليل',
        subtitle: ref.read(selectedMonthProvider),
        headers: const ['التاريخ', 'الاسم', 'التحليل', 'الطريقة', 'القيمة'],
        rows: tableRows,
        totRow: ['المجموع', '', '', '', '${n(sum)} $cur'],
      );
      final msg = await printOrSharePdf(ref.read(dbDirProvider), bytes,
          'treasury_${detailCli}_anal.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }
    // v51 — طباعة التركيبات بالتصميم الجديد (هوية الكاش والتحويل):
    // نفس المجموعات المعروضة على الشاشة ونفس نسبة الطبيب — تطابق تام
    // بين أرقام الورقة وأرقام التطبيق.
    final bytes = detailView == 'pros'
        ? await prostheticsReportPdf(
            fonts,
            title: '$detailCli — تركيبات',
            subtitle: ref.read(selectedMonthProvider),
            currency: cur,
            groups: groups,
            doctorPct: jsNumOr0(
                jsOr(ref.read(appConfigProvider)['doctorPct'], 50)),
          )
        // م38 — توأم الأصل (TreasuryTab.printDetail): جداول المعالجات
        // المجمّعة بنسبتي الطبيب/العيادة لكل معالجة متشابهة + الإجمالي
        // النهائي — كان جدولاً مسطحاً بلا نسب إطلاقاً.
        : await treatmentTablesPdf(
            fonts,
            title: '$detailCli — ${labels[detailView]}',
            subtitle: ref.read(selectedMonthProvider),
            currency: cur,
            tables: buildTreatmentTables(
              items,
              fallbackPct: jsNumber(
                          ref.read(appConfigProvider)['doctorPct'])
                      .isFinite
                  ? jsNumber(
                      ref.read(appConfigProvider)['doctorPct'])
                  : 50,
            ),
          );
    final msg = await printOrSharePdf(ref.read(dbDirProvider), bytes,
        'treasury_${detailCli}_$detailView.pdf');
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

/// نظام «التحاليل» — بطاقة إحصاءٍ بعرضٍ ثابت لشبكة Wrap (توأم _StatCard
/// لكن بلا Expanded كي يصفّها Wrap صفّين على الشاشات الضيّقة).
class _WrapStatCard extends StatelessWidget {
  const _WrapStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // عرض نصف الصف تقريباً (بطاقتان في السطر) مع طرح تباعد Wrap.
    final w = (MediaQuery.sizeOf(context).width - 28 - 6) / 2;
    return SizedBox(
      width: w.clamp(120.0, 300.0),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Text(label,
                  style: TextStyle(fontSize: 11.5, color: BrandColors.mut)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
              Text(unit,
                  style: TextStyle(fontSize: 11.5, color: BrandColors.faint)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// م109 — تسمية صفٍّ صغيرة فوق شبكة خانات بطاقة الإجمالي.
Widget _rowLabel(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 2),
      child: Text(s,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: BrandColors.mut)),
    );

/// م109 — خانة شبكة بطاقة الإجمالي: تسمية صغيرة فوق رقمٍ عريض بأرقام
/// جدولية داخل صندوق مظلل — أعمدة متوازية تُقرأ وتُجمع من النظرة الأولى.
class _GridCell extends StatelessWidget {
  const _GridCell(
      {required this.label, required this.value, this.color, this.bg});

  final String label;
  final String value;
  final Color? color;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: bg ?? BrandColors.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                maxLines: 1,
                style:
                    TextStyle(fontSize: 10.5, color: BrandColors.mut2)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: color ?? BrandColors.brand700,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ]),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final String value;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate:
              value.isEmpty ? DateTime.now() : DateTime.parse(value),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked != null) {
          onPick('${picked.year.toString().padLeft(4, '0')}-'
              '${picked.month.toString().padLeft(2, '0')}-'
              '${picked.day.toString().padLeft(2, '0')}');
        }
      },
      child: Text(value.isEmpty ? label : '$label: $value',
          style: const TextStyle(fontSize: 11)),
    );
  }
}
