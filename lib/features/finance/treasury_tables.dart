/// م154 — ودجات الخزينة الجديدة المشتركة بين المنصتين (قرار المالك):
///
/// • [TreasuryMasterRow] — صفٌّ بسيط أنيق (اسمٌ + إجمالي شهري) لقائمة
///   العيادات/التحاليل/المصروفات — بنمط صفوف جدول المختبرات.
/// • [TreasuryMovesTable] — جدول حركاتٍ منظم (التاريخ/الاسم/الدفع/القيمة)
///   فوقه بحثٌ وفلترة (الكل/كاش/تحويل) وطباعةٌ حسب الفلترة الظاهرة.
/// • [TreasuryProsTable] — جدول التركيبات المنظم (المريض/الإجمالي/الطبيب/
///   العيادة/المخبر) بنفس معلومات البطاقات السابقة.
/// • [TreasuryTotalsTable] — جدول «الإجمالي»: العيادات/التحاليل/المصروفات
///   × (كاش/تحويل/إجمالي) + صف الصافي بعد الخصم — بنطاق الشهر المختار.
/// • [TreasuryViewSwitcher] — مبدّل «تفصيل/إجمالي» بنمط مبدّل الحجوزات.
///
/// كل القيم شهرية (مبدّل الشهر القائم) فتصفر تلقائياً مطلع كل شهر.
/// العزل المالي محفوظ: التحاليل صفٌّ مستقل لا يُجمع مع إيراد العيادات
/// إلا في صف الصافي التجميعي الصريح.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../print/print_service.dart' show loadPdfBrand, printOrSharePdf;
import '../print/reports.dart' show simpleTablePdf, treatmentTablesPdf;
import '../print/treatment_tables.dart' show buildTreatmentTables;
import '../print/treatment_tables.dart' show formatNumber;
import 'reports_bridge.dart';
import 'treasury_logic.dart'
    show
        ProsGroup,
        TreasurySlice,
        detailItems,
        prosPayClin,
        prosPayDoc,
        prosPayLab;

typedef _JMap = Map<String, Object?>;

/// حركات عيادةٍ في شهر الشريحة: كاش + تحويل معاً، كل صفٍّ موسومٌ بطريقته
/// (نقي — للجدول الموحد وفلترته).
List<Map<String, Object?>> clinicMonthMoves(
    TreasurySlice s, String clinic) {
  final out = <Map<String, Object?>>[
    for (final r in detailItems(s, 'cash', clinic)) {...r, '_pay': 'كاش'},
    for (final r in detailItems(s, 'xfer', clinic)) {...r, '_pay': 'تحويل'},
  ];
  out.sort((a, b) => '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'));
  return out;
}

/// مبدّل «التفصيل/الإجمالي» — توأم مبدّل أسبوع/قائمة في الحجوزات.
class TreasuryViewSwitcher extends StatelessWidget {
  const TreasuryViewSwitcher({
    super.key,
    required this.totals,
    required this.onChanged,
  });

  /// true = وضع «الإجمالي»، false = وضع «التفصيل».
  final bool totals;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const segTxt = TextStyle(fontSize: 12, fontWeight: FontWeight.w800);
    return SegmentedButton<bool>(
      key: const Key('tr2-view-switcher'),
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return BrandColors.gold;
          return BrandColors.surface2;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BrandColors.brand900;
          }
          return BrandColors.ink;
        }),
      ),
      segments: const [
        ButtonSegment(
          value: false,
          icon: Icon(Icons.table_rows_rounded, size: 16),
          label: Text('التفصيل', style: segTxt),
        ),
        ButtonSegment(
          value: true,
          icon: Icon(Icons.summarize_rounded, size: 16),
          label: Text('الإجمالي', style: segTxt),
        ),
      ],
      selected: {totals},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// صفٌّ بسيط في القائمة الرئيسية: أيقونة + اسم + إجمالي شهري + سهم.
class TreasuryMasterRow extends StatelessWidget {
  const TreasuryMasterRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.color,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  final Color? color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = color ?? BrandColors.goldDark;
    return Material(
      color: selected
          ? c.withValues(alpha: .10)
          : BrandColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: selected ? c.withValues(alpha: .55) : BrandColors.line,
            width: selected ? 1.2 : .8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(children: [
            Icon(icon, size: 17, color: c),
            const SizedBox(width: 9),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brandText)),
            ),
            Text(value,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: c,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 4),
            Icon(Icons.chevron_left_rounded,
                size: 17, color: BrandColors.mut),
          ]),
        ),
      ),
    );
  }
}

/// جدول الحركات المنظم — بحث + فلترة (الكل/كاش/تحويل) + طباعة حسب الظاهر.
/// [rows]: صفوفٌ تحمل date/name(أو patient_name)/amount وطريقةً في '_pay'
/// أو 'payment'. [dense] للهاتف (خطوط أصغر وحشوة أضيق).
class TreasuryMovesTable extends ConsumerStatefulWidget {
  const TreasuryMovesTable({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
    this.dense = false,
    this.showService = false,
    this.originalPrint = false,
    this.doctorPct = 50,
  });

  /// م154/د — عمود «نوع العلاج» بعد الاسم (حركات العيادات).
  final bool showService;

  /// م154/د — الطباعة بالتصميم الأصلي القديم (جداول المعالجات المجمعة
  /// بنسبتي الطبيب/العيادة) حسب الفلترة الظاهرة — لحركات العيادات.
  final bool originalPrint;
  final num doctorPct;

  final String title;

  /// عنوان فرعي للطباعة (الشهر عادةً).
  final String subtitle;
  final List<Map<String, Object?>> rows;
  final bool dense;

  @override
  ConsumerState<TreasuryMovesTable> createState() =>
      _TreasuryMovesTableState();
}

class _TreasuryMovesTableState extends ConsumerState<TreasuryMovesTable> {
  final _searchCtl = TextEditingController();
  String _pay = 'all';

  /// م154/د — الفرز: 'date' (الأحدث أولاً — الافتراضي) أو 'name'.
  String _sort = 'date';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  String _payOf(_JMap r) =>
      '${r['_pay'] ?? r['payment'] ?? ''}'.trim() == 'كاش' ? 'كاش' : 'تحويل';

  List<_JMap> get _visible {
    final q = _searchCtl.text.trim();
    return [
      for (final r in widget.rows)
        if ((_pay == 'all' ||
                (_pay == 'cash' ? _payOf(r) == 'كاش' : _payOf(r) != 'كاش')) &&
            (q.isEmpty ||
                '${r['name'] ?? r['patient_name'] ?? r['title'] ?? ''}'
                    .contains(q)))
          r,
    ]..sort((a, b) => _sort == 'name'
        ? '${a['name'] ?? a['patient_name'] ?? ''}'
            .compareTo('${b['name'] ?? b['patient_name'] ?? ''}')
        : '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'));
  }

  num get _visibleTotal {
    num s = 0;
    for (final r in _visible) {
      s += jsNumOr0(r['amount']);
    }
    return s;
  }

  Future<void> _print() async {
    final n = formatNumber;
    final cur = ref.read(currencyProvider);
    final fonts = await loadPdfBrand(ref);
    final rows = _visible;
    if (widget.originalPrint) {
      // م154/د — التقرير الأصلي القديم حرفياً (جداول المعالجات المجمعة
      // بنسبتي الطبيب/العيادة) على الصفوف الظاهرة حسب الفلترة.
      final bytes = await treatmentTablesPdf(
        fonts,
        title: widget.title +
            (_pay == 'all' ? '' : _pay == 'cash' ? ' — كاش' : ' — تحويل'),
        subtitle: widget.subtitle,
        currency: cur,
        tables: buildTreatmentTables(rows, fallbackPct: widget.doctorPct),
      );
      final msg = await printOrSharePdf(
          ref.read(dbDirProvider), bytes, 'treasury_moves.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }
    final bytes = await simpleTablePdf(
      fonts,
      title: widget.title +
          (_pay == 'all' ? '' : _pay == 'cash' ? ' — كاش' : ' — تحويل'),
      subtitle: widget.subtitle,
      headers: const ['التاريخ', 'الاسم', 'الدفع', 'القيمة'],
      rows: [
        for (final r in rows)
          [
            '${r['date'] ?? ''}',
            '${r['name'] ?? r['patient_name'] ?? r['title'] ?? ''}',
            _payOf(r),
            '${n(jsNumOr0(r['amount']))} $cur',
          ],
      ],
      totRow: ['المجموع', '', '', '${n(_visibleTotal)} $cur'],
    );
    final msg = await printOrSharePdf(
        ref.read(dbDirProvider), bytes, 'treasury_moves.pdf');
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final cur = ref.watch(currencyProvider);
    final visible = _visible;
    final fs = widget.dense ? 11.5 : 12.5;
    const segTxt = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700);

    final table = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.line, width: .8),
      ),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── شريط الأدوات: بحث + فلترة الدفع + طباعة ──────────────────────
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                key: const Key('tr2-search'),
                controller: _searchCtl,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'بحث بالاسم…',
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
              side: BorderSide(
                  color: BrandColors.gold.withValues(alpha: .3)),
            ),
            child: PopupMenuButton<String>(
              key: const Key('tr2-sort'),
              tooltip: 'فرز',
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                    value: 'date',
                    checked: _sort == 'date',
                    child: const Text('التاريخ الأحدث أولاً',
                        style: TextStyle(fontSize: 12.5))),
                CheckedPopupMenuItem(
                    value: 'name',
                    checked: _sort == 'name',
                    child: const Text('حسب الاسم',
                        style: TextStyle(fontSize: 12.5))),
              ],
              child: const SizedBox(
                width: 38,
                height: 36,
                child: Icon(Icons.filter_alt_outlined,
                    size: 16, color: BrandColors.goldDark),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: const Key('tr2-print'),
            visualDensity: VisualDensity.compact,
            tooltip: 'طباعة حسب الفلترة الظاهرة',
            icon: Icon(Icons.print_rounded,
                size: 18, color: BrandColors.brandIcon),
            onPressed: visible.isEmpty ? null : _print,
          ),
        ]),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SegmentedButton<String>(
            key: const Key('tr2-pay-filter'),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: BrandColors.surface2,
              foregroundColor: BrandColors.mut,
              selectedBackgroundColor: BrandColors.green,
              selectedForegroundColor: Colors.white,
              side: BorderSide(
                  color: BrandColors.green.withValues(alpha: .40)),
            ),
            segments: const [
              ButtonSegment(
                  value: 'all', label: Text('الكل', style: segTxt)),
              ButtonSegment(
                  value: 'cash', label: Text('كاش', style: segTxt)),
              ButtonSegment(
                  value: 'transfer', label: Text('تحويل', style: segTxt)),
            ],
            selected: {_pay},
            onSelectionChanged: (s) => setState(() => _pay = s.first),
          ),
        ),
        const SizedBox(height: 8),
        // ── رأس الجدول ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            SizedBox(
                width: widget.dense ? 74 : 90,
                child: Text('التاريخ', style: _head())),
            Expanded(child: Text('الاسم', style: _head())),
            if (widget.showService)
              Expanded(child: Text('نوع العلاج', style: _head())),
            SizedBox(
                width: 58,
                child: Text('الدفع',
                    style: _head(), textAlign: TextAlign.center)),
            SizedBox(
                width: widget.dense ? 76 : 96,
                child: Text('القيمة',
                    style: _head(), textAlign: TextAlign.center)),
          ]),
        ),
        Divider(height: 1, color: BrandColors.line),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text('لا حركات مطابقة',
                  key: const Key('tr2-empty'),
                  style: TextStyle(fontSize: 12, color: BrandColors.mut)),
            ),
          )
        else
          for (final r in visible) ...[
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(children: [
                SizedBox(
                  width: widget.dense ? 74 : 90,
                  child: Text('${r['date'] ?? ''}',
                      style: TextStyle(
                          fontSize: fs - 1,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.ink)),
                ),
                Expanded(
                  child: Text(
                      '${r['name'] ?? r['patient_name'] ?? r['title'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: fs, fontWeight: FontWeight.w700)),
                ),
                if (widget.showService)
                  Expanded(
                    child: Text('${r['service'] ?? '—'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: fs - .5,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.strong)),
                  ),
                SizedBox(width: 58, child: Center(child: _chip(_payOf(r)))),
                SizedBox(
                  width: widget.dense ? 76 : 96,
                  child: Text(n(jsNumOr0(r['amount'])),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: fs,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.green,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ])),
                ),
              ]),
            ),
            Divider(height: 1, color: BrandColors.line),
          ],
        const SizedBox(height: 8),
        // ── التذييل: مجموع الظاهر حسب الفلترة ────────────────────────────
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(46, 125, 90, .08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: const Color.fromRGBO(46, 125, 90, .25)),
          ),
          child: Row(children: [
            SizedBox(
              width: widget.dense ? 74 : 90,
              child: Text(
                  _pay == 'all'
                      ? 'المجموع'
                      : _pay == 'cash'
                          ? 'مجموع الكاش'
                          : 'مجموع التحويل',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.strong)),
            ),
            const Expanded(child: SizedBox()),
            if (widget.showService) const Expanded(child: SizedBox()),
            SizedBox(
                width: 58,
                child: Center(
                    child: Text(cur,
                        style: TextStyle(
                            fontSize: 9.5, color: BrandColors.strong)))),
            SizedBox(
              width: widget.dense ? 76 : 96,
              child: Text(n(_visibleTotal),
                  key: const Key('tr2-visible-total'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.green,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ]),
        ),
      ],
    ),
    );
    // م154/هـ — الكمبيوتر: أعمدة متقاربة والجدول يعانق اليمين، والمساحة
    // الفارغة تُترك يساراً (قرار المالك)؛ الهاتف بعرضه الكامل.
    return widget.dense
        ? table
        : Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: widget.showService ? 700 : 620),
              child: table,
            ),
          );
  }

  TextStyle _head() => TextStyle(
      fontSize: 11, fontWeight: FontWeight.w800, color: BrandColors.strong);

  Widget _chip(String pay) {
    final isCash = pay == 'كاش';
    final color = isCash ? BrandColors.green : const Color(0xFF8A6D1B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(pay,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

/// م154/ب — دفعات مجموعة تركيبات كصفوف موحدة (نقية): التركيبة غير الدين
/// دفعةٌ كاملة بحصصها المجمدة، ودفعة الدين بحصصها الثلاث المحسوبة —
/// نفس منطق prosGrouped وحساباته حرفياً، عرضاً فقط.
List<Map<String, Object?>> prosGroupPayments(ProsGroup g, num doctorPct) => [
      for (final it in g.items)
        if (it['_t'] == 'p' && !jsTruthy(it['isDebt']))
          {
            'date': it['date'],
            'amount': it['total'],
            'payment': it['payment'],
            'lab': it['labValue'],
            'doc': it['doctorShare'],
            'clin': it['clinicShare'],
          }
        else if (it['_t'] != 'p')
          {
            'date': it['date'],
            'amount': it['amount'],
            'payment': it['payment'],
            'lab': prosPayLab(it, doctorPct),
            'doc': prosPayDoc(it, doctorPct),
            'clin': prosPayClin(it, doctorPct),
          },
    ];

/// نوع تركيب المجموعة — أول نوعٍ غير فارغ من صفوف التركيبات.
String prosGroupType(ProsGroup g) {
  for (final it in g.items) {
    if (it['_t'] == 'p') {
      final t = '${it['prosType'] ?? ''}'.trim();
      if (t.isNotEmpty && t != 'null') return t;
    }
  }
  return 'تركيبات';
}

/// م154/ب — التركيبات من مستويين (قرار المالك):
/// المستوى الأول قائمة مرضى التركيبات (بحث + فرز): الاسم ونوع التركيب
/// وإجمالي القيمة والمدفوع الإجمالي. الدخول لاسمٍ يفتح جدول دفعاته
/// الدقيق: التاريخ/الدفعة/الدفع/المعمل/الطبيب/العيادة + صف إجمالي مميز
/// يجمع كل عمود — بنفس منطق prosGrouped وحساباته حرفياً. فلترة كاش/
/// تحويل داخل الاسم + طباعة كامل التركيبات بالتقرير القديم نفسه.
class TreasuryProsTable extends ConsumerStatefulWidget {
  const TreasuryProsTable({
    super.key,
    required this.groups,
    required this.doctorPct,
    required this.month,
    required this.clinic,
    this.dense = false,
  });

  final List<ProsGroup> groups;
  final num doctorPct;
  final String month;
  final String clinic;
  final bool dense;

  @override
  ConsumerState<TreasuryProsTable> createState() =>
      _TreasuryProsTableState();
}

class _TreasuryProsTableState extends ConsumerState<TreasuryProsTable> {
  final _searchCtl = TextEditingController();
  String _sort = 'recent';
  String? _open;
  String _pay = 'all';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _printAll() async {
    final fonts = await loadPdfBrand(ref);
    final bytes = await prostheticsReportPdf(
      fonts,
      title: 'تركيبات ${widget.clinic}',
      subtitle: widget.month,
      currency: ref.read(currencyProvider),
      groups: widget.groups,
      doctorPct: widget.doctorPct,
    );
    final msg = await printOrSharePdf(
        ref.read(dbDirProvider), bytes, 'treasury_pros.pdf');
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final cur = ref.watch(currencyProvider);
    final fs = widget.dense ? 11.5 : 12.5;

    // ── المستوى الثاني: جدول دفعات الاسم المفتوح ────────────────────────
    if (_open != null) {
      final g = widget.groups.firstWhere((x) => x.name == _open,
          orElse: () => ProsGroup(_open!));
      final all = prosGroupPayments(g, widget.doctorPct);
      final rows = [
        for (final r in all)
          if (_pay == 'all' ||
              (_pay == 'cash'
                  ? r['payment'] == 'كاش'
                  : r['payment'] != 'كاش'))
            r,
      ];
      num tAmt = 0, tLab = 0, tDoc = 0, tClin = 0;
      for (final r in rows) {
        tAmt += jsNumOr0(r['amount']);
        tLab += jsNumOr0(r['lab']);
        tDoc += jsNumOr0(r['doc']);
        tClin += jsNumOr0(r['clin']);
      }
      TextStyle head() => TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: BrandColors.strong);
      Widget num6(String v, {Color? color, bool bold = false}) => Expanded(
            child: Text(v,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: fs - .5,
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          );
      const segTxt =
          TextStyle(fontSize: 11, fontWeight: FontWeight.w700);

      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BrandColors.line, width: .8),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            IconButton(
              key: const Key('tr2-pros-back'),
              visualDensity: VisualDensity.compact,
              tooltip: 'رجوع للقائمة',
              icon: Icon(Icons.arrow_forward_rounded,
                  size: 18, color: BrandColors.brandIcon),
              onPressed: () => setState(() => _open = null),
            ),
            Expanded(
              child: Text(g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: fs + 1.5,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.brandText)),
            ),
            SegmentedButton<String>(
              key: const Key('tr2-pros-pay'),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: BrandColors.surface2,
                foregroundColor: BrandColors.mut,
                selectedBackgroundColor: BrandColors.goldDark,
                selectedForegroundColor: Colors.white,
                side: BorderSide(
                    color: BrandColors.gold.withValues(alpha: .4)),
              ),
              segments: const [
                ButtonSegment(
                    value: 'all', label: Text('الكل', style: segTxt)),
                ButtonSegment(
                    value: 'cash', label: Text('كاش', style: segTxt)),
                ButtonSegment(
                    value: 'transfer',
                    label: Text('تحويل', style: segTxt)),
              ],
              selected: {_pay},
              onSelectionChanged: (v) => setState(() => _pay = v.first),
            ),
            IconButton(
              key: const Key('tr2-pros-print'),
              visualDensity: VisualDensity.compact,
              tooltip: 'طباعة كامل التركيبات',
              icon: Icon(Icons.print_rounded,
                  size: 18, color: BrandColors.brandIcon),
              onPressed: _printAll,
            ),
          ]),
          const SizedBox(height: 8),
          // رأس الجدول — ستة أعمدة بتوسيط دقيق (التاريخ من اليمين).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: [
              SizedBox(
                  width: widget.dense ? 70 : 92,
                  child: Text('التاريخ',
                      textAlign: TextAlign.start, style: head())),
              num6('الدفعة', bold: true),
              SizedBox(
                  width: 54,
                  child: Text('الدفع',
                      textAlign: TextAlign.center, style: head())),
              num6('المعمل', bold: true),
              num6('الطبيب', bold: true),
              num6('العيادة', bold: true),
            ]),
          ),
          Divider(height: 1, color: BrandColors.line),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('لا دفعات مطابقة',
                    style:
                        TextStyle(fontSize: 12, color: BrandColors.mut)),
              ),
            )
          else
            for (final r in rows) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5),
                child: Row(children: [
                  SizedBox(
                    width: widget.dense ? 70 : 92,
                    child: Text('${r['date'] ?? ''}',
                        textAlign: TextAlign.start,
                        style: TextStyle(
                            fontSize: fs - 1.5,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.ink)),
                  ),
                  num6(n(jsNumOr0(r['amount'])),
                      color: BrandColors.green),
                  SizedBox(
                    width: 54,
                    child: Center(
                      child: Text('${r['payment'] ?? ''}',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: r['payment'] == 'كاش'
                                  ? BrandColors.green
                                  : const Color(0xFF8A6D1B))),
                    ),
                  ),
                  num6(n(jsNumOr0(r['lab'])), color: BrandColors.ink),
                  num6(n(jsNumOr0(r['doc'])),
                      color: BrandColors.goldDark),
                  num6(n(jsNumOr0(r['clin'])),
                      color: BrandColors.brand700),
                ]),
              ),
              Divider(height: 1, color: BrandColors.line),
            ],
          // ── صف الإجمالي المميز: مجموع نهائي تحت كل عمود ─────────────────
          Container(
            key: const Key('tr2-pros-footer'),
            margin: const EdgeInsets.only(top: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(201, 162, 75, .10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color.fromRGBO(201, 162, 75, .30)),
            ),
            child: Row(children: [
              SizedBox(
                  width: widget.dense ? 70 : 92,
                  child: Text('الإجمالي',
                      style: TextStyle(
                          fontSize: fs - 1,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.strong))),
              num6(n(tAmt), color: BrandColors.green, bold: true),
              SizedBox(
                  width: 54,
                  child: Center(
                      child: Text(cur,
                          style: TextStyle(
                              fontSize: 9.5,
                              color: BrandColors.mut2)))),
              num6(n(tLab), color: BrandColors.ink, bold: true),
              num6(n(tDoc), color: BrandColors.goldDark, bold: true),
              num6(n(tClin), color: BrandColors.brand700, bold: true),
            ]),
          ),
        ],
      ),
      );
    }

    // ── المستوى الأول: قائمة مرضى التركيبات ─────────────────────────────
    final q = _searchCtl.text.trim();
    final list = [
      for (final g in widget.groups)
        if (q.isEmpty || g.name.contains(q)) g,
    ];
    if (_sort == 'name') list.sort((a, b) => a.name.compareTo(b.name));

    num paidOf(ProsGroup g) {
      num s0 = 0;
      for (final r in prosGroupPayments(g, widget.doctorPct)) {
        s0 += jsNumOr0(r['amount']);
      }
      return s0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                key: const Key('tr2-pros-search'),
                controller: _searchCtl,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'بحث بالاسم…',
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
              side: BorderSide(
                  color: BrandColors.gold.withValues(alpha: .3)),
            ),
            child: PopupMenuButton<String>(
              key: const Key('tr2-pros-sort'),
              tooltip: 'فرز',
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                    value: 'recent',
                    checked: _sort == 'recent',
                    child: const Text('الأحدث أولاً',
                        style: TextStyle(fontSize: 12.5))),
                CheckedPopupMenuItem(
                    value: 'name',
                    checked: _sort == 'name',
                    child: const Text('بالاسم',
                        style: TextStyle(fontSize: 12.5))),
              ],
              child: const SizedBox(
                width: 38,
                height: 36,
                child: Icon(Icons.filter_alt_outlined,
                    size: 16, color: BrandColors.goldDark),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            key: const Key('tr2-pros-print-all'),
            visualDensity: VisualDensity.compact,
            tooltip: 'طباعة كامل التركيبات',
            icon: Icon(Icons.print_rounded,
                size: 18, color: BrandColors.brandIcon),
            onPressed: widget.groups.isEmpty ? null : _printAll,
          ),
        ]),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text('لا تركيبات هذا الشهر',
                  style: TextStyle(fontSize: 12, color: BrandColors.mut)),
            ),
          )
        else
          for (final g in list) ...[
            Material(
              color: BrandColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: BrandColors.line, width: .8),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('tr2-pros-g-${g.name}'),
                onTap: () => setState(() {
                  _open = g.name;
                  _pay = 'all';
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.person_rounded,
                        size: 17, color: BrandColors.goldDark),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: fs,
                                  fontWeight: FontWeight.w800,
                                  color: BrandColors.brandText)),
                          const SizedBox(height: 2),
                          Text(
                              'نوع التركيب: ${prosGroupType(g)}'
                              ' • الإجمالي: ${n(g.total)}'
                              ' • المدفوع: ${n(paidOf(g))} $cur',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: fs - 2,
                                  fontWeight: FontWeight.w700,
                                  color: BrandColors.strong)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_left_rounded,
                        size: 17, color: BrandColors.mut),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

/// جدول «الإجمالي» — العيادات/التحاليل/المصروفات × (كاش/تحويل/إجمالي)
/// + صف الصافي بعد خصم المصروفات (قرار المالك) — كله بنطاق الشهر المختار.
class TreasuryTotalsTable extends ConsumerWidget {
  const TreasuryTotalsTable({
    super.key,
    required this.month,
    required this.clinicsCash,
    required this.clinicsXfer,
    required this.clinicsGrand,
    required this.analCash,
    required this.analXfer,
    required this.expCash,
    required this.expXfer,
    required this.expTotal,
    this.det = true,
    this.dense = false,
  });

  final String month;
  final num clinicsCash;
  final num clinicsXfer;

  /// المحصّل الشامل للعيادات (يتضمن التركيبات المدفوعة).
  final num clinicsGrand;
  final num analCash;
  final num analXfer;
  final num expCash;
  final num expXfer;
  final num expTotal;
  final bool det;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = formatNumber;
    final fs = dense ? 12.0 : 13.0;

    String v(num x) => det ? n(x) : '—';

    Widget cell(String txt,
            {Color? color, bool bold = false, bool head = false}) =>
        Expanded(
          child: Text(txt,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: head ? 11 : fs,
                  fontWeight:
                      bold || head ? FontWeight.w800 : FontWeight.w700,
                  color: color ?? (head ? BrandColors.mut2 : null),
                  fontFeatures: const [FontFeature.tabularFigures()])),
        );

    Widget row(String label, num cash, num xfer, num total,
        {Color? color, Key? key, bool emphasize = false}) {
      return Container(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: emphasize
            ? BoxDecoration(
                color: const Color.fromRGBO(46, 125, 90, .08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color.fromRGBO(46, 125, 90, .25)),
              )
            : null,
        child: Row(children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: TextStyle(
                    fontSize: fs - .5,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.brandText)),
          ),
          cell(v(cash), color: color),
          cell(v(xfer), color: color),
          cell(v(total), color: color, bold: true),
        ]),
      );
    }

    return Card(
      key: const Key('tr2-totals-table'),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text('إجمالي الخزينة — $month',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.brandText)),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                const Expanded(flex: 2, child: SizedBox()),
                cell('كاش', head: true),
                cell('تحويل', head: true),
                cell('الإجمالي', head: true),
              ]),
            ),
            const SizedBox(height: 4),
            Divider(height: 1, color: BrandColors.line),
            row('إيراد العيادات', clinicsCash, clinicsXfer, clinicsGrand,
                color: BrandColors.brand700, key: const Key('tr2-tot-clinics')),
            Divider(height: 1, color: BrandColors.line),
            row('إيراد التحاليل الثلاثية', analCash, analXfer,
                analCash + analXfer,
                color: BrandColors.green, key: const Key('tr2-tot-anal')),
            Divider(height: 1, color: BrandColors.line),
            row('المصروفات', expCash, expXfer, expTotal,
                color: BrandColors.red, key: const Key('tr2-tot-exp')),
            const SizedBox(height: 10),
            row(
              'صافي الخزينة (بعد الخصم)',
              clinicsCash + analCash - expCash,
              clinicsXfer + analXfer - expXfer,
              clinicsGrand + analCash + analXfer - expTotal,
              color: BrandColors.brand900,
              key: const Key('tr2-tot-net'),
              emphasize: true,
            ),
          ],
        ),
      ),
    );
  }
}
