/// ============================================================================
///  الخزينة — نسخة سطح المكتب: Master/Detail بتكافؤٍ حرفيٍّ مع الهاتف
/// ============================================================================
///
///  (قرار المالك، تدقيق التكافؤ): يمين بطاقةٌ مستقلة لكل عيادة بثلاث خانات
///  قابلة للنقر (كاش/تحويل/تركيبات) كالهاتف؛ النقر يفتح القسم الأيسر بتفصيل
///  الفئة (قائمة المرضى/البحث/الفرز/نطاق التاريخ/الطباعة + إجمالي الفئة)؛
///  وأسفل الشاشة بعرضها شريط الإجماليات: الدخل الفعلي المحصّل قبل خصم
///  المصروفات، صف المصروفات (كاش/تحويل/الإجمالي)، الصوافي بعد الخصم، وذيل
///  «ديون معلقة» ينقر لتبويب الديون المكتبي.
///
///  - المنطق كله من treasury_logic.dart (نقيّ، مستورد أصلاً) بلا أي تعديل:
///    clinicCash/clinicXfer/clinicProsTotalPaid، filteredDetailItems/Total،
///    prosGrouped/getCasesWithPayments، crossMonthPayments، applySorting.
///  - الطباعة توأم _printDetail الهاتفي حرفياً: تركيبات ← prostheticsReportPdf،
///    كاش/تحويل ← treatmentTablesPdf، عبر printOrSharePdf وloadPdfBrand.
///  - صلاحية treasury.details كالهاتف: البطاقات تظهر دائماً والأرقام «—»
///    بدونها، وبطاقة الإجماليات/الصوافي/الديون تُحجب، وصف المصروفات يظهر
///    للجميع متى وُجد.
///  - مفتاح DesktopSplitView: 'treasury'. مفاتيح العناصر الجديدة tr-desk-*.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/js_compat.dart';
import '../../finance/analyses_filter.dart' show filterAnalysesRows;
import '../../finance/debts_section.dart' show debtsClinicFilterProvider;
import '../../finance/finance_screen.dart' show financeRevProvider;
import '../../finance/treasury_logic.dart';
import '../../print/print_service.dart' show loadPdfBrand, printOrSharePdf;
import '../../print/reports.dart'
    show prostheticsReportPdf, simpleTablePdf, treatmentTablesPdf;
import '../../print/treatment_tables.dart'
    show buildTreatmentTables, formatNumber;
import '../../staff/staff_gate.dart' show staffAllowed;
import '../desktop_prefs.dart'
    show desktopPrefsProvider, saveDesktopPref;
import '../desktop_shell.dart' show desktopTabProvider;
import '../widgets/split_view.dart' show DesktopSplitView;

typedef _JMap = Map<String, Object?>;

/// مفتاح حفظ حالة طيّ شريط الإجماليات (محلي للجهاز، افتراضي موسّع).
const _kTotalsExpandedKey = 'treasury.totals.expanded';

class DesktopTreasuryScreen extends ConsumerStatefulWidget {
  const DesktopTreasuryScreen({super.key});

  @override
  ConsumerState<DesktopTreasuryScreen> createState() =>
      _DesktopTreasuryScreenState();
}

class _DesktopTreasuryScreenState
    extends ConsumerState<DesktopTreasuryScreen> {
  /// الفئة المختارة في التفصيل: null = لا تفصيل، 'cash'/'xfer'/'pros'.
  String? _detailView;

  /// عيادة التفصيل المختار.
  String _detailCli = '';

  final _nameCtl = TextEditingController();
  String _filterFrom = '';
  String _filterTo = '';
  bool _showDateRange = false;
  String _sortMode = 'date-desc';

  // ── حالة بحث/فلتر التحاليل (محلية — تُصفَّر عند تغيير الفئة مقبول) ──
  final _analSearchCtl = TextEditingController();
  /// وضع فلتر التحاليل: 'all' | 'cash' | 'transfer'
  String _analFilterMode = 'all';

  /// مجموعات التركيبات الموسّعة في التفصيل.
  final _expandedPros = <String>{};

  /// تجاوزٌ محليٌّ لحالة طيّ شريط الإجماليات — null = اتبع المحفوظ
  /// (والافتراضي موسّع)؛ التجاوز يتقدّم على القرص كي يبين الأثر فوراً.
  bool? _totalsExpanded;

  @override
  void dispose() {
    _nameCtl.dispose();
    _analSearchCtl.dispose();
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

  /// فتح تفصيل فئةٍ لعيادة (يصفّر الفلاتر كالهاتف _showDetail).
  void _showDetail(String type, String cli) => setState(() {
        _detailView = type;
        _detailCli = cli;
        _nameCtl.clear();
        _filterFrom = '';
        _filterTo = '';
      });

  /// القفز لتبويب الديون المكتبي بفلتر العيادة — توأم _goDebts الهاتفي
  /// لكن على مبدّل تبويبات سطح المكتب لا financeSectionProvider.
  void _goDebts(String? clinic) {
    ref.read(debtsClinicFilterProvider.notifier).state = clinic ?? '';
    ref.read(desktopTabProvider.notifier).state = 'debts';
  }

  @override
  Widget build(BuildContext context) {
    final s = _slice();
    final cur = ref.watch(currencyProvider);
    final clinics = ref.watch(clinicsProvider);
    final n = formatNumber;
    final det = staffAllowed('treasury.details');
    final t = treasuryTotals(s);
    final ex = ref.watch(reposProvider).expenses.monthExpenseTotals(s.month);

    // حالة طيّ شريط الإجماليات: التجاوز المحلي أولاً، ثم المحفوظ، ثم موسّع
    // افتراضاً (الوضع الموسّع هو السلوك المطلوب عند أول فتح).
    final savedTotals =
        ref.watch(desktopPrefsProvider)[_kTotalsExpandedKey];
    final totalsExpanded = _totalsExpanded ??
        (savedTotals is bool ? savedTotals : true);

    // ── اللوح الرئيسي (يمين): بطاقات العيادات + شريط الإجماليات السفلي ──
    final master = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // رأسٌ خفيف: الشهر (اختياره من هيدر الصدفة، هنا عرض فقط).
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(children: [
            Icon(Icons.account_balance_rounded,
                size: 18, color: BrandColors.goldDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text('خزينة ${s.month}',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.brandText)),
            ),
          ]),
        ),
        // شبكة بطاقات العيادات عمودين — بطاقة مستقلة بثلاث خانات لكل عيادة.
        // (استبدلت ListView العمودي: تعبئة أفقية عمودين تقلّص التمرير للنصف
        // وتستغل عرض اللوح؛ mainAxisExtent 92 يطابق ارتفاع البطاقة الحالي.)
        Expanded(
          child: clinics.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text('لا عيادات مُعدّة',
                        style: TextStyle(
                            fontSize: 13, color: BrandColors.mut)),
                  ),
                )
              : GridView.builder(
                  key: const Key('tr-desk-clinics'),
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    // نظام «التحاليل» — البطاقة صارت بصفّين من الخانات
                    // (كاش/تحويل ثم تركيبات/تحاليل) فيرتفع الطبيعي إلى ~232؛
                    // نُثبّته كي لا تُقصّ الخانة الرابعة (RenderFlex overflow).
                    mainAxisExtent: 232,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: clinics.length,
                  itemBuilder: (ctx, i) {
                    final cli = clinics[i];
                    return _ClinicCard(
                      key: Key('tr-desk-clinic-$cli'),
                      clinic: cli,
                      cur: cur,
                      det: det,
                      activeCat: _detailCli == cli ? _detailView : null,
                      cash: n(clinicCash(s, cli)),
                      xfer: n(clinicXfer(s, cli)),
                      pros: n(clinicProsTotalPaid(s, cli)),
                      anal: n(clinicAnalyses(s, cli).total),
                      onTapCash: () => _showDetail('cash', cli),
                      onTapXfer: () => _showDetail('xfer', cli),
                      onTapPros: () => _showDetail('pros', cli),
                      onTapAnal: () => _showDetail('anal', cli),
                    );
                  },
                ),
        ),
        // ── شريط الإجماليات السفلي اللاصق القابل للطي — بعرض اللوح ──
        _TotalsBar(
          cur: cur,
          det: det,
          totals: t,
          // نظام «التحاليل» — إجمالٍ منفصلٌ عن grand (سطرٌ مستقل).
          analyses: analysesTotals(s),
          expenses: ex,
          expanded: totalsExpanded,
          onToggleExpand: () {
            final next = !totalsExpanded;
            setState(() => _totalsExpanded = next);
            saveDesktopPref(ref, _kTotalsExpandedKey, next);
          },
          onOpenDebts: () => _goDebts(null),
        ),
      ],
    );

    // ── لوح التفصيل (يسار): تفصيل الفئة المختارة ──
    //   لا نغلّفه بـ DetailHost (ملاّح متداخل) عمداً: التفصيل لا يدفع صفحاتٍ
    //   فرعية، وتغليفه كان يجمّد الودجة على أول توليد للمسار فلا ينعكس
    //   توسيع مجموعات التركيبات ولا تبديل الفلاتر. تمريره مباشرةً يبقي
    //   setState يعيد البناء طبيعياً (مع ValueKey ثابت للفئة/العيادة كي
    //   يتحرك AnimatedSwitcher عند تبدّل الاختيار).
    final detailWidget = _detailView == null
        ? null
        : KeyedSubtree(
            key: ValueKey('tr-desk-detail-$_detailCli-$_detailView'),
            child: _buildDetail(s, cur, n, det),
          );

    return DesktopSplitView(
      id: 'treasury',
      emptyIcon: Icons.account_balance_rounded,
      emptyTitle: 'اختر عملية لعرض التفاصيل',
      emptyHint: 'اضغط كاش أو تحويل أو تركيبات على بطاقة عيادة',
      masterWidth: 460,
      minMasterWidth: 360,
      maxMasterWidth: 620,
      master: master,
      detail: detailWidget,
    );
  }

  // ── لوح التفصيل ─────────────────────────────────────────────────────────

  Widget _buildDetail(
      TreasurySlice s, String cur, String Function(Object?) n, bool det) {
    // نسبة الطبيب من الإعداد كما يمرره الهاتف (لحصص التركيبات).
    final doctorPct =
        jsNumOr0(jsOr(ref.watch(appConfigProvider)['doctorPct'], 50));
    final labels = {
      'cash': 'كاش',
      'xfer': 'تحويل',
      'pros': 'تركيبات',
      'anal': 'تحاليل',
    };
    final items = filteredDetailItems(
      s,
      _detailView!,
      _detailCli,
      name: _nameCtl.text.trim(),
      from: _filterFrom,
      to: _filterTo,
      sort: _sortMode,
    );
    final groups = _detailView == 'pros'
        ? _filteredGroups(s, doctorPct)
        : const <ProsGroup>[];
    final detailTotal = _detailView == 'pros'
        ? groups.fold<num>(0, (t, g) => t + g.docTotal)
        : filteredDetailTotal(items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── الترويسة: العيادة+الفئة | بحث | قمع أدوات (فرز/تاريخ/طباعة) ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          color: BrandColors.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: BrandColors.gold.withValues(alpha: .12),
                    border: Border.all(
                        color: BrandColors.gold.withValues(alpha: .35)),
                  ),
                  child: Icon(Icons.payments_rounded,
                      size: 20, color: BrandColors.goldDark),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_detailCli,
                          key: const Key('tr-desk-detail-clinic'),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: BrandColors.brandText)),
                      Text('${labels[_detailView]}',
                          style: TextStyle(
                              fontSize: 11.5, color: BrandColors.mut2)),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('tr-desk-detail-close'),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: BrandColors.mut,
                  tooltip: 'إغلاق',
                  onPressed: () => setState(() => _detailView = null),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      key: const Key('tr-desk-search'),
                      controller: _nameCtl,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'بحث بالاسم...',
                        hintStyle: TextStyle(
                            fontSize: 12, color: BrandColors.mut2),
                        prefixIcon: Icon(Icons.search_rounded,
                            size: 16, color: BrandColors.mut2),
                        filled: true,
                        fillColor: BrandColors.surface2,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: BrandColors.line, width: .8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: BrandColors.line, width: .8),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // قمع الأدوات الواحد — يتلوّن عند تفعيل نطاق التاريخ.
                Builder(builder: (context) {
                  final dateActive = _showDateRange ||
                      _filterFrom.isNotEmpty ||
                      _filterTo.isNotEmpty;
                  return Material(
                    color: BrandColors.gold
                        .withValues(alpha: dateActive ? .18 : .08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                          color: BrandColors.gold.withValues(alpha: .3)),
                    ),
                    child: PopupMenuButton<String>(
                      key: const Key('tr-desk-tools'),
                      tooltip: 'أدوات التفصيل',
                      onSelected: (v) {
                        if (v == 'daterange') {
                          setState(
                              () => _showDateRange = !_showDateRange);
                        } else if (v == 'print') {
                          _printDetail(items, groups, cur);
                        } else if (v.startsWith('sort:')) {
                          setState(() => _sortMode = v.substring(5));
                        }
                      },
                      itemBuilder: (context) => [
                        for (final m in sortModes)
                          CheckedPopupMenuItem(
                            key: Key('tr-desk-sort-$m'),
                            value: 'sort:$m',
                            checked: _sortMode == m,
                            child: Text('${sortLabels[m]}',
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                        const PopupMenuDivider(height: 6),
                        CheckedPopupMenuItem(
                          key: const Key('tr-desk-daterange'),
                          value: 'daterange',
                          checked: dateActive,
                          child: const Text('نطاق تاريخ',
                              style: TextStyle(fontSize: 12.5)),
                        ),
                        const PopupMenuDivider(height: 6),
                        PopupMenuItem(
                          key: const Key('tr-desk-print'),
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
                        width: 40,
                        height: 36,
                        child: Icon(Icons.filter_alt_outlined,
                            size: 16, color: BrandColors.goldDark),
                      ),
                    ),
                  );
                }),
              ]),
              const SizedBox(height: 8),
              // تبويبات التنقل بين الفئات (+ «تحاليل» — النظام المعزول).
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
                        color: _detailView == cat.$1
                            ? BrandColors.goldDark
                            : BrandColors.surface2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                              color: _detailView == cat.$1
                                  ? BrandColors.goldDark
                                  : BrandColors.line),
                        ),
                        child: InkWell(
                          key: Key('tr-desk-cat-${cat.$1}'),
                          borderRadius: BorderRadius.circular(24),
                          onTap: () =>
                              setState(() => _detailView = cat.$1),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: Text(cat.$2,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: _detailView == cat.$1
                                          ? Colors.white
                                          : BrandColors.mut)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
              if (_showDateRange) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: _DateField(
                          key: const Key('tr-desk-from'),
                          label: 'من',
                          value: _filterFrom,
                          onPick: (v) =>
                              setState(() => _filterFrom = v))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _DateField(
                          key: const Key('tr-desk-to'),
                          label: 'إلى',
                          value: _filterTo,
                          onPick: (v) =>
                              setState(() => _filterTo = v))),
                  if (_filterFrom.isNotEmpty || _filterTo.isNotEmpty)
                    TextButton(
                        onPressed: () => setState(() {
                              _filterFrom = '';
                              _filterTo = '';
                            }),
                        child: const Text('مسح')),
                ]),
              ],
              if (_sortMode != 'date-desc')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('ترتيب: ${sortLabels[_sortMode]}',
                      style: TextStyle(
                          fontSize: 11.5, color: BrandColors.mut2)),
                ),
            ],
          ),
        ),
        // ── المحتوى: قائمة البنود أو بطاقات التركيبات المجمّعة ──
        Expanded(
          child: ListView(
            key: const Key('tr-desk-detail-list'),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            children: [
              if (_detailView == 'pros')
                ..._prosCards(s, groups, cur, n)
              else if (items.isEmpty && _detailView != 'anal')
                _emptyCard('لا عناصر')
              // نظام «التحاليل» — شريط بحث/فلتر ثم البنود القابلة للتعديل والحذف.
              else if (_detailView == 'anal') ...[
                // ── شريط البحث والفلتر الخاص بالتحاليل ───────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    // حقل البحث — يحاكي زخرفة tr-desk-search
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          key: const Key('tr-desk-anal-search'),
                          controller: _analSearchCtl,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'بحث في التحاليل…',
                            hintStyle: TextStyle(
                                fontSize: 12, color: BrandColors.mut2),
                            prefixIcon: Icon(Icons.search_rounded,
                                size: 16, color: BrandColors.mut2),
                            filled: true,
                            fillColor: BrandColors.surface2,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color: BrandColors.line, width: .8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                  color: BrandColors.line, width: .8),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // زر الفلتر مع شارة الوضع غير الافتراضي
                    Builder(builder: (context) {
                      final filterActive = _analFilterMode != 'all';
                      return Stack(clipBehavior: Clip.none, children: [
                        Material(
                          color: BrandColors.gold.withValues(
                              alpha: filterActive ? .18 : .08),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                                color: BrandColors.gold
                                    .withValues(alpha: .3)),
                          ),
                          child: PopupMenuButton<String>(
                            key: const Key('tr-desk-anal-filter'),
                            tooltip: 'فلتر التحاليل',
                            onSelected: (v) =>
                                setState(() => _analFilterMode = v),
                            itemBuilder: (context) => [
                              CheckedPopupMenuItem(
                                key: const Key(
                                    'tr-desk-anal-filter-all'),
                                value: 'all',
                                checked: _analFilterMode == 'all',
                                child: const Text('جميع التحاليل',
                                    style: TextStyle(fontSize: 12.5)),
                              ),
                              CheckedPopupMenuItem(
                                key: const Key(
                                    'tr-desk-anal-filter-cash'),
                                value: 'cash',
                                checked: _analFilterMode == 'cash',
                                child: const Text('تحاليل كاش',
                                    style: TextStyle(fontSize: 12.5)),
                              ),
                              CheckedPopupMenuItem(
                                key: const Key(
                                    'tr-desk-anal-filter-transfer'),
                                value: 'transfer',
                                checked: _analFilterMode == 'transfer',
                                child: const Text('تحاليل تحويل',
                                    style: TextStyle(fontSize: 12.5)),
                              ),
                            ],
                            child: const SizedBox(
                              width: 38,
                              height: 36,
                              child: Icon(Icons.filter_list_rounded,
                                  size: 16, color: BrandColors.goldDark),
                            ),
                          ),
                        ),
                        // شارة صغيرة تُظهر الوضع غير الافتراضي
                        if (filterActive)
                          Positioned(
                            top: -4,
                            left: -4,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: BrandColors.goldDark,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: BrandColors.surface,
                                    width: 1.5),
                              ),
                            ),
                          ),
                      ]);
                    }),
                  ]),
                ),
                // ── بنود التحاليل بعد الفلتر ──────────────────────────────
                ..._buildDeskAnalItems(items, cur),
              ] else
                for (final r in items)
                  _ItemTile(row: r, cur: cur),
            ],
          ),
        ),
        // ── مجموع الفئة أسفل القائمة ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: BoxDecoration(
            color: BrandColors.surface,
            border: Border(
                top: BorderSide(color: BrandColors.line, width: .8)),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                  _detailView == 'pros'
                      ? 'مجموع حصة الطبيب (تركيبات)'
                      : 'المجموع',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            Text('${n(detailTotal)} $cur',
                key: const Key('tr-desk-detail-total'),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: BrandColors.goldDark,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        ),
      ],
    );
  }

  Widget _emptyCard(String msg) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(msg,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: BrandColors.mut2, fontSize: 12.5)),
        ),
      );

  // ── بناء بنود التحاليل بعد تطبيق الفلتر (عرضي — المجاميع لا تتأثر) ─────

  List<Widget> _buildDeskAnalItems(List<_JMap> allItems, String cur) {
    final filtered = filterAnalysesRows(
      allItems,
      query: _analSearchCtl.text,
      mode: _analFilterMode,
    );
    if (filtered.isEmpty) {
      return [_emptyCard('لا نتائج مطابقة')];
    }
    return [
      for (final r in filtered)
        _AnalItemTile(
          row: r,
          cur: cur,
          onEdit: () => _editAnalysis(r),
          onDelete: () => _deleteAnalysis(r),
        ),
    ];
  }

  // ── تجميع/فلترة التركيبات (توأم _filteredGroups الهاتفي) ─────────────────

  List<ProsGroup> _filteredGroups(TreasurySlice s, num doctorPct) {
    var groups = prosGrouped(s, _detailCli, doctorPct);
    final q = _nameCtl.text.trim();
    if (q.isNotEmpty || _filterFrom.isNotEmpty || _filterTo.isNotEmpty) {
      groups = [
        for (final g in groups)
          if (matchName(g.name, q)) _refilterGroup(g, doctorPct),
      ].whereType<ProsGroup>().toList();
    }
    if (_sortMode == 'name-asc') {
      groups.sort((a, b) => a.name.compareTo(b.name));
    } else if (_sortMode == 'name-desc') {
      groups.sort((a, b) => b.name.compareTo(a.name));
    }
    return groups;
  }

  ProsGroup? _refilterGroup(ProsGroup g, num doctorPct) {
    final items = [
      for (final r in g.items)
        if (matchDate(r['date'] as String?, _filterFrom, _filterTo)) r,
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

  // ── بطاقات التركيبات المجمّعة (المكافئ المكتبي لـ _prosCards الهاتفي) ─────

  List<Widget> _prosCards(TreasurySlice s, List<ProsGroup> groups,
      String cur, String Function(Object?) n) {
    if (groups.isEmpty) return [_emptyCard('لا تركيبات')];
    final repos = ref.read(reposProvider);
    final allRecords = repos.records.getAll();
    final allDebts = repos.debts.getAll();
    return [
      for (final g in groups)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            ListTile(
              key: Key('tr-desk-prosgroup-${g.name}'),
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
                    key: Key('tr-desk-crossmonth-${g.name}'),
                    tooltip: 'دفعات بأشهر أخرى',
                    icon: const Icon(Icons.error_outline_rounded,
                        size: 17, color: BrandColors.goldDark),
                    onPressed: () => _showCrossMonth(
                        g, allRecords, allDebts, s.month, cur, n),
                  ),
                Icon(
                    _expandedPros.contains(g.name)
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 19),
              ]),
              onTap: () => setState(() {
                if (!_expandedPros.remove(g.name)) {
                  _expandedPros.add(g.name);
                }
              }),
            ),
            if (_expandedPros.contains(g.name))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Column(children: [
                  for (final cg in getCasesWithPayments(
                      g.items, allDebts, allRecords)) ...[
                    // رأس الحالة: النوع × الوحدات + إجمالي · معمل.
                    Container(
                      key: Key('tr-desk-case-${cg.pros['id']}'),
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: BrandColors.gold.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                BrandColors.gold.withValues(alpha: .22)),
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
                              fontSize: 11.5, color: BrandColors.mut),
                        ),
                      ]),
                    ),
                    // شريط الدين المتبقي.
                    if (jsTruthy(cg.pros['isDebt']) && cg.remaining > 0)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: BrandColors.red.withValues(alpha: .07),
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
                    // كاش: بطاقة واحدة بحصص الصف.
                    if (!jsTruthy(cg.pros['isDebt']))
                      _prosPayCard(
                        key: Key('tr-desk-cash-${cg.pros['id']}'),
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
                    // دفعات الدين المرقمة بأجزائها المجمّدة.
                    for (final pay in cg.payments)
                      _prosPayCard(
                        key: Key('tr-desk-pay-${pay['id']}'),
                        badge:
                            'دفعة ${jsNumOr0(pay['_seq']).toStringAsFixed(0)}',
                        badgeColor: const Color(0xFF16A34A),
                        amount: n(jsNumOr0(
                            jsOr(pay['_fullAmount'], pay['amount']))),
                        date: '${jsOr(pay['date'], '—')}',
                        indent: true,
                        parts: [
                          if (prosPayLab(pay, _doctorPct()) > 0)
                            (
                              'معمل',
                              n(prosPayLab(pay, _doctorPct())),
                              const Color(0xFFEA580C)
                            ),
                          if (prosPayDoc(pay, _doctorPct()) > 0)
                            (
                              'طبيب',
                              n(prosPayDoc(pay, _doctorPct())),
                              const Color(0xFF065F46)
                            ),
                          if (prosPayClin(pay, _doctorPct()) > 0)
                            (
                              'عيادة',
                              n(prosPayClin(pay, _doctorPct())),
                              const Color(0xFF047857)
                            ),
                        ],
                      ),
                    // المدفوع/المتبقي للحالة (الدين فقط).
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
                  // تذييل الأربع خانات.
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

  /// نسبة الطبيب العامة (احتياط الدفعات القديمة بلا أجزاء مجمّدة).
  num _doctorPct() =>
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
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );

  /// بطاقة دفعة/كاش — pros-pay-card حرفياً (نُقل من الهاتف بلا تغيير مظهر).
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
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()])),
            Text(date,
                style: TextStyle(
                    fontSize: 11.5, color: BrandColors.mut2)),
          ],
        ),
      ]),
    );
  }

  /// نافذة الدفعات العابرة للشهور — توأم _showCrossMonth الهاتفي.
  void _showCrossMonth(ProsGroup g, List<JMap> records, List<JMap> debts,
      String month, String cur, String Function(Object?) n) {
    final items = crossMonthPayments(g, records, debts, month);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('tr-desk-crossmonth-dialog'),
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
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
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

  // ── نظام «التحاليل» — تعديل/حذف بند تحليلٍ (توأم الهاتف حرفياً) ──────────

  /// تعديل قيمة/طريقة تحليلٍ عبر records.updateLocal (يبقى صفاً محروساً).
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
              key: const Key('tr-desk-anal-edit-price'),
              controller: priceCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'القيمة', isDense: true),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('tr-desk-anal-edit-pay'),
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
                key: const Key('tr-desk-anal-edit-save'),
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

  /// حذف صف تحليلٍ (records.delete نظيف — لا دين ولا دفعات).
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
              key: const Key('tr-desk-anal-del-confirm'),
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

  /// طباعة الفئة — نقلٌ أمينٌ لـ _printDetail الهاتفي (نفس النداءين حرفياً،
  /// تخضع لصلاحية print داخل printOrSharePdf تلقائياً).
  Future<void> _printDetail(
      List<JMap> items, List<ProsGroup> groups, String cur) async {
    final fonts = await loadPdfBrand(ref);
    final labels = {
      'cash': 'كاش',
      'xfer': 'تحويل',
      'pros': 'تركيبات',
      'anal': 'تحاليل',
    };
    // نظام «التحاليل» — جدولٌ بسيط (توأم الهاتف).
    if (_detailView == 'anal') {
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
        title: '$_detailCli — تحاليل',
        subtitle: ref.read(selectedMonthProvider),
        headers: const ['التاريخ', 'الاسم', 'التحليل', 'الطريقة', 'القيمة'],
        rows: tableRows,
        totRow: ['المجموع', '', '', '', '${n(sum)} $cur'],
      );
      final msg = await printOrSharePdf(ref.read(dbDirProvider), bytes,
          'treasury_${_detailCli}_anal.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }
    final bytes = _detailView == 'pros'
        ? await prostheticsReportPdf(
            fonts,
            title: '$_detailCli — تركيبات',
            subtitle: ref.read(selectedMonthProvider),
            currency: cur,
            groups: groups,
            doctorPct: jsNumOr0(
                jsOr(ref.read(appConfigProvider)['doctorPct'], 50)),
          )
        : await treatmentTablesPdf(
            fonts,
            title: '$_detailCli — ${labels[_detailView]}',
            subtitle: ref.read(selectedMonthProvider),
            currency: cur,
            tables: buildTreatmentTables(
              items,
              fallbackPct:
                  jsNumber(ref.read(appConfigProvider)['doctorPct'])
                          .isFinite
                      ? jsNumber(ref.read(appConfigProvider)['doctorPct'])
                      : 50,
            ),
          );
    final msg = await printOrSharePdf(ref.read(dbDirProvider), bytes,
        'treasury_${_detailCli}_$_detailView.pdf');
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}

// ── بطاقة عيادة مستقلة بثلاث خانات (اللوح الرئيسي) ───────────────────────────

class _ClinicCard extends StatelessWidget {
  const _ClinicCard({
    super.key,
    required this.clinic,
    required this.cur,
    required this.det,
    required this.activeCat,
    required this.cash,
    required this.xfer,
    required this.pros,
    required this.anal,
    required this.onTapCash,
    required this.onTapXfer,
    required this.onTapPros,
    required this.onTapAnal,
  });

  final String clinic;
  final String cur;
  final bool det;

  /// الفئة النشطة لهذه العيادة (لإبراز الخانة المفتوحة) أو null.
  final String? activeCat;
  final String cash;
  final String xfer;
  final String pros;

  /// نظام «التحاليل» — دخل العيادة المخبري المعزول.
  final String anal;
  final VoidCallback onTapCash;
  final VoidCallback onTapXfer;
  final VoidCallback onTapPros;
  final VoidCallback onTapAnal;

  @override
  Widget build(BuildContext context) {
    return Container(
      // بلا margin سفليّ — شبكة اللوح تتكفّل بالتباعد (crossAxis/mainAxis).
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BrandColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.apartment_rounded,
                size: 16, color: BrandColors.goldDark),
            const SizedBox(width: 6),
            Text(clinic,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: BrandColors.brand900)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _StatCell(
              key: Key('tr-desk-cash-$clinic'),
              label: 'كاش',
              value: det ? cash : '—',
              unit: cur,
              color: BrandColors.green,
              active: activeCat == 'cash',
              onTap: onTapCash,
            ),
            const SizedBox(width: 8),
            _StatCell(
              key: Key('tr-desk-xfer-$clinic'),
              label: 'تحويل',
              value: det ? xfer : '—',
              unit: cur,
              color: BrandColors.brand600,
              active: activeCat == 'xfer',
              onTap: onTapXfer,
            ),
          ]),
          const SizedBox(height: 8),
          // نظام «التحاليل» — الصف الثاني: تركيبات | تحاليل (خانةٌ رابعة).
          Row(children: [
            _StatCell(
              key: Key('tr-desk-pros-$clinic'),
              label: 'تركيبات',
              value: det ? pros : '—',
              unit: cur,
              color: BrandColors.goldDark,
              active: activeCat == 'pros',
              onTap: onTapPros,
            ),
            const SizedBox(width: 8),
            _StatCell(
              key: Key('tr-desk-anal-$clinic'),
              label: 'تحاليل',
              value: det ? anal : '—',
              unit: cur,
              color: BrandColors.green,
              active: activeCat == 'anal',
              onTap: onTapAnal,
            ),
          ]),
        ],
      ),
    );
  }
}

/// خانةٌ قابلة للنقر في بطاقة العيادة — تتلوّن عند فتح تفصيلها.
class _StatCell extends StatelessWidget {
  const _StatCell({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: active
            ? color.withValues(alpha: .16)
            : color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: active
                      ? color.withValues(alpha: .5)
                      : color.withValues(alpha: .18)),
            ),
            child: Column(children: [
              Text(label,
                  style:
                      TextStyle(fontSize: 11, color: BrandColors.mut)),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    maxLines: 1,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: color,
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ])),
              ),
              Text(unit,
                  style:
                      TextStyle(fontSize: 10.5, color: BrandColors.faint)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── شريط الإجماليات السفلي (بعرض اللوح، بترتيب الهاتف) ───────────────────────

class _TotalsBar extends StatelessWidget {
  const _TotalsBar({
    required this.cur,
    required this.det,
    required this.totals,
    required this.analyses,
    required this.expenses,
    required this.expanded,
    required this.onToggleExpand,
    required this.onOpenDebts,
  });

  final String cur;
  final bool det;
  final ({
    num cash,
    num xfer,
    num prosDoc,
    num prosPaid,
    num grand,
    num debtRem
  }) totals;

  /// نظام «التحاليل» — إجمالٍ منفصلٌ عن grand (لا يُجمَع معه).
  final ({num total, num cash, num transfer}) analyses;
  final ({double total, double cash, double xfer}) expenses;

  /// حالة توسّع الجسم — الرأس المصغّر يبقى دائماً.
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onOpenDebts;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final t = totals;
    final ex = expenses;

    return Container(
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border:
            Border(top: BorderSide(color: BrandColors.line, width: .8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── الرأس المصغّر الدائم (~48px): صافي الخزينة (بعد الخصم) رقماً
          // كبيراً + سهم الطي. صافي الخزينة محجوبٌ خلف الصلاحية كبقية الأرقام،
          // فبدونها يعرض الرأس عنوان الشريط بلا رقم (لا تسريب).
          InkWell(
            key: const Key('tr-desk-totals-toggle'),
            onTap: onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
              child: Row(children: [
                Icon(Icons.account_balance_wallet_rounded,
                    size: 17, color: BrandColors.goldDark),
                const SizedBox(width: 8),
                if (det) ...[
                  Expanded(
                    child: Text('صافي الخزينة (بعد الخصم)',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.mut)),
                  ),
                  Text('${n(t.grand - ex.total)} $cur',
                      key: const Key('tr-desk-totals-summary'),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.brand900,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ] else
                  Expanded(
                    child: Text('الإجماليات',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.brandText)),
                  ),
                const SizedBox(width: 6),
                Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: BrandColors.mut),
              ]),
            ),
          ),
          // ── الجسم القابل للطي: بقية الشريط حرفياً ──
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            firstCurve: Curves.easeOut,
            secondCurve: Curves.easeIn,
            sizeCurve: Curves.easeInOut,
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _body(n, t, ex),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// جسم الشريط — الترتيب الهاتفي حرفياً (الدخل المحصّل، المصروفات، الصوافي،
  /// ذيل الديون) بلا أي تعديل على المفاتيح أو المنطق.
  Widget _body(
    String Function(Object?) n,
    ({num cash, num xfer, num prosDoc, num prosPaid, num grand, num debtRem})
        t,
    ({double total, double cash, double xfer}) ex,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // (أ) الدخل الفعلي المحصّل (قبل خصم المصروفات) — خلف الصلاحية.
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
                Text('الدخل الفعلي المحصّل (قبل المصروفات)',
                    style: TextStyle(
                        fontSize: 11, color: BrandColors.mut2)),
                const SizedBox(height: 2),
                Text('${n(t.grand)} $cur',
                    key: const Key('tr-desk-grand'),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.goldDark,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ]),
            ),
          // نظام «التحاليل» — سطرٌ مستقلٌّ (منفصلٌ عن grand): إجمالي/كاش/
          // تحويل الدخل المخبري، خلف الصلاحية ومتى وُجد.
          if (det && analyses.total != 0) ...[
            const SizedBox(height: 10),
            _rowLabel('التحاليل (دخل مخبري معزول)'),
            Row(children: [
              _GridCell(
                  label: 'الإجمالي',
                  value: n(analyses.total),
                  keyName: 'tr-desk-anal-total',
                  color: BrandColors.green),
              const SizedBox(width: 6),
              _GridCell(
                  label: 'كاش',
                  value: n(analyses.cash),
                  keyName: 'tr-desk-anal-cash',
                  color: BrandColors.green),
              const SizedBox(width: 6),
              _GridCell(
                  label: 'تحويل',
                  value: n(analyses.transfer),
                  keyName: 'tr-desk-anal-xfer',
                  color: BrandColors.green),
            ]),
          ],
          // (ب) صف المصروفات — للجميع متى total ≠ 0.
          if (ex.total != 0) ...[
            const SizedBox(height: 10),
            _rowLabel('المصروفات'),
            Row(children: [
              _GridCell(
                  label: 'كاش',
                  value: n(ex.cash),
                  keyName: 'tr-desk-exp-cash',
                  color: BrandColors.red,
                  bg: const Color.fromRGBO(192, 57, 43, .06)),
              const SizedBox(width: 6),
              _GridCell(
                  label: 'تحويل',
                  value: n(ex.xfer),
                  keyName: 'tr-desk-exp-xfer',
                  color: BrandColors.red,
                  bg: const Color.fromRGBO(192, 57, 43, .06)),
              const SizedBox(width: 6),
              _GridCell(
                  label: 'الإجمالي',
                  value: n(ex.total),
                  keyName: 'tr-desk-exp-total',
                  color: BrandColors.red,
                  bg: const Color.fromRGBO(192, 57, 43, .06)),
            ]),
            // (ج) الصوافي بعد الخصم — خلف الصلاحية.
            if (det) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(46, 125, 90, .08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color.fromRGBO(46, 125, 90, .25)),
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
                          key: const Key('tr-desk-cash-net'),
                          textDirection: TextDirection.ltr,
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
                      color: const Color.fromRGBO(46, 125, 90, .25)),
                  Expanded(
                    child: Column(children: [
                      Text('صافي الخزينة (بعد الخصم)',
                          style: TextStyle(
                              fontSize: 10.5,
                              color: BrandColors.mut2)),
                      const SizedBox(height: 2),
                      Text('${n(t.grand - ex.total)} $cur',
                          key: const Key('tr-desk-grand-net'),
                          textDirection: TextDirection.ltr,
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
          ],
          // (د) ذيل «ديون معلقة» — خلف الصلاحية، ينقر لتبويب الديون.
          if (det) ...[
            const SizedBox(height: 10),
            Material(
              color: const Color.fromRGBO(192, 57, 43, .07),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const Key('tr-desk-open-debts'),
                onTap: onOpenDebts,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 9),
                  child: Row(children: [
                    const Icon(Icons.receipt_long_rounded,
                        size: 16, color: BrandColors.red),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text('ديون معلّقة (غير المحصّلة)',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: BrandColors.strong)),
                    ),
                    Text(n(t.debtRem),
                        key: const Key('tr-desk-debt-rem'),
                        textDirection: TextDirection.ltr,
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
        ],
      ),
    );
  }
}

/// تسمية صفٍّ صغيرة فوق شبكة خانات (توأم _rowLabel الهاتفي).
Widget _rowLabel(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 2),
      child: Text(s,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: BrandColors.mut)),
    );

/// خانة شبكة (توأم _GridCell الهاتفي) — تسمية فوق رقمٍ بأرقام جدولية.
class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.label,
    required this.value,
    this.keyName,
    this.color,
    this.bg,
  });

  final String label;
  final String value;
  final String? keyName;
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
                key: keyName == null ? null : Key(keyName!),
                maxLines: 1,
                textDirection: TextDirection.ltr,
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

// ── بند بسيط في قائمة التفصيل (الاسم + التاريخ·الخدمة + المبلغ) ──────────────

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.row, required this.cur});

  final _JMap row;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        title: Text('${row['name'] ?? ''}',
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700)),
        subtitle: Text(
            '${row['date'] ?? ''} · ${row['service'] ?? ''}',
            style: const TextStyle(fontSize: 11)),
        trailing: Text('${n(jsNumOr0(row['amount']))} $cur',
            textDirection: TextDirection.ltr,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: BrandColors.brand700,
                fontFeatures: [FontFeature.tabularFigures()])),
      ),
    );
  }
}

// ── نظام «التحاليل» — بند تفصيلٍ قابل للتعديل والحذف (خلف الصلاحيات) ─────────

class _AnalItemTile extends StatelessWidget {
  const _AnalItemTile({
    required this.row,
    required this.cur,
    required this.onEdit,
    required this.onDelete,
  });

  final _JMap row;
  final String cur;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final canEdit = staffAllowed('records.edit');
    final canDel = staffAllowed('records.delete');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        title: Text('${row['name'] ?? ''}',
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700)),
        subtitle: Text(
            '${row['date'] ?? ''} · '
            '${row['analysisName'] ?? row['service'] ?? ''} · '
            '${row['payment'] ?? ''}',
            style: const TextStyle(fontSize: 11)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${n(jsNumOr0(row['amount']))} $cur',
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: BrandColors.green,
                  fontFeatures: [FontFeature.tabularFigures()])),
          if (canEdit)
            IconButton(
              key: Key('tr-desk-anal-edit-${row['id']}'),
              visualDensity: VisualDensity.compact,
              tooltip: 'تعديل',
              icon: Icon(Icons.edit_rounded,
                  size: 15, color: BrandColors.brandIcon),
              onPressed: onEdit,
            ),
          if (canDel)
            IconButton(
              key: Key('tr-desk-anal-del-${row['id']}'),
              visualDensity: VisualDensity.compact,
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_rounded,
                  size: 15, color: BrandColors.red),
              onPressed: onDelete,
            ),
        ]),
      ),
    );
  }
}

// ── حقل تاريخٍ للتفصيل (توأم _DateField الهاتفي) ─────────────────────────────

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
