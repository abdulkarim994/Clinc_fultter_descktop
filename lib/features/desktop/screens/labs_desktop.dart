/// ============================================================================
///  التركيبات (المختبر) — نسخة سطح المكتب: Master/Detail بنمط شاشة الديون
/// ============================================================================
///
///  (قرار المالك — عقد التصميم «د»): تُعاد بنية هذا التبويب لتطابق شاشة
///  الديون المكتبية (debts_desktop) وبنية الهاتف (مختبر ← حالاته)، بدل
///  القائمة المسطّحة القديمة التي تفرد كل المختبرات في قائمة حالات واحدة.
///
///    • يمين (~380px): قائمة **المختبرات** المجمّعة بعدّادات — رأس
///      «المختبرات» + عداد + بحث فوري يصفّي بالاسم، ثم صفوف مختبر
///      [أيقونة][اسم][شارة نشطة][شارة غير مدفوعة][إجمالي مستحق][chevron].
///      النقر يضبط المختبر المحدَّد ويلوّن الصف (ذهبي + حد جانبي).
///    • يسار: جدول [DesktopDataTable]<LabCase> لحالات المختبر المحدَّد
///      (الحالة/المريض/النوع×الوحدات/العيادة/القيمة/المدفوع/الحالة
///      التشغيلية/التاريخ) بترويسة مختبر [أيقونة][اسم+عدد][طباعة][إغلاق]
///      وذيل المجاميع الستة، ونقر مزدوج/فتح يعرض تفاصيل الحالة الكاملة.
///
///  منطق البيانات من labs_logic.dart (LabCase / labCases / labCasesCount /
///  labTotalDebt / labTotalCollected / labTotalAll / labTotalUnits) بلا أي
///  تعديل — يُستهلَك كما هو. والطباعة (labReportPdf + printOrSharePdf) توأم
///  الهاتف حرفياً. المنطق المالي (financialStatus من الدين المرتبط) محفوظ.
///  مفتاح DesktopSplitView: 'labs'.
library;

import 'package:flutter/material.dart';
// م161 — لوغو المختبر الموحّد.
// ignore: directives_ordering
import '../../labs/lab_logo.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/js_compat.dart';
import '../../labs/labs_logic.dart';
import '../../print/print_service.dart' show loadPdfBrand, printOrSharePdf;
import '../../print/reports.dart'
    show labMonthReportPdf, labsValuesPdf;
import '../widgets/context_menu.dart' show CtxItem;
import '../widgets/desktop_dialogs.dart' show showDesktopPanel;
import '../widgets/desktop_table.dart' show DeskCol, DesktopDataTable;
import '../widgets/split_view.dart'
    show DesktopSplitView, DetailHost, SplitEmptyState;

class DesktopLabsScreen extends ConsumerStatefulWidget {
  const DesktopLabsScreen({super.key});

  @override
  ConsumerState<DesktopLabsScreen> createState() => _DesktopLabsScreenState();
}

/// خلاصة عدّادات مختبرٍ للقائمة الرئيسية (يمين) — كلها من labs_logic.
class _LabSummary {
  const _LabSummary({
    required this.lab,
    required this.total,
    required this.active,
    required this.due,
    required this.monthValue,
  });

  /// م161 — قيمة المختبر للشهر المختار (مجموع labValue لحالاته).
  final num monthValue;

  /// اسم المختبر.
  final String lab;

  /// عدد حالات المختبر — labCasesCount.
  final int total;

  /// عدد الحالات غير المدفوعة (financialStatus == 'دين').
  final int active;

  /// إجمالي المستحق (قيمة الحالات المدينة) — labTotalDebt.
  final num due;
}

class _DesktopLabsScreenState extends ConsumerState<DesktopLabsScreen> {
  /// المختبر المختار حالياً (null = لا اختيار).
  String? _selectedLab;

  /// نص البحث الفوري (تصفية قائمة المختبرات بالاسم).
  String _query = '';

  /// اتجاه فرز حالات المختبر (يمرَّر لـ labCases؛ الجدول يعيد الفرز أيضاً).
  static const _sortOrder = 'newest';

  /// فرز قائمة المختبرات: 'name' أو 'due'.
  String _labSort = 'name';

  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1500)),
      );

  /// حالات مختبرٍ عبر المنطق الموجود بلا تعديل.
  List<LabCase> _casesOf(
    String lab, {
    required List<JMap> prosthetics,
    required List<JMap> debts,
    required List<JMap> records,
  }) =>
      labCases(lab,
          prosthetics: prosthetics,
          debts: debts,
          records: records,
          sortOrder: _sortOrder);

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(appConfigProvider);
    final labs = cfg['labs'] is List
        ? [for (final l in cfg['labs'] as List) '$l']
        : <String>[];
    final repos = ref.watch(reposProvider);
    final cur = ref.watch(currencyProvider);
    // م161 — نطاق الشهر المختار (تصفير تلقائي مطلع كل شهر كالهاتف).
    final month = ref.watch(selectedMonthProvider);
    final prosthetics = repos.prosthetics.getAll();
    final debts = repos.debts.getAll();
    final records = repos.records.getAll();

    // ── خلاصات المختبرات (عدّادات) — من labs_logic بلا تعديل ──
    final summaries = <_LabSummary>[];
    for (final lab in labs) {
      final cases = _casesOf(lab,
          prosthetics: prosthetics, debts: debts, records: records);
      summaries.add(_LabSummary(
        lab: lab,
        total: labCasesCount(prosthetics, lab),
        active: cases.where((c) => c.financialStatus == 'دين').length,
        due: labTotalDebt(cases),
        monthValue:
            labMonthValue(lab, prosthetics: prosthetics, month: month),
      ));
    }

    // تصفية بالبحث ثم الفرز (بالاسم أو المستحق الأعلى أولاً).
    final q = _query.trim();
    var filtered = q.isEmpty
        ? [...summaries]
        : [for (final s in summaries) if (s.lab.contains(q)) s];
    filtered.sort((a, b) => _labSort == 'due'
        ? b.due.compareTo(a.due)
        : a.lab.compareTo(b.lab));

    // ── القسم الأيمن: رأس + بحث + قائمة المختبرات المجمّعة ──
    final master = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MasterHeader(
          count: filtered.length,
          total: summaries.length,
          month: month,
          searchCtl: _searchCtl,
          labSort: _labSort,
          onSearch: (v) => setState(() => _query = v),
          onSortChanged: (s) => setState(() => _labSort = s),
          // م161 — طباعة قيم كل المعامل للشهر المختار.
          onPrintAll: labs.isEmpty
              ? null
              : () => _printAllLabs(labs, prosthetics, month),
        ),
        const Divider(height: 1),
        Expanded(
          child: labs.isEmpty
              ? const _LabsEmptyConfig()
              : filtered.isEmpty
                  ? _NoResults(query: _query)
                  : ListView.builder(
                      key: const Key('labs-desk-list'),
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final s = filtered[i];
                        return _LabTile(
                          summary: s,
                          cur: cur,
                          selected: _selectedLab == s.lab,
                          onTap: () =>
                              setState(() => _selectedLab = s.lab),
                        );
                      },
                    ),
        ),
      ],
    );

    // ── القسم الأيسر: جدول حالات المختبر المحدَّد أو الحالة الفارغة ──
    Widget? detailWidget;
    final sel = _selectedLab;
    // نتحقق أن المختبر المحدَّد ما زال ضمن الإعدادات (قد يُحذف).
    if (sel != null && labs.contains(sel)) {
      // م161 — حالات الشهر المختار وحدها (كجدول الهاتف الجديد).
      final cases = [
        for (final c in _casesOf(sel,
            prosthetics: prosthetics, debts: debts, records: records))
          if ('${c.row['date'] ?? ''}'.startsWith(month)) c,
      ];
      detailWidget = DetailHost(
        hostKey: 'labs-$sel-$month',
        child: _LabDetail(
          key: ValueKey('labs-detail-$sel'),
          lab: sel,
          month: month,
          cases: cases,
          cur: cur,
          onClose: () => setState(() => _selectedLab = null),
          onPrint: (byClinic) =>
              _printLab(sel, prosthetics, month, byClinic: byClinic),
          onOpenCase: (c) => _openCase(c, cur),
          onCopyName: (name) {
            Clipboard.setData(ClipboardData(text: name));
            _snack('نُسخ الاسم');
          },
        ),
      );
    }

    return DesktopSplitView(
      id: 'labs',
      emptyIcon: Icons.biotech_rounded,
      emptyTitle: 'اختر مختبراً لعرض حالاته',
      emptyHint: 'اختر مختبراً من القائمة لعرض جدول حالاته الكامل',
      masterWidth: 380,
      master: master,
      detail: detailWidget,
    );
  }

  /// م161 — طباعة قيم كل المعامل للشهر المختار.
  Future<void> _printAllLabs(
      List<String> labs, List<JMap> prosthetics, String month) async {
    try {
      final fonts = await loadPdfBrand(ref);
      final bytes = await labsValuesPdf(fonts,
          subtitle: month,
          currency: ref.read(currencyProvider),
          cards: labCards(labs, prosthetics: prosthetics, month: month));
      final msg = await printOrSharePdf(
          ref.read(dbDirProvider), bytes, 'labs_values.pdf');
      if (mounted) _snack(msg);
    } catch (e) {
      if (mounted) _snack('تعذّرت الطباعة');
    }
  }

  // ── فتح تفاصيل الحالة الكاملة (نافذة شبه‑شاشة) ────────────────────────────

  Future<void> _openCase(LabCase c, String cur) async {
    await showDesktopPanel<void>(
      context,
      title: '${c.row['name'] ?? 'حالة'}',
      subtitle: '${c.row['labName'] ?? ''}',
      builder: (_) => _CaseDetail(labCase: c, cur: cur),
    );
  }

  // ── طباعة تقرير المختبر — توأم _printLab الهاتفي حرفياً ───────────────────

  Future<void> _printLab(
      String lab, List<JMap> prosthetics, String month,
      {required bool byClinic}) async {
    if (lab.isEmpty) {
      _snack('لا مختبر محدّد');
      return;
    }
    try {
      final fonts = await loadPdfBrand(ref);
      // م161 — نفس تقرير الهاتف: جدول الشهر بالأحدث + صف الإجمالي،
      // بخياري «كل العيادات معاً» أو «كل عيادة على حدة».
      final bytes = await labMonthReportPdf(fonts,
          lab: lab,
          subtitle: month,
          currency: ref.read(currencyProvider),
          rows: labMonthRows(lab, prosthetics: prosthetics, month: month),
          byClinic: byClinic);
      final msg = await printOrSharePdf(
          ref.read(dbDirProvider), bytes, 'lab_$lab.pdf');
      if (mounted) _snack(msg);
    } catch (e) {
      if (mounted) _snack('تعذّرت الطباعة');
    }
  }
}

// ── رأس القسم الأيمن ─────────────────────────────────────────────────────────

class _MasterHeader extends StatelessWidget {
  const _MasterHeader({
    required this.count,
    required this.total,
    required this.month,
    required this.searchCtl,
    required this.labSort,
    required this.onSearch,
    required this.onSortChanged,
    required this.onPrintAll,
  });

  final int count;
  final int total;

  /// م161 — الشهر المختار (يظهر بالعنوان وتُطبع قيمه).
  final String month;
  final TextEditingController searchCtl;
  final String labSort;
  final void Function(String) onSearch;
  final void Function(String) onSortChanged;

  /// م161 — طباعة قيم كل المعامل (null = لا مختبرات).
  final VoidCallback? onPrintAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: BrandColors.surface,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // العنوان + العداد.
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: BrandColors.brand600.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const LabLogo(size: 18, color: BrandColors.brand700),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('المختبرات — $month',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.brandText)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: BrandColors.brand.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('$count',
                  key: const Key('labs-desk-count'),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brand600)),
            ),
          ]),
          const SizedBox(height: 8),
          // بحث فوري (تصفية بالاسم) + م161: زر طباعة قيم كل المعامل.
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: TextField(
                  key: const Key('labs-desk-search'),
              controller: searchCtl,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'بحث باسم المختبر...',
                hintStyle:
                    TextStyle(fontSize: 12, color: BrandColors.mut2),
                prefixIcon: Icon(Icons.search_rounded,
                    size: 16, color: BrandColors.mut2),
                filled: true,
                fillColor: BrandColors.surface2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: BrandColors.line, width: .8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: BrandColors.line, width: .8),
                ),
              ),
                  onChanged: onSearch,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: 'طباعة قيم كل المعامل',
              child: Material(
                color: BrandColors.gold.withValues(alpha: .08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                      color: BrandColors.gold.withValues(alpha: .3)),
                ),
                child: InkWell(
                  key: const Key('labs-desk-print-all'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: onPrintAll,
                  child: const SizedBox(
                    width: 36,
                    height: 34,
                    child: Icon(Icons.print_rounded,
                        size: 16, color: BrandColors.goldDark),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          // فرز القائمة: بالاسم / بالأعلى مستحقاً.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final entry in const [
                ('name', 'بالاسم'),
                ('due', 'الأعلى مستحقاً'),
              ])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    key: Key('labs-desk-sort-${entry.$1}'),
                    label: Text(entry.$2,
                        style: const TextStyle(fontSize: 11)),
                    selected: labSort == entry.$1,
                    selectedColor: BrandColors.brand600,
                    labelStyle: TextStyle(
                        color: labSort == entry.$1
                            ? Colors.white
                            : BrandColors.ink,
                        fontWeight: FontWeight.w700),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onSortChanged(entry.$1),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── صف مختبر في القائمة الرئيسية ─────────────────────────────────────────────

class _LabTile extends StatefulWidget {
  const _LabTile({
    required this.summary,
    required this.cur,
    required this.selected,
    required this.onTap,
  });

  final _LabSummary summary;
  final String cur;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_LabTile> createState() => _LabTileState();
}

class _LabTileState extends State<_LabTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final bg = widget.selected
        ? BrandColors.gold.withValues(alpha: .10)
        : _hovered
            ? BrandColors.surface2
            : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          key: Key('labs-desk-tile-${s.lab}'),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom: const BorderSide(color: Color(0x11000000), width: .5),
              // حد جانبي بديره = بداية RTL (اليمين فيزيائياً).
              right: widget.selected
                  ? BorderSide(color: BrandColors.gold, width: 2.5)
                  : BorderSide.none,
            ),
          ),
          padding: EdgeInsetsDirectional.only(
              start: widget.selected ? 9.5 : 12, end: 10, top: 8, bottom: 8),
          child: Row(children: [
            // أيقونة المختبر.
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BrandColors.brand600.withValues(alpha: .1),
                border: Border.all(
                    color: BrandColors.brand600.withValues(alpha: .25)),
              ),
              child: const LabLogo(size: 18, color: BrandColors.brand700),
            ),
            const SizedBox(width: 10),
            // الاسم + الشارات.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.lab,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.brandText)),
                  const SizedBox(height: 3),
                  // Wrap: على القوائم الضيقة تنزل الشارة الثانية لسطر
                  // تالٍ بدل التجاوز (RenderFlex overflow).
                  Wrap(
                    spacing: 5,
                    runSpacing: 3,
                    children: [
                      _Chip(
                        label: '${s.active} نشطة',
                        color: BrandColors.goldDark,
                        bg: BrandColors.gold.withValues(alpha: .14),
                      ),
                      if (s.due > 0)
                        _Chip(
                          label: '${s.active} غير مدفوعة',
                          color: BrandColors.red,
                          bg: BrandColors.red.withValues(alpha: .10),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // م161 — قيمة الشهر (كبطاقة الهاتف) + المستحق إن وجد.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  s.monthValue.toStringAsFixed(0),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: BrandColors.goldDark,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text('قيمة الشهر',
                    style: TextStyle(
                        fontSize: 9.5, color: BrandColors.mut2)),
                if (s.due > 0)
                  Text('مستحق ${s.due.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.red)),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_left_rounded,
                size: 18, color: BrandColors.mut2),
          ]),
        ),
      ),
    );
  }
}

/// شارة صغيرة (عدّاد) في صف المختبر.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color, required this.bg});

  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ── لوح تفصيل المختبر: ترويسة + جدول الحالات + ذيل المجاميع ───────────────────

class _LabDetail extends StatelessWidget {
  const _LabDetail({
    super.key,
    required this.lab,
    required this.month,
    required this.cases,
    required this.cur,
    required this.onClose,
    required this.onPrint,
    required this.onOpenCase,
    required this.onCopyName,
  });

  final String lab;

  /// م161 — الشهر المختار (نطاق الجدول والطباعة).
  final String month;
  final List<LabCase> cases;
  final String cur;
  final VoidCallback onClose;

  /// م161 — طباعة بخيارين: byClinic=true كل عيادة على حدة.
  final void Function(bool byClinic) onPrint;
  final void Function(LabCase) onOpenCase;
  final void Function(String) onCopyName;

  /// المدفوع المشتق كالهاتف: القيمة إن محصّل وإلا 0 (المخزن لا يحفظ labPaid).
  static num _paidOf(LabCase c) =>
      c.financialStatus == 'محصّل' ? jsNumOr0(c.row['labValue']) : 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── الترويسة: [أيقونة][اسم + عدد][طباعة ذهبي][إغلاق] ──
        Container(
          color: BrandColors.surface,
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BrandColors.brand600.withValues(alpha: .1),
                border: Border.all(
                    color: BrandColors.brand600.withValues(alpha: .3)),
              ),
              child: const LabLogo(size: 21, color: BrandColors.brand700),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lab,
                      key: const Key('labs-desk-detail-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.brandText)),
                  Text('${cases.length} حالة · $month',
                      style: TextStyle(
                          fontSize: 11.5, color: BrandColors.mut2)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // زر طباعة تقرير المختبر (ذهبي) — توأم lab-print الهاتفي.
            Material(
              color: BrandColors.gold.withValues(alpha: .08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                    color: BrandColors.gold.withValues(alpha: .3)),
              ),
              child: PopupMenuButton<String>(
                key: const Key('labs-desk-print'),
                tooltip: 'طباعة',
                enabled: cases.isNotEmpty,
                onSelected: (v) => onPrint(v == 'byClinic'),
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
            const SizedBox(width: 6),
            IconButton(
              key: const Key('labs-desk-close'),
              icon: const Icon(Icons.close_rounded, size: 18),
              color: BrandColors.mut,
              tooltip: 'إغلاق',
              onPressed: onClose,
            ),
          ]),
        ),
        const Divider(height: 1),
        // ── جدول الحالات ──
        Expanded(
          child: DesktopDataTable<LabCase>(
            tableId: 'labs-cases',
            rows: cases,
            rowId: (c) => '${c.row['id'] ?? ''}',
            defaultSortId: 'date',
            defaultSortAsc: false,
            persistSort: false,
            defaultPinned: const ['date', 'name'],
            rowHeight: 40,
            emptyTitle: 'لا توجد حالات لهذا المختبر',
            searchHint: 'بحث بالاسم أو النوع…',
            searchText: (c) =>
                '${c.row['name'] ?? ''} ${c.row['prosType'] ?? ''} '
                '${c.row['labName'] ?? ''}',
            onOpen: onOpenCase,
            contextMenuOf: (c) => [
              CtxItem('فتح التفاصيل',
                  icon: Icons.info_outline_rounded,
                  keyId: 'labs-open-case',
                  onTap: () => onOpenCase(c)),
              CtxItem('نسخ اسم المريض',
                  icon: Icons.copy_rounded,
                  keyId: 'labs-copy-name',
                  onTap: () => onCopyName('${c.row['name'] ?? ''}')),
              CtxItem.divider,
              CtxItem('طباعة تقرير المختبر',
                  icon: Icons.print_rounded,
                  keyId: 'labs-print-report',
                  onTap: () => onPrint(false)),
            ],
            columns: _columns(cur),
            // م161/ب — صف الإجمالي آخر صف داخل الجدول بمحاذاة كل عمود
            // (قرار المالك: تجميع كل شيء بنظرة واحدة).
            totalOf: (id) => switch (id) {
              'date' => 'الإجمالي',
              'name' => '${cases.length} حالة',
              'units' => labTotalUnits(cases).toStringAsFixed(0),
              'value' => labTotalAll(cases).toStringAsFixed(0),
              'paid' => labTotalCollected(cases).toStringAsFixed(0),
              _ => '',
            },
            footer: _LabTotalsFooter(cases: cases, cur: cur),
          ),
        ),
      ],
    );
  }

  // ── تعريف الأعمدة — م161: ترتيب جدول الهاتف (التاريخ/الاسم/العيادة/
  // النوع/الوحدات/القيمة) + عمودا سطح المكتب الإضافيان (المدفوع/الحالة).
  List<DeskCol<LabCase>> _columns(String cur) {
    return [
      // التاريخ — أولاً كالهاتف (الفرز الافتراضي الأحدث).
      DeskCol.text<LabCase>(
        id: 'date',
        label: 'التاريخ',
        width: 96,
        value: (c) => '${c.row['date'] ?? ''}',
        sortKey: (c) => '${c.row['date'] ?? ''}',
      ),
      // المريض (يتوسّع — flex:2، مثبّت افتراضياً).
      DeskCol.text<LabCase>(
        id: 'name',
        label: 'الاسم',
        width: 150,
        flex: 2,
        weight: FontWeight.w800,
        value: (c) => '${c.row['name'] ?? ''}',
        color: (_) => BrandColors.brandText,
      ),
      // العيادة.
      DeskCol.text<LabCase>(
        id: 'clinic',
        label: 'العيادة',
        width: 96,
        value: (c) => '${c.row['clinic'] ?? ''}'.trim(),
        color: (_) => BrandColors.mut,
      ),
      // نوع التركيب.
      DeskCol.text<LabCase>(
        id: 'type',
        label: 'نوع التركيب',
        width: 120,
        value: (c) => '${c.row['prosType'] ?? ''}'.trim(),
      ),
      // م161 — الوحدات عموداً مستقلاً (الرقم فقط).
      DeskCol.text<LabCase>(
        id: 'units',
        label: 'الوحدات',
        width: 70,
        numeric: true,
        value: (c) {
          final u = jsNumOr0(c.row['prosUnits']);
          return (u > 0 ? u : 1).toStringAsFixed(0);
        },
        sortKey: (c) => jsNumOr0(c.row['prosUnits']),
      ),
      // القيمة (labValue) — رقمية ذهبية.
      DeskCol.text<LabCase>(
        id: 'value',
        label: 'القيمة',
        width: 90,
        numeric: true,
        weight: FontWeight.w800,
        value: (c) => jsNumOr0(c.row['labValue']).toStringAsFixed(0),
        sortKey: (c) => jsNumOr0(c.row['labValue']),
        color: (_) => BrandColors.goldDark,
      ),
      // المدفوع (مشتق كالهاتف) — إضافي سطح المكتب.
      DeskCol.text<LabCase>(
        id: 'paid',
        label: 'المدفوع',
        width: 90,
        numeric: true,
        weight: FontWeight.w800,
        value: (c) => _paidOf(c).toStringAsFixed(0),
        sortKey: (c) => _paidOf(c),
        color: (c) => c.financialStatus == 'محصّل'
            ? BrandColors.green
            : BrandColors.mut2,
      ),
      // الحالة المالية — شارة ملوّنة (إضافي سطح المكتب).
      DeskCol<LabCase>(
        id: 'status',
        label: 'الحالة',
        width: 92,
        minWidth: 80,
        sortKey: (c) => c.financialStatus,
        cell: (context, c) {
          final paid = c.financialStatus == 'محصّل';
          final color = paid ? BrandColors.green : BrandColors.red;
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(c.financialStatus,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: color)),
          );
        },
      ),
    ];
  }
}

// ── ذيل المجاميع (توأم _tot في labs_tab.dart:291-314 — الست كلها) ─────────────

class _LabTotalsFooter extends StatelessWidget {
  const _LabTotalsFooter({required this.cases, required this.cur});

  final List<LabCase> cases;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final collected = labTotalCollected(cases);
    final debt = labTotalDebt(cases);
    final net = collected - debt;

    return Container(
      key: const Key('labs-desk-totals'),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border:
            Border(top: BorderSide(color: BrandColors.line, width: .8)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          // م161/ب — العدّ والوحدات والقيمة صارت صفَّ إجمالي داخل الجدول
          // بمحاذاة أعمدته؛ هنا الملخص المالي وحده (محصّل/ديون/صافٍ).
          _stat('المحصّل', '${collected.toStringAsFixed(2)} $cur',
              color: BrandColors.green),
          _sep(),
          _stat('الديون', '${debt.toStringAsFixed(2)} $cur',
              color: BrandColors.red,
              keyName: 'labs-desk-total-debt'),
          _sep(),
          _stat('الصافي', '${net.toStringAsFixed(2)} $cur',
              color: BrandColors.brand700, big: true),
        ]),
      ),
    );
  }

  Widget _sep() => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: BrandColors.line,
      );

  Widget _stat(String label, String value,
      {Color? color, bool big = false, String? keyName}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: BrandColors.mut2)),
        const SizedBox(height: 2),
        Text(value,
            key: keyName == null ? null : Key(keyName),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: big ? 14.5 : 12.5,
              fontWeight: big ? FontWeight.w900 : FontWeight.w800,
              color: color ?? BrandColors.brand900,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ],
    );
  }
}

// ── لوحة تفاصيل الحالة الكاملة (تُفتح بنقر مزدوج / قائمة السياق) ───────────────

class _CaseDetail extends StatelessWidget {
  const _CaseDetail({required this.labCase, required this.cur});

  final LabCase labCase;
  final String cur;

  @override
  Widget build(BuildContext context) {
    final c = labCase;
    final row = c.row;

    final name = '${row['name'] ?? ''}';
    final clinic = '${row['clinic'] ?? ''}'.trim();
    final prosType = '${row['prosType'] ?? ''}'.trim();
    final lab = '${row['labName'] ?? ''}'.trim();
    final date = '${row['date'] ?? ''}';
    final notes = '${row['notes'] ?? ''}'.trim();
    final labValue = jsNumOr0(row['labValue']);
    final units = jsNumOr0(row['prosUnits']);
    final isPaid = c.financialStatus == 'محصّل';

    // الحالة المالية: labValue = الإجمالي. المدفوع = labValue إن محصّل وإلا 0.
    // (المخزن لا يحتفظ بـ labPaid مباشرةً — المعلومة مشتقّة من الحالة)
    final paid = isPaid ? labValue : 0.0;
    final remaining = isPaid ? 0.0 : labValue;
    final progress = labValue > 0 && isPaid ? 1.0 : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس مختصر (العنوان يظهر في ترويسة النافذة).
          if (name.isNotEmpty || clinic.isNotEmpty) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isPaid ? BrandColors.green : BrandColors.red)
                      .withValues(alpha: .1),
                  border: Border.all(
                      color: (isPaid ? BrandColors.green : BrandColors.red)
                          .withValues(alpha: .3)),
                ),
                child: Icon(
                  isPaid
                      ? Icons.check_rounded
                      : Icons.hourglass_bottom_rounded,
                  size: 24,
                  color: isPaid ? BrandColors.green : BrandColors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: BrandColors.brandText)),
                    if (clinic.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(clinic,
                          style: TextStyle(
                              fontSize: 12, color: BrandColors.mut2)),
                    ],
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
          ],

          // بطاقة هوية الحالة.
          _SectionCard(
            title: 'هوية الحالة',
            icon: Icons.person_outline_rounded,
            children: [
              if (prosType.isNotEmpty)
                _DetailField(
                  label: 'نوع التركيبة',
                  value: units > 1
                      ? '$prosType × ${units.toStringAsFixed(0)} وحدات'
                      : prosType,
                  valueColor: BrandColors.brand700,
                ),
              if (lab.isNotEmpty) _DetailField(label: 'المختبر', value: lab),
              if (clinic.isNotEmpty)
                _DetailField(label: 'العيادة', value: clinic),
              _DetailField(label: 'التاريخ', value: date),
            ],
          ),
          const SizedBox(height: 14),

          // الحالة المالية.
          _FinancialCard(
            labValue: labValue,
            paid: paid,
            remaining: remaining,
            progress: progress,
            cur: cur,
          ),
          const SizedBox(height: 14),

          // حالة المختبر.
          _SectionCard(
            title: 'حالة المختبر',
            icon: Icons.biotech_rounded,
            children: [
              _StatusBadgeField(
                status: c.financialStatus,
                date: c.statusDate,
                isPaid: isPaid,
              ),
            ],
          ),

          // الملاحظات (إن وُجدت).
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SectionCard(
              title: 'ملاحظات',
              icon: Icons.notes_rounded,
              children: [_NotesField(notes: notes)],
            ),
          ],
        ],
      ),
    );
  }
}

// ── بطاقة قسم عامة ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BrandColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              Icon(icon, size: 15, color: BrandColors.brand600),
              const SizedBox(width: 6),
              Text(title,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brandText)),
            ]),
          ),
          Divider(height: 1, color: BrandColors.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

// ── حقل تفصيل عادي ───────────────────────────────────────────────────────────

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty || value == 'null') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: BrandColors.mut2)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? BrandColors.ink)),
        ],
      ),
    );
  }
}

// ── شارة الحالة + التاريخ ─────────────────────────────────────────────────────

class _StatusBadgeField extends StatelessWidget {
  const _StatusBadgeField({
    required this.status,
    required this.date,
    required this.isPaid,
  });

  final String status;
  final String date;
  final bool isPaid;

  @override
  Widget build(BuildContext context) {
    final color = isPaid ? BrandColors.green : BrandColors.red;
    return Row(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isPaid
                ? Icons.check_circle_rounded
                : Icons.hourglass_bottom_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(status,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ]),
      ),
      const SizedBox(width: 10),
      Text(date, style: TextStyle(fontSize: 11.5, color: BrandColors.mut2)),
    ]);
  }
}

// ── بطاقة الحالة المالية ─────────────────────────────────────────────────────

class _FinancialCard extends StatelessWidget {
  const _FinancialCard({
    required this.labValue,
    required this.paid,
    required this.remaining,
    required this.progress,
    required this.cur,
  });

  final num labValue;
  final num paid;
  final num remaining;
  final double progress;
  final String cur;

  @override
  Widget build(BuildContext context) {
    Widget statCell(String label, String value, Color color) => Expanded(
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(fontSize: 10, color: BrandColors.mut2)),
              const SizedBox(height: 3),
              Text(value,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BrandColors.line),
      ),
      child: Column(
        children: [
          // رأس — إجمالي التركيبة.
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF0E4D2E), Color(0xFF1A3A2A)]),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.account_balance_wallet_rounded,
                    size: 14, color: BrandColors.goldLight),
                const SizedBox(width: 6),
                Text('الحالة المالية',
                    style: TextStyle(
                        fontSize: 11, color: BrandColors.goldLight)),
              ]),
              const SizedBox(height: 6),
              Text(
                '${labValue.toStringAsFixed(0)} $cur',
                key: const Key('labs-desk-value'),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: BrandColors.goldLight,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text('الإجمالي',
                  style: TextStyle(
                      fontSize: 10,
                      color: BrandColors.goldLight.withValues(alpha: .7))),
            ]),
          ),
          // شريط التقدم.
          ClipRRect(
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: BrandColors.red.withValues(alpha: .18),
              valueColor: AlwaysStoppedAnimation(BrandColors.green),
            ),
          ),
          // المدفوع / المتبقي.
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(children: [
              statCell('المدفوع', '${paid.toStringAsFixed(0)} $cur',
                  BrandColors.green),
              Container(width: 1, height: 30, color: BrandColors.line),
              statCell('المتبقي', '${remaining.toStringAsFixed(0)} $cur',
                  remaining > 0 ? BrandColors.red : BrandColors.green),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── حقل الملاحظات ─────────────────────────────────────────────────────────────

class _NotesField extends StatelessWidget {
  const _NotesField({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BrandColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BrandColors.line),
      ),
      child: Text(notes,
          style: TextStyle(
              fontSize: 12.5, height: 1.6, color: BrandColors.mut)),
    );
  }
}

// ── حالات فارغة ──────────────────────────────────────────────────────────────

class _LabsEmptyConfig extends StatelessWidget {
  const _LabsEmptyConfig();

  @override
  Widget build(BuildContext context) {
    return SplitEmptyState(
      icon: Icons.biotech_rounded,
      title: 'لا توجد مختبرات',
      hint: 'أضف مختبرات من الإعدادات ← إعدادات المختبرات',
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 44, color: BrandColors.faint),
            const SizedBox(height: 12),
            Text('لا نتائج مطابقة',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.mut)),
            const SizedBox(height: 6),
            Text('لا نتائج لـ «$query»',
                style: TextStyle(fontSize: 12, color: BrandColors.faint)),
          ],
        ),
      ),
    );
  }
}
