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
    // م178/ب — تسطيح المجموعات إلى صفوفٍ مفردة (العيادة عمود): ترتيب
    // المجموعات وصفوفها محفوظ كما يعيده financialStatement (الأحدث
    // إنشاءً أولاً) — العرضُ وحده تغيّر لا المنطق.
    final rows = <({
      String clinic,
      String date,
      String name,
      String payment,
      String service,
      num amount
    })>[
      for (final g in groups)
        for (final p in g.patients)
          (
            clinic: g.clinic,
            date: p.date,
            name: p.name,
            payment: p.payment,
            service: p.service,
            amount: p.amount,
          ),
    ];

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
        // م178/ب — النتائج **جدول أبيض واحد مسطّح بهوية جدول الخزينة
        // حرفياً** (قرار المالك): لا تجميع بالعيادة ولا مجاميع فرعية —
        // العيادة صارت عموداً، والمجموع العام وحده أسفل الجدول.
        // الأعمدة: التاريخ · الاسم · اسم العيادة · نوع العلاج ·
        // طريقة الدفع (رقاقة) · القيمة.
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Text('لا حركات في المدى/الفلاتر المحددة',
                      key: const Key('st-empty'),
                      style: TextStyle(
                          fontSize: 12, color: BrandColors.mut2)))
              : ListView(
                  key: const Key('st-list'),
                  // م178/ج — هوامش الشاشة أخفّ (كانت 14): العرض المستعاد
                  // يذهب كله فواصلَ بين الأعمدة (طلب المالك).
                  padding: EdgeInsets.fromLTRB(
                      isDesktopUi(context) ? 14 : 6,
                      0,
                      isDesktopUi(context) ? 14 : 6,
                      90),
                  children: [_resultsTable(rows, cur, n)],
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

  /// م178/ب — جدول النتائج: نسخةٌ حرفية من هوية [TreasuryMovesTable]
  /// (غلاف أبيض بزوايا 12 وحد .8 وحشوة 10، ترويسة `_thStyle`، صفوف
  /// بحشوة (8,5) وفواصل بينها، رقاقة دفعٍ ملوّنة، قيمة خضراء بأرقام
  /// جدولية، وتذييل مجموعٍ أخضر) — والكمبيوتر يعانق اليمين بعرضٍ محدود.
  Widget _resultsTable(
    List<({String clinic, String date, String name, String payment,
        String service, num amount})> rows,
    String cur,
    String Function(num) n,
  ) {
    final wide = isDesktopUi(context);
    // م178/ج — تنفّس الأعمدة (طلب المالك: «حس لاصقات ببعض»):
    //   • فاصل **بين كل عمودين** بلا استثناء (كان بين المجموعات فقط،
    //     فالتصقت «اسم العيادة» بـ«نوع العلاج»).
    //   • كل النصوص **متوسطة** في عمودها (كانت تبدأ من اليمين فتلامس
    //     العمود المجاور).
    //   • الأعمدة الثابتة أنحف على الهاتف والتاريخ بلا سنة — والعرض
    //     المستعاد يذهب فواصلَ.
    final fs = wide ? 12.5 : 11.5;
    final wDate = wide ? 86.0 : 44.0;
    final wPay = wide ? 70.0 : 50.0;
    final wVal = wide ? 92.0 : 58.0;
    final gap = wide ? 12.0 : 8.0;

    /// التاريخ: كامل على الكمبيوتر، ومختصر (MM-DD) على الهاتف.
    String dateOf(String d) =>
        wide || d.length < 10 ? d : d.substring(5);

    /// ترويسة عمود متوسطة النص داخل FittedBox انكماشي (سطر واحد، ونصُّها
    /// كما هو). بلا [width] تُرجع التسمية عارية ليلفّها المنادي بوزنه.
    Widget head(String txt, {double? width}) {
      final label = FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(txt,
            maxLines: 1, textAlign: TextAlign.center, style: _thStyle()),
      );
      return width == null ? label : SizedBox(width: width, child: label);
    }

    /// خلية نصية متوسطة في عمودها.
    Widget cell(String txt, {required double size, Color? color}) => Text(
          txt,
          maxLines: 1,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: size, fontWeight: FontWeight.w700, color: color),
        );

    final table = Container(
      padding: EdgeInsets.all(wide ? 10 : 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.line, width: .8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── رأس الأعمدة: التاريخ · الاسم · اسم العيادة · نوع العلاج ·
          //    طريقة الدفع · القيمة — بفاصلٍ بين كل عمودين وتوسيطٍ تام ──
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: wide ? 8 : 2, vertical: 4),
            child: Row(children: [
              head('التاريخ', width: wDate),
              SizedBox(width: gap),
              Expanded(flex: 3, child: head('الاسم')),
              SizedBox(width: gap),
              Expanded(flex: 3, child: head('اسم العيادة')),
              SizedBox(width: gap),
              Expanded(flex: 3, child: head('نوع العلاج')),
              SizedBox(width: gap),
              head('طريقة الدفع', width: wPay),
              SizedBox(width: gap),
              head('القيمة', width: wVal),
            ]),
          ),
          Divider(height: 1, color: BrandColors.line),
          for (final r in rows) ...[
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: wide ? 8 : 2, vertical: 6),
              child: Row(children: [
                SizedBox(
                  width: wDate,
                  child: Text(dateOf(r.date),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: fs - 1,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.ink,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ])),
                ),
                SizedBox(width: gap),
                Expanded(
                    flex: 3, child: cell(r.name, size: fs)),
                SizedBox(width: gap),
                Expanded(
                  flex: 3,
                  child: cell(r.clinic,
                      size: fs - .5, color: BrandColors.brandText),
                ),
                SizedBox(width: gap),
                Expanded(
                  flex: 3,
                  child: cell(r.service.isEmpty ? '—' : r.service,
                      size: fs - .5, color: BrandColors.strong),
                ),
                SizedBox(width: gap),
                SizedBox(
                    width: wPay,
                    child: Center(child: _payChip(r.payment))),
                SizedBox(width: gap),
                SizedBox(
                  width: wVal,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(n(r.amount),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: fs,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.green,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ]),
                    ),
                  ),
                ),
              ]),
            ),
            Divider(height: 1, color: BrandColors.line),
          ],
          const SizedBox(height: 8),
          // ── تذييل المجموع (نمط الخزينة: صندوق أخضر خفيف) ──
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: wide ? 10 : 4, vertical: 8),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(46, 125, 90, .08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color.fromRGBO(46, 125, 90, .25)),
            ),
            child: Row(children: [
              SizedBox(
                width: wide ? 90 : 62,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('المجموع',
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.strong)),
                ),
              ),
              const Expanded(child: SizedBox()),
              SizedBox(
                  width: wPay,
                  child: Center(
                      child: Text(cur,
                          style: TextStyle(
                              fontSize: 9.5,
                              color: BrandColors.strong)))),
              SizedBox(width: gap),
              SizedBox(
                width: wVal,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      n(rows.fold<num>(0, (s, r) => s + r.amount)),
                      key: const Key('st-table-total'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.green,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ),
            ]),
          ),
        ],
      ),
    );

    // م154/هـ — الكمبيوتر: الجدول يعانق اليمين بعرضٍ محدود والفراغ
    // يُترك يساراً (قرار المالك)؛ الهاتف بعرضه الكامل.
    return wide
        ? Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: table,
            ),
          )
        : table;
  }

  /// م178/ب — رقاقة طريقة الدفع بلوني الخزينة حرفياً: الكاش أخضر وغيره
  /// بنّي ذهبي، خلفية 10% وزوايا 8.
  Widget _payChip(String pay) {
    final isCash = pay == 'كاش' || pay == 'نقد' || pay == 'نقدي';
    final color = isCash ? BrandColors.green : const Color(0xFF8A6D1B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(pay.isEmpty ? '—' : pay,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: color)),
    );
  }

  /// م178 — نص ترويسة عمودٍ في جدول النتائج (توأم ترويسات الخزينة).
  TextStyle _thStyle() => TextStyle(
      fontSize: 11, fontWeight: FontWeight.w800, color: BrandColors.strong);

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
