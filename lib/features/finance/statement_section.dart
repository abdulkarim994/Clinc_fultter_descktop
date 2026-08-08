/// ============================================================================
///  م99 — قسم «كشف مالي»: الكشف بمدى تاريخي وفلترة متعددة وطباعة/تصدير
/// ============================================================================
///
///  رابعُ أقسام المالية (بجانب الخزينة والديون والأرباح)، بطلب المالك:
///  كشفٌ إجمالي للعيادات بمدى «من/إلى»، وفلترةٍ **متعددة الاختيار**
///  بالعيادات والفئات (كاش/تحويل/تركيبات/دين + أي طريقة دفعٍ مُعرَّفة)،
///  وبحثٍ بالاسم، وإجماليٍ أسفل، وطباعةٍ/تصدير PDF — بنفس هوية تفصيل
///  الخزينة (الكاش والتحويل).
///
///  المنطق كلُّه في `home_logic.financialStatement` (نقيٌّ ومختبَر)؛
///  هذا الملف واجهةٌ صرفة فوقه، والأحدثُ إضافةً أولاً.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../desktop/desktop_gate.dart' show isDesktopUi;
import '../desktop/widgets/desktop_dialogs.dart' show showDesktopDialog;
import 'finance_screen.dart' show financeRevProvider;
import '../print/print_service.dart' show loadPdfBrand, printOrSharePdf;
import '../print/reports.dart' show simpleTablePdf;
import '../print/treatment_tables.dart' show formatNumber;
import '../records/home_logic.dart' show financialStatement, kNoClinic;

class StatementSection extends ConsumerStatefulWidget {
  const StatementSection({super.key});

  @override
  ConsumerState<StatementSection> createState() => _StatementSectionState();
}

class _StatementSectionState extends ConsumerState<StatementSection> {
  final _nameCtl = TextEditingController();
  late String _from;
  late String _to;
  final Set<String> _clinics = {}; // فارغ = الكل
  final Set<String> _cats = {}; // فارغ = الكل
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _from = getCurrentDate();
    _to = _from;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  bool get _multiDay => _from != _to;

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// م109 — منتقي مدى واحد بدل زرَّي «من/إلى» (تبسيط الرأس).
  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
          start: DateTime.parse(_from), end: DateTime.parse(_to)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = _fmt(picked.start);
      _to = _fmt(picked.end);
    });
  }

  /// م109 — عدد الفلاتر المفعلة (شارة زر الفلاتر).
  int get _activeFilters => _clinics.length + _cats.length;

  /// م109 — ورقة الفلاتر السفلية: رقائق العيادة والفئة متعددة الاختيار
  /// (كانت صفين دائمين في الرأس — طلب المالك تجميعها وتبسيطها).
  Future<void> _openFilters() async {
    // نسخة الكمبيوتر: الفلاتر نفسها في حوار مركزي بدل الورقة السفلية.
    if (isDesktopUi(context)) {
      await showDesktopDialog<void>(
        context,
        title: 'الفلاتر',
        width: 460,
        builder: _filtersBody,
      );
      if (mounted) setState(() {});
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: _filtersBody,
    );
    if (mounted) setState(() {});
  }

  Widget _filtersBody(BuildContext context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text('الفلاتر',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.brandText)),
                ),
                if (_activeFilters > 0)
                  TextButton(
                    key: const Key('st-clear-filters'),
                    onPressed: () => setSheet(() => setState(() {
                          _clinics.clear();
                          _cats.clear();
                        })),
                    child: const Text('مسح الكل',
                        style: TextStyle(fontSize: 12)),
                  ),
              ]),
              const SizedBox(height: 4),
              _chipRow('العيادة', _clinicOptions, _clinics, 'st-clinic',
                  refresh: () => setSheet(() {})),
              const SizedBox(height: 8),
              _chipRow('الفئة', _catOptions, _cats, 'st-cat',
                  refresh: () => setSheet(() {})),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

  List<String> get _clinicOptions {
    final cfg = ref.read(appConfigProvider);
    return [
      if (cfg['clinics'] is List)
        for (final c in cfg['clinics'] as List) '$c',
      kNoClinic,
    ];
  }

  List<String> get _catOptions {
    final cfg = ref.read(appConfigProvider);
    final pays = [
      if (cfg['payments'] is List)
        for (final p in cfg['payments'] as List) '$p',
    ];
    // فئات ثابتة يضمنها الكشف: تركيبات + دين — مع طرق الدفع المُعرَّفة.
    return {
      ...pays,
      'تركيبات',
      'دين',
    }.toList();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final repos = ref.read(reposProvider);
      final cur = ref.read(currencyProvider);
      final n = formatNumber;
      final groups = financialStatement(
        repos.records.getAll(),
        repos.prosthetics.getAll(),
        from: _from,
        to: _to,
        clinics: _clinics,
        categories: _cats,
        nameQuery: _nameCtl.text,
      );
      final rows = <List<String>>[];
      num grand = 0;
      for (final g in groups) {
        grand += g.total;
        for (final p in g.patients) {
          rows.add([
            p.date,
            p.name,
            g.clinic,
            p.payment,
            '${n(p.amount)} $cur',
          ]);
        }
      }
      final fonts = await loadPdfBrand(ref);
      final filters = <String>[
        if (_clinics.isNotEmpty) 'العيادات: ${_clinics.join('، ')}',
        if (_cats.isNotEmpty) 'الفئات: ${_cats.join('، ')}',
        if (_nameCtl.text.trim().isNotEmpty) 'بحث: ${_nameCtl.text.trim()}',
      ];
      final bytes = await simpleTablePdf(
        fonts,
        title: 'كشف مالي من $_from إلى $_to',
        subtitle: filters.isEmpty ? 'كل العيادات وطرق الدفع' : filters.join('  •  '),
        headers: const ['التاريخ', 'الاسم', 'العيادة', 'الفئة', 'المبلغ'],
        rows: rows,
        totRow: ['الإجمالي', '', '', '', '${n(grand)} $cur'],
      );
      final msg = await printOrSharePdf(
        ref.read(dbDirProvider),
        bytes,
        'statement_${_from}_$_to.pdf',
        auditDb: ref.read(localDbProvider),
        auditEntity: 'statement',
        auditId: '${_from}_$_to',
      );
      if (mounted) _snack(msg);
    } catch (e) {
      if (mounted) _snack('تعذّرت الطباعة: $e');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(financeRevProvider); // إعادة البناء عند أي كتابة مالية
    final repos = ref.read(reposProvider);
    final cur = ref.watch(currencyProvider);
    final n = formatNumber;
    final groups = financialStatement(
      repos.records.getAll(),
      repos.prosthetics.getAll(),
      from: _from,
      to: _to,
      clinics: _clinics,
      categories: _cats,
      nameQuery: _nameCtl.text,
    );
    num grand = 0;
    for (final g in groups) {
      grand += g.total;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
          // م109 — رأسٌ بصفٍّ واحد (كان أربعة): بحث + مدى واحد + فلاتر
          // بورقة سفلية بشارة عدّ + طباعة — كل الوظائف كما هي.
          child: Row(children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  key: const Key('st-search'),
                  controller: _nameCtl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'بحث بالاسم',
                    prefixIcon:
                        const Icon(Icons.search_rounded, size: 17),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10),
                    filled: true,
                    fillColor: BrandColors.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: BrandColors.line),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _headerBtn(
              key: const Key('st-range'),
              onTap: _pickRange,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_month_rounded,
                    size: 15, color: BrandColors.brandIcon),
                const SizedBox(width: 4),
                Text(_rangeLabel,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(width: 6),
            _headerBtn(
              key: const Key('st-filters'),
              onTap: _openFilters,
              child: Stack(clipBehavior: Clip.none, children: [
                Icon(Icons.tune_rounded,
                    size: 17, color: BrandColors.brandIcon),
                if (_activeFilters > 0)
                  PositionedDirectional(
                    top: -5,
                    end: -7,
                    child: Container(
                      width: 15,
                      height: 15,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle),
                      child: Text('$_activeFilters',
                          key: const Key('st-filters-count'),
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                          ),
                          style: const TextStyle(
                              fontSize: 8.5,
                              height: 1.0,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 6),
            Material(
              color: BrandColors.brand600.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: const Key('st-print'),
                borderRadius: BorderRadius.circular(10),
                onTap: _printing ? null : _print,
                child: SizedBox(
                  width: 40,
                  height: 38,
                  child: _printing
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.print_rounded,
                          size: 18, color: BrandColors.brandIcon),
                ),
              ),
            ),
          ]),
        ),
        const Divider(height: 14),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Text('لا حركات في المدى/الفلاتر المحددة',
                      key: const Key('st-empty'),
                      style: TextStyle(
                          fontSize: 12, color: BrandColors.mut2)))
              : ListView(
                  key: const Key('st-list'),
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 90),
                  children: [
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 4),
                        child: Row(children: [
                          Icon(Icons.local_hospital_rounded,
                              size: 14, color: BrandColors.brandIcon),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(g.clinic,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: BrandColors.brandText)),
                          ),
                          Text('${n(g.total)} $cur',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800)),
                        ]),
                      ),
                      for (final p in g.patients)
                        Container(
                          margin:
                              const EdgeInsets.symmetric(vertical: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: BrandColors.surface2,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: BrandColors.line),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                      [
                                        if (p.service.isNotEmpty) p.service,
                                        if (p.payment.isNotEmpty) p.payment,
                                        if (_multiDay) p.date,
                                      ].join(' · '),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: BrandColors.mut2)),
                                ],
                              ),
                            ),
                            Text('${n(p.amount)} $cur',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: BrandColors.goldDark)),
                          ]),
                        ),
                    ],
                  ],
                ),
        ),
        // ── الإجمالي أسفل (يتبع كل الفلاتر) ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: BrandColors.surface2,
            border: Border(top: BorderSide(color: BrandColors.line)),
          ),
          child: Row(children: [
            const Expanded(
                child: Text('الإجمالي',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w900))),
            Text('${n(grand)} $cur',
                key: const Key('st-total'),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: BrandColors.goldDark)),
          ]),
        ),
      ],
    );
  }

  /// م109 — نص المدى المضغوط لزر الرأس: يوم واحد = تاريخه، وإلا مدى.
  String get _rangeLabel {
    String dm(String d) =>
        d.length >= 10 ? '${d.substring(8, 10)}/${d.substring(5, 7)}' : d;
    return _multiDay ? '${dm(_from)}–${dm(_to)}' : dm(_from);
  }

  /// م109 — زر رأسٍ موحد الهوية (مدى/فلاتر) بمقاس زر الطباعة نفسه.
  Widget _headerBtn({
    required Key key,
    required VoidCallback onTap,
    required Widget child,
  }) =>
      Material(
        color: BrandColors.surface2,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: BrandColors.line),
            ),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      );

  /// صف رقائق فلترة متعددة الاختيار — «الكل» حين لا تحديد.
  Widget _chipRow(
      String label, List<String> options, Set<String> selected, String keyBase,
      {VoidCallback? refresh}) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('$label:',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: BrandColors.mut2)),
          ),
          for (final o in options)
            FilterChip(
              key: Key('$keyBase-$o'),
              label: Text(o, style: const TextStyle(fontSize: 11)),
              selected: selected.contains(o),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selectedColor: BrandColors.brand600.withValues(alpha: .16),
              checkmarkColor: BrandColors.brandIcon,
              onSelected: (on) {
                setState(() {
                  if (on) {
                    selected.add(o);
                  } else {
                    selected.remove(o);
                  }
                });
                // داخل الورقة السفلية: تحديث حالتها الحية أيضاً.
                refresh?.call();
              },
            ),
        ],
      ),
    );
  }
}
