/// م149 — بطاقة «سجلات التحاليل الثلاثية» المستقلة في الخزينة.
///
/// بطاقة قائمة بذاتها (لا تجاور كاش/تحويل أي عيادة) بنموذجين من ودجة
/// واحدة: جدول كامل لسطح المكتب (dense: false) وقائمة مكثفة للهاتف
/// (dense: true). المصدر: صفوف isAnalysis **للشهر الميلادي الجاري فقط**
/// بتاريخ اليوم — «التصفير التلقائي» أول كل شهرٍ يتحقق بطبيعة الاستعلام
/// (نطاق الشهر بالتاريخ الجاري، لا حالة مخزنة تحتاج تصفيراً) — مستقلةٌ
/// عن مبدّل شهر الخزينة عمداً.
///
/// الفلاتر تتركب معاً: بحثٌ بالاسم (بالتطبيع العربي عبر filterAnalysesRows)
/// + طريقة الدفع (الكل/كاش/تحويل) + العيادة (قائمة عيادات المركز). قدرات
/// م145 منقولةٌ إلى هنا: تعديل البند (القيمة/الطريقة) وحذفه والطباعة.
/// التعديل عبر records.updateLocal والحذف عبر records.delete (متزامنان)،
/// خلف صلاحيتَي records.edit/records.delete؛ وإجمالي التذييل خلف
/// treasury.details كبقية المجاميع (م121/م125).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../print/print_service.dart' show loadPdfBrand, printOrSharePdf;
import '../print/reports.dart' show simpleTablePdf;
import '../print/treatment_tables.dart' show formatNumber;
// م168 — بعد الإيقاف يصير السجل عرضاً تاريخياً فقط (بلا تعديل/حذف).
import '../settings/analyses3.dart' show kTriAnalysesName, triAnalysesEnabled;
import '../../core/utils/ar_normalize.dart' show normPhone;
import '../patients/patient_profile_screen.dart' show PatientProfileScreen;
import '../patients/patients_logic.dart' show IdentityIndex, identityOfRow;
import '../staff/staff_gate.dart' show staffAllowed;
import 'analyses_filter.dart'
    show currentMonthTotal, filterAnalysesRows;
import 'finance_screen.dart' show financeRevProvider;

typedef _JMap = Map<String, Object?>;

/// صفوف السجل النقية — م154: **الأرشيف الكامل** (كل الشهور) مرتباً الأحدث
/// أولاً بمنع تكرارٍ بالمعرّف — السجل الدائم في «السجلات» لا يصفر أبداً؛
/// التصفير الشهري صار شأن الخزينة الجديدة وحدها.
List<Map<String, Object?>> analysesRegistryRows(
  List<Map<String, Object?>> records) {
  final seen = <String>{};
  final out = <Map<String, Object?>>[
    for (final r in records)
      if (jsTruthy(r['isAnalysis']) &&
          '${r['id'] ?? ''}'.isNotEmpty &&
          seen.add('${r['id']}'))
        r,
  ];
  out.sort((a, b) => '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'));
  return out;
}

/// م154 — شاشة «إيراد التحاليل الثلاثية» داخل السجلات (الهاتف): السجل
/// الدائم الكامل بفلاتره — انتقل من الخزينة بقرار المالك، فالخزينة صارت
/// شهريةً تصفر وهذا أرشيفٌ تاريخي لا يصفر.
class AnalysesRegistryScreen extends StatelessWidget {
  const AnalysesRegistryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إيراد التحاليل الثلاثية',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: const [AnalysesRegistryCard(dense: true)],
      ),
    );
  }
}

/// م154 — مدخل السجل المثبّت (بطاقة/صفّ مضغوط): يظهر أعلى قائمة المرضى
/// على الجهازين ويفتح السجل الكامل — لا يظهر إلا حين الميزة مفعّلة.
class AnalysesRegistryEntry extends StatelessWidget {
  const AnalysesRegistryEntry({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BrandColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: BrandColors.green.withValues(alpha: .35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('anal-registry-entry'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(Icons.biotech_rounded, size: 18, color: BrandColors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text('إيراد التحاليل الثلاثية',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brandText)),
            ),
            Text('السجل الكامل',
                style: TextStyle(fontSize: 11, color: BrandColors.mut2)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_left_rounded,
                size: 18, color: BrandColors.mut),
          ]),
        ),
      ),
    );
  }
}

/// بطاقة سجلات التحاليل الثلاثية — نموذجا سطح المكتب والهاتف من مصدرٍ واحد.
class AnalysesRegistryCard extends ConsumerStatefulWidget {
  const AnalysesRegistryCard({
    super.key,
    this.dense = false,
    this.showIndex = false,
    this.showDate = false,
    this.inlineTotal = false,
  });

  /// true = قائمة الهاتف المكثفة؛ false = جدول سطح المكتب الكامل.
  final bool dense;

  /// م155 — عمود «#» التسلسلي في جدول سطح المكتب (لوح السجلات).
  final bool showIndex;

  /// م155 — عمود «التاريخ» في جدول سطح المكتب (لوح السجلات).
  final bool showDate;

  /// م155 — صف «الإجمالي» ختاماً داخل الجدول (مجموع الظاهر بعد الفلاتر).
  final bool inlineTotal;

  @override
  ConsumerState<AnalysesRegistryCard> createState() =>
      _AnalysesRegistryCardState();
}

class _AnalysesRegistryCardState extends ConsumerState<AnalysesRegistryCard> {
  final _searchCtl = TextEditingController();

  /// وضع فلتر الطريقة: 'all' | 'cash' | 'transfer'.
  String _mode = 'all';

  /// فلتر العيادة — فارغ = كل العيادات.
  String _clinic = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  /// عيادة الصف للعرض (clinic ثم clinic_id احتياطاً — نفس اصطلاح الفلتر).
  static String _rowClinic(_JMap r) {
    final c = '${r['clinic'] ?? ''}'.trim();
    if (c.isNotEmpty && c != 'null') return c;
    return '${r['clinic_id'] ?? ''}'.trim();
  }

  /// م189 — رقم هاتف الصفّ للعرض (طلب المالك: عمودٌ يميّز مريضاً عن سميّه).
  ///
  /// ثلاثة مصادر بالترتيب: عمودُه الخام ⇐ **الخام من زيارته الأصل**
  /// (`analysisOf` — فصفوفُ ما قبل م189 المكتوبة بلا هاتف تظهر بأرقامها)
  /// ⇐ القانوني من الحلّال الموروث. الخام مقدَّمٌ ليقرأ المالك الرقم كما
  /// كتبه (بصفر البدء) لا مطبَّعاً.
  ///
  /// م190 — وحين لا يبقى إلا القانوني (بلا صفر البدء) يُردُّ شكلُه الخام من
  /// أي صفٍّ يشاركه الهوية ([rawByCanon]) — فلا يرى المالك رقماً ناقص
  /// الصفر أبداً (بلاغه: «يعرض رقم الهاتف بدون 0 — اجعله بصفر»).
  String _rowPhoneText(_JMap r, Map<String, _JMap> byId, IdentityIndex idx,
      Map<String, String> rawByCanon) {
    String raw(Object? v) =>
        '${v ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    final own = raw(r['phone']);
    if (own.isNotEmpty) return own;
    final parent = byId['${r['analysisOf'] ?? ''}'];
    if (parent != null) {
      final p = raw(parent['phone']);
      if (p.isNotEmpty) return p;
    }
    final canon = idx.phoneOf(r);
    if (canon.isEmpty) return '—';
    return rawByCanon[canon] ?? canon;
  }

  /// م190 — فتح ملف المريض من السجل (طلب المالك) بهويته **الموروثة**:
  /// صفُّ التحليل قد يكون بلا هاتف، فتُحلّ هويته عن زيارته الأصل — وبها
  /// يفتح ملف صاحبه لا ملف سميّه. بلا عيادة لا ملف، فنكتفي بتنبيه.
  void _openPatient(_JMap r, IdentityIndex idx) {
    final name = '${r['name'] ?? r['patient_name'] ?? ''}'.trim();
    final clinic = _rowClinic(r);
    if (name.isEmpty || clinic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن فتح الملف: بيانات الصف ناقصة')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PatientProfileScreen(
        patientName: name,
        clinic: clinic,
        identity: identityOfRow(r, idx),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(financeRevProvider);
    final repos = ref.watch(reposProvider);
    final cur = ref.watch(currencyProvider);
    final clinics = ref.watch(clinicsProvider);
    final n = formatNumber;
    final today = getCurrentDate();
    final month = today.length >= 7 ? today.substring(0, 7) : today;

    final allRows = analysesRegistryRows(
      repos.records.getAll().cast<Map<String, Object?>>(),
    );
    final visible = filterAnalysesRows(
      allRows,
      query: _searchCtl.text,
      mode: _mode,
      clinic: _clinic,
    );
    final total = currentMonthTotal(visible, today: today);
    final det = staffAllowed('treasury.details');

    // م187 — هوية حاوية «جدول الحركات» حرفياً: بيضاء مسطّحة بزوايا 12
    // وحدٍّ رقيق (بدل ارتفاع Card) — فتتطابق البطاقتان بصرياً.
    return Container(
      key: const Key('anal-reg-card'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.line, width: .8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── الرأس: أيقونة + الاسم + زر الطباعة ─────────────────────────
            Row(children: [
              Icon(Icons.biotech_rounded,
                  size: 18, color: BrandColors.green),
              const SizedBox(width: 7),
              Expanded(
                child: Text('سجلات $kTriAnalysesName',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.brandText)),
              ),
              IconButton(
                key: const Key('anal-reg-print'),
                visualDensity: VisualDensity.compact,
                tooltip: 'طباعة السجل',
                icon: Icon(Icons.print_rounded,
                    size: 17, color: BrandColors.brandIcon),
                onPressed: visible.isEmpty ? null : () => _print(visible, cur),
              ),
            ]),
            const SizedBox(height: 8),
            // ── شريط الفلترة: بحث + طريقة الدفع + العيادة (تتركب معاً) ─────
            _filterBar(clinics),
            const SizedBox(height: 8),
            // ── الجسم: جدول سطح المكتب أو قائمة الهاتف المكثفة ─────────────
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    allRows.isEmpty
                        ? 'لا تحاليل مسجلة بعد'
                        : 'لا نتائج مطابقة للفلاتر',
                    key: const Key('anal-reg-empty'),
                    style: TextStyle(fontSize: 12, color: BrandColors.mut),
                  ),
                ),
              )
            else
              // م187 — جدول واحد بهوية الحركات للهاتف والكمبيوتر معاً.
              _movesTable(visible, cur, n),
            // ── التذييل: إجمالي الشهر الميلادي الجاري وحده ─────────────────
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(46, 125, 90, .08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color.fromRGBO(46, 125, 90, .25)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text('إجمالي الشهر الحالي ($month)',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.strong)),
                ),
                Text(det ? '${n(total)} $cur' : '—',
                    key: const Key('anal-reg-total'),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: BrandColors.green,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── شريط الفلترة ──────────────────────────────────────────────────────────

  Widget _filterBar(List<String> clinics) {
    final search = TextField(
      key: const Key('anal-reg-search'),
      controller: _searchCtl,
      style: const TextStyle(fontSize: 12.5),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'بحث بالاسم…',
        prefixIcon: const Icon(Icons.search_rounded, size: 16),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 30, minHeight: 30),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onChanged: (_) => setState(() {}),
    );
    // نمط عنوان المقطع يُمرَّر على النص نفسه (يندمج مع النمط الموروث
    // فتبقى عائلة خط التطبيق) — لا عبر styleFrom(textStyle) الذي يستبدله.
    const segTxt = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700);
    final paySeg = SegmentedButton<String>(
      key: const Key('anal-reg-filter'),
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        backgroundColor: BrandColors.surface2,
        foregroundColor: BrandColors.mut,
        selectedBackgroundColor: BrandColors.green,
        selectedForegroundColor: Colors.white,
        side: BorderSide(color: BrandColors.green.withValues(alpha: .40)),
      ),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'all', label: Text('الكل', style: segTxt)),
        ButtonSegment(value: 'cash', label: Text('كاش', style: segTxt)),
        ButtonSegment(
            value: 'transfer', label: Text('تحويل', style: segTxt)),
      ],
      selected: {_mode},
      onSelectionChanged: (s) => setState(() => _mode = s.first),
    );
    final clinicDd = DropdownButtonFormField<String>(
      key: const Key('anal-reg-clinic'),
      initialValue: _clinic,
      isDense: true,
      // يتمدد لعرض قيده ويقصّ النص الطويل — يمنع فيض الصف على الشاشات
      // الضيقة (النموذج المكثف) بدل أن يفرض عرضه الجوهري.
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      // نمط البنود على النصوص نفسها (يندمج مع الموروث فتبقى عائلة الخط).
      items: [
        DropdownMenuItem(
            value: '',
            child: Text('كل العيادات',
                style: TextStyle(
                    fontSize: 12, color: BrandColors.strong))),
        for (final c in clinics)
          DropdownMenuItem(
              value: c,
              child: Text(c,
                  style: TextStyle(
                      fontSize: 12, color: BrandColors.strong))),
      ],
      onChanged: (v) => setState(() => _clinic = v ?? ''),
    );

    // الهاتف: البحث سطرٌ ثم العيادة سطرٌ ثم الطريقة — رصٌّ عمودي لأن عرض
    // المقاطع الثلاثة + القائمة معاً يفيض على الشاشات الضيقة؛
    // سطح المكتب: صفٌّ واحد.
    if (widget.dense) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: 6),
          clinicDd,
          const SizedBox(height: 6),
          Center(child: paySeg),
        ],
      );
    }
    return Row(children: [
      Expanded(flex: 3, child: search),
      const SizedBox(width: 8),
      paySeg,
      const SizedBox(width: 8),
      Expanded(flex: 2, child: clinicDd),
    ]);
  }

  // ── م187 — جدول واحد بهوية «جدول الحركات» في الخزينة ────────────────
  //
  // قرار المالك: «تحويل شكل التحاليل الثلاثية بالسجلات إلى جدول مشابه
  // جدول الحركات في الخزينة (مشابه تماماً) مع بقاء إمكانية الحذف
  // والتعديل — تغيير تصميم بس». فزال ازدواج (جدول مكتبي + بطاقات هاتف)
  // إلى **جدول واحد** بنسختين كالحركات حرفياً: صفّ رؤوس بخطّ الرؤوس
  // نفسه، وفواصل بين الصفوف، وشارة دفعٍ ملوّنة، وأرقام بخطٍّ جدوليّ،
  // وتذييل مجموعٍ أخضر. المنطق (الفلاتر/التعديل/الحذف/الطباعة) لم يُمس.

  static TextStyle _head() => TextStyle(
      fontSize: 11, fontWeight: FontWeight.w800, color: BrandColors.mut2);

  /// عرض أعمدة الحركات نفسها: التاريخ/الدفع/القيمة ثابتة والاسم يتمدد.
  double get _wDate => widget.dense ? 74 : 92;
  // م190 — نِسَب الأعمدة (رأساً وصفّاً): الاسم أعرضها، ثم الهاتف والعيادة
  // متساويان، ثم الدفع والقيمة. مصدرٌ واحد ⇒ تناظرٌ حتمي بلا حسابات يدوية.
  int get _fName => 3;
  int get _fPhone => widget.dense ? 3 : 2;
  int get _fClinic => 2;
  int get _fPay => 2;
  int get _fVal => 2;
  double get _wAct => widget.dense ? 34 : 34;

  Widget _movesTable(
      List<_JMap> rows, String cur, String Function(Object?) n) {
    // م168 — التعديل/الحذف بالتفعيل وحده: بعد الإيقاف عرضٌ تاريخي فقط.
    final triOn = triAnalysesEnabled(ref.read(appConfigProvider));
    final canEdit = triOn && staffAllowed('records.edit');
    final canDel = triOn && staffAllowed('records.delete');
    final det = staffAllowed('treasury.details');
    final fs = widget.dense ? 11.5 : 12.5;
    final gap = widget.dense ? 8.0 : 10.0;
    // م189 — مصدر أرقام عمود الهاتف: صفوف السجلات بمعرّفاتها (للوراثة عن
    // الزيارة الأصل) + الحلّال الموروث احتياطاً. يُبنى مرة واحدة للجدول.
    final repos = ref.read(reposProvider);
    final allRecs = repos.records.getAll().cast<Map<String, Object?>>();
    final byId = {for (final r in allRecs) '${r['id']}': r};
    final allPros = repos.prosthetics.getAll().cast<Map<String, Object?>>();
    final allDebts = repos.debts.getAll().cast<Map<String, Object?>>();
    final idIdx = IdentityIndex(allRecs, allPros, allDebts);
    // م190 — قانوني ⇒ خام: ليُعرض الرقم بصفر البدء كما كتبه المالك.
    final rawByCanon = <String, String>{};
    for (final row in [...allRecs, ...allPros, ...allDebts]) {
      final d = '${row['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.isEmpty) continue;
      rawByCanon.putIfAbsent(normPhone(d), () => d);
    }
    num visibleSum = 0;
    for (final r in rows) {
      visibleSum += jsNumOr0(r['amount']);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── رأس الجدول (هوية الحركات: فواصل واضحة وتوسيط الدفع والقيمة) ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          if (widget.showIndex)
            SizedBox(
                width: 26,
                child:
                    Text('#', style: _head(), textAlign: TextAlign.center)),
          if (widget.showDate)
            SizedBox(width: _wDate, child: Text('التاريخ', style: _head())),
          SizedBox(width: gap),
          // م190 — شبكة نسبٍ واحدة للرأس وللصفوف (بلاغ المالك: «لا يوجد
          // تناظر بحجم الأعمدة»): كانت الأسماء والعيادات تتمدد بينما
          // الهاتف والدفع والقيمة بعروضٍ ثابتة صغيرة، فيتكدّس نصف الجدول
          // يميناً ويبقى يسارُه فارغاً. النِّسَب أدناه مصدرٌ واحد للاثنين.
          Expanded(
              flex: _fName,
              child: Text('الاسم',
                  style: _head(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          SizedBox(width: gap),
          // م189 — عمود رقم الهاتف بعد الاسم: يميّز المريض عن سميّه.
          Expanded(
              flex: _fPhone,
              child: Text('الهاتف',
                  style: _head(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          SizedBox(width: gap),
          Expanded(
              flex: _fClinic,
              child: Text('العيادة',
                  style: _head(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          SizedBox(width: gap),
          Expanded(
              flex: _fPay,
              child: Text('الدفع',
                  style: _head(), textAlign: TextAlign.center)),
          SizedBox(width: gap),
          Expanded(
              flex: _fVal,
              child: Text('القيمة',
                  style: _head(), textAlign: TextAlign.center)),
          if (canEdit || canDel) SizedBox(width: _wAct),
        ]),
      ),
      Divider(height: 1, color: BrandColors.line),
      for (var i = 0; i < rows.length; i++) ...[
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: 8, vertical: widget.dense ? 5 : 6),
          child: Row(children: [
            if (widget.showIndex)
              SizedBox(
                  width: 26,
                  child: Text('${i + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: fs - 1.5,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.mut2))),
            if (widget.showDate)
              SizedBox(
                width: _wDate,
                child: Text('${rows[i]['date'] ?? ''}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: fs - 1,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.ink,
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ])),
              ),
            SizedBox(width: gap),
            // م190 — الاسم مفتاحُ ملف المريض (طلب المالك): يفتح ملفه
            // **بهويته الموروثة** عن زيارته — فيفتح ملف صاحبه لا سميّه.
            Expanded(
              flex: _fName,
              child: InkWell(
                key: Key('anal-reg-open-${rows[i]['id']}'),
                onTap: () => _openPatient(rows[i], idIdx),
                child: Text(
                    '${rows[i]['name'] ?? rows[i]['patient_name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: fs,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.brand900,
                        decoration: TextDecoration.underline,
                        decorationColor:
                            BrandColors.brand600.withValues(alpha: .35))),
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              flex: _fPhone,
              child: Text(_rowPhoneText(rows[i], byId, idIdx, rawByCanon),
                  key: Key('anal-reg-phone-${rows[i]['id']}'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: fs - 1,
                      fontWeight: FontWeight.w700,
                      color: BrandColors.mut,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            SizedBox(width: gap),
            Expanded(
              flex: _fClinic,
              child: Text(_rowClinic(rows[i]),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: fs - .5,
                      fontWeight: FontWeight.w700,
                      color: BrandColors.strong)),
            ),
            SizedBox(width: gap),
            Expanded(
                flex: _fPay, child: Center(child: _payChip(rows[i]))),
            SizedBox(width: gap),
            Expanded(
              flex: _fVal,
              child: Text(n(jsNumOr0(rows[i]['amount'])),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: fs,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.green,
                      fontFeatures: const [
                        FontFeature.tabularFigures()
                      ])),
            ),
            // م187 — التعديل والحذف في قائمةٍ واحدة مضغوطة: تبقى القدرتان
            // كما هما (نفس مفاتيح م145) بلا أن يتكسّر إيقاع أعمدة الحركات.
            if (canEdit || canDel)
              SizedBox(
                width: _wAct,
                child: PopupMenuButton<String>(
                  key: Key('anal-reg-menu-${rows[i]['id']}'),
                  tooltip: 'خيارات',
                  padding: EdgeInsets.zero,
                  itemBuilder: (_) => [
                    if (canEdit)
                      PopupMenuItem(
                        key: Key('anal-reg-edit-${rows[i]['id']}'),
                        value: 'edit',
                        child: const Text('تعديل',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    if (canDel)
                      PopupMenuItem(
                        key: Key('anal-reg-del-${rows[i]['id']}'),
                        value: 'del',
                        child: Text('حذف',
                            style: TextStyle(
                                fontSize: 12.5, color: BrandColors.red)),
                      ),
                  ],
                  onSelected: (v) =>
                      v == 'edit' ? _edit(rows[i]) : _delete(rows[i]),
                  child: Icon(Icons.more_vert_rounded,
                      size: 16, color: BrandColors.mut2),
                ),
              ),
          ]),
        ),
        Divider(height: 1, color: BrandColors.line),
      ],
      // م155 — صف الإجمالي ختاماً داخل الجدول (مواصفة المالك) — بهوية
      // تذييل الحركات: كبسولة خضراء ورقمٌ جدوليّ.
      if (widget.inlineTotal)
        Container(
          key: const Key('anal-reg-inline-total'),
          margin: const EdgeInsets.only(top: 6),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(46, 125, 90, .08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: const Color.fromRGBO(46, 125, 90, .25)),
          ),
          child: Row(children: [
            // م190 — التذييل بنفس نِسَب الجدول: المجموع يقع تحت عمود
            // «القيمة» بالضبط (كان بعرضٍ ثابتٍ فينزاح عنه).
            Expanded(
              flex: _fName + _fPhone + _fClinic + _fPay,
              child: Text('المجموع (${rows.length} بند)',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.strong)),
            ),
            SizedBox(width: gap * 4),
            Expanded(
              flex: _fVal,
              child: Text(det ? n(visibleSum) : '—',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.green,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
            if (canEdit || canDel) SizedBox(width: _wAct),
          ]),
        ),
    ]);
  }

  /// شارة الطريقة — أخضر للكاش وذهبيٌّ داكن للتحويل (اصطلاح جدول اليوم).
  Widget _payChip(_JMap r) {
    final isCash = r['payment'] == 'كاش';
    final color = isCash ? BrandColors.green : const Color(0xFF8A6D1B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('${r['payment'] ?? ''}',
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
    );
  }

  // ── تعديل/حذف بند (قدرات م145 منقولة حرفياً بمفاتيح anal-reg-*) ──────────

  Future<void> _edit(_JMap r) async {
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
              key: const Key('anal-reg-edit-price'),
              controller: priceCtl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'القيمة', isDense: true),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              key: const Key('anal-reg-edit-pay'),
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
                key: const Key('anal-reg-edit-save'),
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('حفظ')),
          ],
        ),
      ),
    );
    final price = jsNumOr0(priceCtl.text);
    priceCtl.dispose();
    if (ok != true || price <= 0) return;
    ref.read(reposProvider).records.updateLocal(id, {
      'amount': price,
      'payment': pay,
    });
    ref.read(financeRevProvider.notifier).state++;
    if (mounted) setState(() {});
  }

  Future<void> _delete(_JMap r) async {
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
              key: const Key('anal-reg-del-confirm'),
              style: FilledButton.styleFrom(backgroundColor: BrandColors.red),
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

  // ── الطباعة — جدولٌ بسيط بأعمدة البطاقة نفسها + إجمالي الشهر ─────────────

  Future<void> _print(List<_JMap> rows, String cur) async {
    final fonts = await loadPdfBrand(ref);
    final n = formatNumber;
    final repos = ref.read(reposProvider);
    final allRecs = repos.records.getAll().cast<Map<String, Object?>>();
    final byId = {for (final r in allRecs) '${r['id']}': r};
    final allPros = repos.prosthetics.getAll().cast<Map<String, Object?>>();
    final allDebts = repos.debts.getAll().cast<Map<String, Object?>>();
    final idIdx = IdentityIndex(allRecs, allPros, allDebts);
    final rawByCanon = <String, String>{};
    for (final row in [...allRecs, ...allPros, ...allDebts]) {
      final d = '${row['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.isEmpty) continue;
      rawByCanon.putIfAbsent(normPhone(d), () => d);
    }
    num sum = 0;
    final tableRows = <List<String>>[];
    for (final r in rows) {
      final amt = jsNumOr0(r['amount']);
      sum += amt;
      tableRows.add([
        '${r['date'] ?? ''}',
        '${r['name'] ?? r['patient_name'] ?? ''}',
        // م189 — الهاتف في الطباعة أيضاً (توأم عمود الشاشة).
        _rowPhoneText(r, byId, idIdx, rawByCanon),
        _rowClinic(r),
        '${r['payment'] ?? ''}',
        '${n(amt)} $cur',
      ]);
    }
    final today = getCurrentDate();
    final bytes = await simpleTablePdf(
      fonts,
      title: 'سجلات $kTriAnalysesName',
      subtitle: today.length >= 7 ? today.substring(0, 7) : today,
      headers: const [
        'التاريخ',
        'اسم المريض',
        'الهاتف',
        'العيادة',
        'الطريقة',
        'السعر'
      ],
      rows: tableRows,
      totRow: ['إجمالي الشهر الحالي', '', '', '', '', '${n(sum)} $cur'],
    );
    final msg = await printOrSharePdf(
        ref.read(dbDirProvider), bytes, 'analyses_registry.pdf');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
