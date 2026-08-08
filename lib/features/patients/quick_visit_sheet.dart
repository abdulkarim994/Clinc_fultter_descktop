/// نافذة «الزيارة السريعة» (م58) — اقتراح المالك: دائرة عائمة خاصة بكل
/// مريض تفتح ورقة سفلية مختزلة بدل التحويل للشاشة الرئيسية.
///
/// المحتوى: المعالجة (سعرها يُملأ تلقائياً من الإعدادات — سلوك م55
/// نفسه ويبقى حراً للتعديل)، القيمة، التاريخ (اليوم افتراضاً)، طريقة
/// الدفع، ومفتاح «دين» مضغوط يُظهر الدفعة الأولى. المحذوف عمداً: الاسم
/// والهاتف والمعلومات الطبية والأسنان والمخبر — تُثبَّت هوية المريض
/// وعيادته من السياق، ورابط «الخيارات الكاملة» يفتح مسار الرئيسية
/// القديم (المسودة + القفزة) للحالات الأوسع (متابعة/ملاحظات/أسنان).
/// م59 — التركيبات مدعومة داخل النافذة بقسم مضغوط: النوع يملأ سعر
/// الوحدة، وقيمة المخبر تُحسب تلقائياً (وحدات × سعر) وتبقى حرة.
///
/// الحفظ بمسار saveNewRecord الموحد نفسه — فتعمل تلقائياً: خصم مرحلة
/// خطة العلاج، إنشاء الدين وقيود الخزينة، ولقطة النسب، والمزامنة
/// الفورية (upsertLocal يختم dirty ويركل المحرك).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../desktop/desktop_gate.dart' show isDesktopUi;
import '../desktop/widgets/desktop_dialogs.dart' show showDesktopDialog;
import '../finance/finance_screen.dart' show financeRevProvider;
import '../records/add_record_screen.dart'
    show labTypesList, labsList, teethCount;
import '../records/day_close_store.dart' show confirmClosedDayWrite;
import '../records/income_day_dialog.dart' show askIncomeDay;
import '../records/mini_calculator.dart' show showMiniCalculator;
import '../records/record_saver.dart'
    show SaveRecordInput, isProsthetic, saveNewRecord, triAnalysisFor;
import '../records/tooth_report_dialog.dart' show showToothReportDialog;
import '../settings/analyses3.dart' show triAnalysesEnabled;
import 'patients_tab.dart' show patientsRevProvider;
import '../staff/staff_gate.dart' show gateStaff;

/// يفتح ورقة الزيارة السريعة لمريض معلوم الهوية والعيادة.
/// [onFullOptions] — مسار «الخيارات الكاملة»: يُستدعى بعد إغلاق الورقة
/// (المسودة + القفزة للرئيسية كما كان).
Future<void> showQuickVisitSheet(
  BuildContext context, {
  required String name,
  required String clinic,
  String phone = '',
  required VoidCallback onFullOptions,
}) {
  // نسخة الكمبيوتر: نفس ورقة الزيارة السريعة داخل حوار مركزي بدل
  // الورقة السفلية — مسار الهاتف أدناه لا يتغير بحرف.
  if (isDesktopUi(context)) {
    return showDesktopDialog<void>(
      context,
      title: 'زيارة سريعة — $name',
      width: 520,
      builder: (_) => SingleChildScrollView(
        child: _QuickVisitSheet(
          name: name,
          clinic: clinic,
          phone: phone,
          onFullOptions: onFullOptions,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      // رفع الورقة فوق لوحة المفاتيح.
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _QuickVisitSheet(
        name: name,
        clinic: clinic,
        phone: phone,
        onFullOptions: onFullOptions,
      ),
    ),
  );
}

class _QuickVisitSheet extends ConsumerStatefulWidget {
  const _QuickVisitSheet({
    required this.name,
    required this.clinic,
    required this.phone,
    required this.onFullOptions,
  });

  final String name;
  final String clinic;
  final String phone;
  final VoidCallback onFullOptions;

  @override
  ConsumerState<_QuickVisitSheet> createState() =>
      _QuickVisitSheetState();
}

class _QuickVisitSheetState extends ConsumerState<_QuickVisitSheet> {
  String service = '';
  String payment = '';
  String date = getCurrentDate();
  bool isDebt = false;
  final amountCtl = TextEditingController();
  final firstPayCtl = TextEditingController();

  // ── نظام «التحاليل الثلاثية» — تحليلٌ واحدٌ ثابتُ الاسم والسعر (معزول مالياً) ──
  bool hasAnalysis = false;
  String analysisPay = 'كاش';

  // معلومات مختصرة (قرار المالك): ملاحظة تلتصق بصف هذه الزيارة/الدفعة
  // حصراً (record.notes) — معزولة عن أي مريض أو عيادة أخرى بنيوياً.
  final quickNoteCtl = TextEditingController();

  // م59 — التركيبات داخل النافذة (كانت محوّلة للخيارات الكاملة):
  // النوع يملأ سعر الوحدة، وقيمة المخبر = وحدات × سعر (توأم
  // onProsTypeChange/onUnitsOrPriceChange في الرئيسية حرفياً).
  String prosType = '';
  String labName = '';
  final prosUnitsCtl = TextEditingController(text: '1');
  final prosUnitPriceCtl = TextEditingController();
  final labValueCtl = TextEditingController();

  // م60 — تحديد الأسنان: يفتح محدد الأسنان الموجود ويحفظ في report.
  List<Map<String, Object?>> reportEntries = [];
  Map<String, Object?> reportMeta = {};

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(appConfigProvider);
    final payments = _list(cfg, 'payments');
    if (payments.isNotEmpty) payment = payments.first;
  }

  @override
  void dispose() {
    amountCtl.dispose();
    firstPayCtl.dispose();
    quickNoteCtl.dispose();
    prosUnitsCtl.dispose();
    prosUnitPriceCtl.dispose();
    labValueCtl.dispose();
    super.dispose();
  }

  /// قيمة المخبر = وحدات × سعر الوحدة (وحدات 0 تُعامل 1 — سلوك الأصل).
  void _recomputeLabValue() {
    final units = jsNumOr0(prosUnitsCtl.text);
    final price = jsNumOr0(prosUnitPriceCtl.text);
    labValueCtl.text =
        ((units == 0 ? 1 : units) * price).toStringAsFixed(0);
    setState(() {});
  }

  /// م60 — فتح محدّد الأسنان الموجود (وضع teethOnly) وحفظ نتيجته.
  Future<void> _openTeeth() async {
    final result = await showToothReportDialog(
      context,
      entries: reportEntries,
      meta: reportMeta,
      teethOnly: true,
      patientName: widget.name,
      patientPhone: widget.phone,
      notation: ref.read(notationSystemProvider),
    );
    if (!mounted) return;
    setState(() {
      if (result == null) {
        reportEntries = [];
        reportMeta = {};
      } else {
        reportEntries = result.entries;
        reportMeta = result.meta;
      }
    });
  }

  /// م60 — آلة حاسبة صغيرة: الناتج يُدرج في حقل القيمة (د.ل).
  Future<void> _openCalculator() async {
    final result = await showMiniCalculator(context);
    if (result != null && mounted) {
      setState(() => amountCtl.text = result == result.roundToDouble()
          ? result.toStringAsFixed(0)
          : '$result');
    }
  }

  List<String> _list(Map<String, Object?> cfg, String key) =>
      cfg[key] is List
          ? [for (final e in cfg[key] as List) '$e']
          : const [];

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1600)));

  Future<void> _save() async {
    // م127 — بوابة دفاعية مركزية (كل المنادين محكومون أصلاً).
    if (!gateStaff(context, 'records.add')) return;
    final amount = jsNumOr0(amountCtl.text);
    if (service.isEmpty) {
      _snack('اختر المعالجة');
      return;
    }
    if (amount <= 0) {
      _snack('أدخل قيمة الزيارة');
      return;
    }
    final firstPay = jsNumOr0(firstPayCtl.text);
    if (isDebt && firstPay > amount) {
      _snack('الدفعة الأولى أكبر من القيمة');
      return;
    }
    // م101 — تاريخ غير اليوم: أين يُحسب الإيراد؟ (الإلغاء = لا حفظ).
    final incomeDay = await askIncomeDay(context, date);
    if (incomeDay == null || !mounted) return;
    // م104 — يوم الاحتساب مقفول؟ تنبيه ومتابعة بالتأكيد فقط.
    if (!await confirmClosedDayWrite(
        context, ref.read(reposProvider).settings, incomeDay)) {
      return;
    }
    if (!mounted) return;
    final ip = isProsthetic(service);
    try {
      final repos = ref.read(reposProvider);
      final cfg = ref.read(appConfigProvider);
      saveNewRecord(
        repos,
        cfg,
        SaveRecordInput(
          name: widget.name,
          date: date,
          incomeDate: incomeDay,
          amount: amount.toDouble(),
          clinic: widget.clinic,
          service: service,
          payment: payment,
          isDebt: isDebt,
          firstPay: isDebt ? firstPay.toDouble() : 0,
          phone: widget.phone,
          // معلومات مختصرة — تُحفظ على صف السجل (وتظهر بعمود المكتب).
          notes: quickNoteCtl.text.trim(),
          // م59 — حقول التركيبة (فرع ip الحرفي في saveNewRecord).
          labValue: ip ? jsNumOr0(labValueCtl.text) : 0,
          prosType: ip ? prosType : '',
          prosUnits: ip
              ? (jsNumOr0(prosUnitsCtl.text) == 0
                  ? 1
                  : jsNumOr0(prosUnitsCtl.text).toInt())
              : 1,
          prosUnitPrice: ip ? jsNumOr0(prosUnitPriceCtl.text) : 0,
          labName: ip ? labName : '',
          // م60 — تقرير الأسنان (نفس شكل add_record).
          report: reportEntries.isNotEmpty
              ? {'entries': reportEntries, 'meta': reportMeta}
              : null,
          // نظام «التحاليل الثلاثية» — الورقة السريعة إنشاءٌ صرف دائماً.
          analysis: triAnalysisFor(
            creating: true,
            checked: hasAnalysis,
            cfg: cfg,
            payment: analysisPay,
          ),
        ),
      );
    } catch (e) {
      _snack(e is ArgumentError ? '${e.message}' : 'تعذّر الحفظ');
      return;
    }
    // نبضات الإسقاط: الملف والقوائم والمالية تتحدث فوراً.
    ref.read(patientsRevProvider.notifier).state++;
    ref.read(financeRevProvider.notifier).state++;
    Navigator.of(context).pop();
    _snack(isDebt ? 'أُضيفت الزيارة وسُجل الدين' : 'تمت إضافة الزيارة');
  }

  /// حقل التاريخ (منتقٍ) — مشترك بين التخطيطات.
  Widget _dateField() => InkWell(
        key: const Key('qv-date'),
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.parse(date),
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (picked != null) {
            setState(() => date =
                '${picked.year.toString().padLeft(4, '0')}-'
                '${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}');
          }
        },
        child: InputDecorator(
          decoration:
              const InputDecoration(labelText: 'التاريخ', isDense: true),
          child: Row(children: [
            Icon(Icons.event_rounded,
                size: 14, color: BrandColors.brandIcon),
            const SizedBox(width: 6),
            Flexible(
              child: Text(date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      );

  /// طريقة الدفع كقائمة منسدلة (تتسع لصف مشترك مع القيمة).
  Widget _payDropdown(List<String> payments) =>
      DropdownButtonFormField<String>(
        key: const Key('qv-pay'),
        isExpanded: true,
        initialValue:
            payments.contains(payment) ? payment : null,
        decoration:
            const InputDecoration(labelText: 'طريقة الدفع', isDense: true),
        items: [
          for (final p in payments)
            DropdownMenuItem(
                value: p,
                child: Text(p, style: const TextStyle(fontSize: 12.5))),
        ],
        onChanged: (v) => setState(() => payment = v ?? ''),
      );

  /// زر تحديد الأسنان — يعرض العدد المحدد ويفتح المحدّد (م60).
  Widget _teethButton() {
    final count = teethCount(reportEntries);
    return InkWell(
      key: const Key('qv-teeth'),
      borderRadius: BorderRadius.circular(12),
      onTap: _openTeeth,
      child: InputDecorator(
        decoration:
            const InputDecoration(labelText: 'تحديد الأسنان', isDense: true),
        child: Row(children: [
          Icon(Icons.grid_view_rounded,
              size: 14, color: BrandColors.brandIcon),
          const SizedBox(width: 6),
          Text(count > 0 ? '$count سن' : 'اختيار',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight:
                      count > 0 ? FontWeight.w700 : FontWeight.w400,
                  color: count > 0
                      ? BrandColors.brandText
                      : BrandColors.mut2)),
        ]),
      ),
    );
  }

  /// نظام «التحاليل الثلاثية» — منطقة مبسّطة: قائمة طريقة الدفع فقط.
  /// الاسم والسعر ثابتان من الإعدادات — لا قائمة أسماء ولا حقل سعر.
  Widget _analysisSection() {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: BrandColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.green.withValues(alpha: .35)),
      ),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        key: const Key('qv-analysis-pay'),
        initialValue: analysisPay,
        decoration: const InputDecoration(
            labelText: 'طريقة دفع التحاليل الثلاثية', isDense: true),
        items: const [
          DropdownMenuItem(value: 'كاش', child: Text('كاش')),
          DropdownMenuItem(value: 'تحويل', child: Text('تحويل')),
        ],
        onChanged: (v) => setState(() => analysisPay = v ?? 'كاش'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(appConfigProvider);
    // م59 — كل المعالجات بما فيها التركيبات (قسمها المضغوط أدناه).
    final services = _list(cfg, 'services');
    final payments = _list(cfg, 'payments');
    final cur = '${jsOr(cfg['currency'], 'د.ل')}';
    final prices = cfg['servicePrices'];
    final labTypes = labTypesList(cfg);
    final labs = labsList(cfg);
    final showPros = isProsthetic(service);

    // Material جذراً (لا Container): ListTile يرسم حبره على أقرب
    // Material — صندوق ملون بينهما يخفيه ويرمي تأكيداً في الاختبارات.
    return Material(
      color: BrandColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(22)),
        side: const BorderSide(color: Color.fromRGBO(201, 162, 75, .25)),
      ),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // مقبض الورقة.
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: BrandColors.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            // العنوان: هوية المريض تُعرض ولا تُحرر — والحاسبة في الزاوية
            // اليسرى (م60).
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'زيارة جديدة — ${widget.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.brandText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(widget.clinic,
                        style: TextStyle(
                            fontSize: 10.5, color: BrandColors.mut2)),
                  ],
                ),
              ),
              // أيقونة الآلة الحاسبة (الزاوية اليسرى).
              Material(
                color: const Color.fromRGBO(201, 162, 75, .1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(
                      color: Color.fromRGBO(201, 162, 75, .3)),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('qv-calc'),
                  onTap: _openCalculator,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.calculate_rounded,
                        size: 20, color: BrandColors.goldDark),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),

            // ── صف 1: المعالجة | التاريخ ──
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('qv-service'),
                  isExpanded: true,
                  initialValue: service.isEmpty ? null : service,
                  decoration: const InputDecoration(
                    labelText: 'المعالجة',
                    isDense: true,
                  ),
                  items: [
                    for (final s in services)
                      DropdownMenuItem(
                          value: s,
                          child: Text(s,
                              style: const TextStyle(fontSize: 12.5))),
                  ],
                  onChanged: (v) => setState(() {
                    service = v ?? '';
                    final p0 = prices is Map ? prices[service] : null;
                    if (jsNumOr0(p0) > 0) {
                      amountCtl.text = jsNumOr0(p0).toStringAsFixed(0);
                    }
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _dateField()),
            ]),
            const SizedBox(height: 10),

            // ── م59: قسم التركيبة (صفان يظهران لمعالجات التركيبات) ──
            if (showPros) ...[
              // صف 2: المخبر | نوع التركيبة
              Row(children: [
                Expanded(
                  child: labs.isEmpty
                      ? const SizedBox.shrink()
                      : DropdownButtonFormField<String>(
                          key: const Key('qv-lab'),
                          isExpanded: true,
                          initialValue:
                              labName.isEmpty ? null : labName,
                          decoration: const InputDecoration(
                            labelText: 'المخبر (اختياري)',
                            isDense: true,
                          ),
                          items: [
                            for (final l in labs)
                              DropdownMenuItem(
                                  value: l,
                                  child: Text(l,
                                      style: const TextStyle(
                                          fontSize: 12.5))),
                          ],
                          onChanged: (v) =>
                              setState(() => labName = v ?? ''),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: const Key('qv-prostype'),
                    isExpanded: true,
                    initialValue: prosType.isEmpty ? null : prosType,
                    decoration: const InputDecoration(
                      labelText: 'نوع التركيبة',
                      isDense: true,
                    ),
                    items: [
                      for (final t in labTypes)
                        DropdownMenuItem(
                            value: '${t['name']}',
                            child: Text('${t['name']}',
                                style: const TextStyle(fontSize: 12.5))),
                    ],
                    onChanged: (v) {
                      prosType = v ?? '';
                      for (final t in labTypes) {
                        if ('${t['name']}' == prosType &&
                            jsTruthy(t['defaultPrice'])) {
                          prosUnitPriceCtl.text = jsNumOr0(t['defaultPrice'])
                              .toStringAsFixed(0);
                          break;
                        }
                      }
                      _recomputeLabValue();
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              // صف 3 (م61): **العدد** أولاً ثم السعر ثم إجمالي المخبر.
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('qv-units'),
                    controller: prosUnitsCtl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                        labelText: 'العدد', isDense: true),
                    onChanged: (_) => _recomputeLabValue(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('qv-unitprice'),
                    controller: prosUnitPriceCtl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                        labelText: 'السعر', isDense: true),
                    onChanged: (_) => _recomputeLabValue(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('qv-labvalue'),
                    controller: labValueCtl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                        labelText: 'إجمالي المخبر', isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
            ],

            // ── صف 4: القيمة (د.ل) | طريقة الدفع ──
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  key: const Key('qv-amount'),
                  controller: amountCtl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: 'القيمة ($cur)',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: payments.isEmpty
                    ? const SizedBox.shrink()
                    : _payDropdown(payments),
              ),
            ]),
            const SizedBox(height: 10),

            // ── صف 5 (م61): تحديد الأسنان | تسجيل كدين — بمستوى واحد:
            // ارتفاع جوهري موحد + مفتاح مقيد الارتفاع (كان المفتاح ينفخ
            // حقله فيهبط عن مستوى حقل الأسنان).
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _teethButton()),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      key: const Key('qv-debt'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => isDebt = !isDebt),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                            labelText: 'تسجيل كدين', isDense: true),
                        child: Row(children: [
                          Text(isDebt ? 'نعم' : 'لا',
                              style: const TextStyle(fontSize: 12.5)),
                          const Spacer(),
                          // م63 — المفتاح بحجمه الكامل **بلا نفخ للحقل**:
                          // صندوق بارتفاع نصّي (20) يحتضن OverflowBox
                          // فيُرسم المفتاح كاملاً ممركزاً متجاوزاً السطر
                          // بتناظر — وارتفاعا الحقلين يتطابقان فيتوازى
                          // الخطان السفليان.
                          SizedBox(
                            height: 20,
                            width: 52,
                            child: OverflowBox(
                              maxHeight: 48,
                              maxWidth: 60,
                              alignment: Alignment.center,
                              child: Switch(
                                value: isDebt,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                activeThumbColor: BrandColors.gold,
                                onChanged: (v) =>
                                    setState(() => isDebt = v),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // الدفعة الأولى تظهر أسفل صف الدين عند تفعيله.
            if (isDebt) ...[
              const SizedBox(height: 10),
              TextField(
                key: const Key('qv-firstpay'),
                controller: firstPayCtl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                  labelText: 'الدفعة الأولى',
                  isDense: true,
                ),
              ),
            ],
            const SizedBox(height: 10),

            // ── نظام «التحاليل الثلاثية» — يظهر الصح فقط حين الميزة مفعّلة ──
            if (triAnalysesEnabled(cfg)) ...[
              Row(children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    key: const Key('qv-analysis-toggle'),
                    value: hasAnalysis,
                    activeColor: BrandColors.green,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() {
                      hasAnalysis = v ?? false;
                      if (hasAnalysis) {
                        analysisPay =
                            (payment == 'كاش' || payment == 'تحويل')
                                ? payment
                                : 'كاش';
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 6),
                Text('التحاليل الثلاثية',
                    style: TextStyle(fontSize: 12.5, color: BrandColors.mut)),
              ]),
              if (hasAnalysis) ...[
                const SizedBox(height: 8),
                _analysisSection(),
              ],
            ],
            const SizedBox(height: 10),

            // ── معلومات مختصرة (اختياري) ──
            TextField(
              key: const Key('qv-note'),
              controller: quickNoteCtl,
              maxLines: 2,
              minLines: 1,
              style: const TextStyle(fontSize: 12.5),
              decoration: const InputDecoration(
                labelText: 'معلومات مختصرة (اختياري)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            // ── الحفظ + الخيارات الكاملة ──
            FilledButton.icon(
              key: const Key('qv-save'),
              style: FilledButton.styleFrom(
                backgroundColor: BrandColors.brand600,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26)),
              ),
              onPressed: _save,
              icon: const Icon(Icons.check_rounded, size: 19),
              label: const Text('حفظ الزيارة',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              key: const Key('qv-full-options'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onFullOptions();
              },
              icon: Icon(Icons.tune_rounded,
                  size: 15, color: BrandColors.goldDark),
              label: Text(
                'الخيارات الكاملة (متابعة/ملاحظات/أسنان...)',
                style: TextStyle(
                    fontSize: 11.5, color: BrandColors.goldDark),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
