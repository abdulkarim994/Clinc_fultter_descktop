/// شاشة الإضافة (تبويب الرئيسية) — نسخة 1:1 من AddRecord.vue:
/// شريط ملخص اليوم (مريض/دخل/دين بالمنطق المالي الحرفي) بنقرات تفتح
/// لوحات تفصيل حسب العيادة، ثم بطاقة «إدخال جديد» بترتيب الأصل: زر اليوم،
/// التاريخ+العيادة، الهاتف أولاً (+رقم ثانٍ) والاسم مع لوحة اقتراحات
/// المرضى (عزل عيادة صارم + ربط صريح يملأ الهاتفين)، المعالجة+الدفع
/// (سعر المعالجة يملأ القيمة)، القيمة+خيارات (دين + موعد متابعة)، قسم
/// التركيبات بمعاينته المالية الحية (صافي/طبيب/عيادة بلقطة النسبة الحية)،
/// صف تبديلَي تحديد الأسنان والمعلومات الطبية، قسم الدين (دفعة أولى
/// بحدّ القيمة + ملاحظات)، وزر الحفظ الذهبي — والحفظ عبر saveNewRecord
/// المنقول حرفياً (لقطات النِّسَب المجمدة واشتقاق الدين).
library;

import 'package:flutter/material.dart';

import '../desktop/desktop_gate.dart' show isDesktopUi;
import '../desktop/widgets/add_record_dock.dart'
    show addRecordDockProvider, AddRecordDockRequest;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/error_log.dart' show recordError;
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../../data/rates/rate_snapshot.dart';
import '../patients/patients_logic.dart' show distinctIdentityPhones;
import '../patients/patients_tab.dart'
    show addVisitDraftProvider, patientsRevProvider;
import '../print/treatment_tables.dart' show formatNumber;
import '../../data/audit/audit_trail.dart' show recordAudit;
import '../finance/finance_screen.dart' show financeRevProvider;
import '../patients/clinic_scope.dart'
    show medicalScopedRead, medicalScopedWrite;
import '../patients/profile_actions.dart' show deleteEntryCascade;
import 'day_close_store.dart' show confirmClosedDayWrite;
import 'default_treatment.dart';
import 'home_logic.dart' hide JMap;
import 'income_day_dialog.dart' show askIncomeDay;
import 'medical_info_dialog.dart';
import 'mini_calculator.dart' show showMiniCalculator;
import 'record_saver.dart';
import 'tooth_report_dialog.dart' show showToothReportDialog, teethKeysOf;
import '../settings/analyses3.dart' show triAnalysesEnabled, triAnalysesPrice;
import 'analysis_actions.dart' show showTriRepeatBlockedDialog, triRepeatCheck;
import '../staff/staff_gate.dart' show gateStaff;

/// config.labs — كما في labsList computed.
List<String> labsList(JMap config) => config['labs'] is List
    ? [for (final l in config['labs'] as List) '$l']
    : const [];

/// config.labTypes — عناصر {name, defaultPrice}.
List<JMap> labTypesList(JMap config) => config['labTypes'] is List
    ? [
        for (final t in config['labTypes'] as List)
          if (t is Map) Map<String, Object?>.from(t),
      ]
    : const [];

/// م162 — أنواع تركيبات مختبرٍ بعينه: من config.labTypesByLab[lab]
/// (لكل مختبر تركيباته وأسعاره — قرار المالك)، وإن لم تكن للمختبر
/// قائمة خاصة نعود للقائمة العامة القديمة تلقائياً (توافقٌ خلفي كامل:
/// لا جهاز ينكسر ولا بيانات تُفقد، والمزامنة عبر app.config كما هي).
List<JMap> labTypesFor(JMap config, String lab) {
  final byLab = config['labTypesByLab'];
  if (lab.isNotEmpty && byLab is Map) {
    final own = byLab[lab];
    if (own is List && own.isNotEmpty) {
      return [
        for (final t in own)
          if (t is Map) Map<String, Object?>.from(t),
      ];
    }
  }
  return labTypesList(config);
}

/// عدد الأسنان الفريدة في معالجات التقرير.
int teethCount(List<JMap> entries) => teethKeysOf(entries).length;

/// عرض التاريخ بأرقام هندية شرقية بصيغة السنة/الشهر/اليوم (توأم عرض
/// input[type=date] في الأصل) — التخزين يبقى ISO لاتينياً.
/// م167/ب — التاريخ بالأرقام اللاتينية (عرضاً فقط؛ التخزين YYYY-MM-DD).
String _enDate(String iso) => iso.replaceAll('-', '/');

/// يفتح نموذج الإدخال الكامل كورقة سفلية (بديل تبويب الرئيسية القديم بكل
/// خياراته). يُستدعى من زر «+» في الصدفة ومن مسارات «إضافة زيارة».
///
/// م94 — الهوية البصرية توأم ورقة «الزيارة السريعة» في بطاقة المريض
/// حرفياً (quick_visit_sheet): سطحٌ بزوايا 22 وإطار ذهبي شفاف، مقبض
/// 38×4، ترويسة عنوان/سطر فرعي + زر حاسبة ذهبي 40×40، تمريرة خارجية
/// واحدة تعانق المحتوى، وزر «حفظ الزيارة» الحبي داخل المحتوى — مع سقف
/// ارتفاعٍ 90٪ يمنع عودة قصّ ما قبل 92 (هذا النموذج أطول من نموذج
/// الزيارة السريعة).
Future<void> openAddRecordSheet(
  BuildContext context, {
  Map<String, Object?>? editEntry,
  String editKind = 'r',
  Map<String, Object?>? editDebt,
}) {
  // م119 — حارس دفاعي مركزي: الإضافة تتطلب صلاحيتها، والتعديل صلاحيته
  // (كل المسارات — الزر العائم، الزيارة السريعة، قوائم الصفوف — تمر هنا).
  if (!gateStaff(context, editEntry == null ? 'records.add' : 'records.edit')) {
    return Future.value();
  }
  // نسخة الكمبيوتر: بدل الدرج الجانبي الضيق، يُضبط لوح «زيارة جديدة»
  // المرسى في DesktopShell (يدفع مساحة العمل للأعلى بتخطيطٍ أفقي متعدد
  // الأعمدة) — لا حوارٌ ولا overlay. النموذج نفسه بكل حقوله ومنطقه حرفياً؛
  // الإغلاق يعيد المزود إلى null. مسار الهاتف أدناه لا يتغير بحرف.
  if (isDesktopUi(context)) {
    ProviderScope.containerOf(context, listen: false)
        .read(addRecordDockProvider.notifier)
        .state = AddRecordDockRequest(
      editEntry: editEntry,
      editKind: editKind,
      editDebt: editDebt,
    );
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final media = MediaQuery.of(sheetCtx);
      return Padding(
        // رفع الورقة فوق لوحة المفاتيح (توأم الزيارة السريعة).
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
          child: Material(
            color: BrandColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
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
                    // النموذج الكامل — ترويسته (العنوان + الحاسبة) داخله
                    // (م96): الحاسبة تُدار بحالة النموذج نفسها فتُدرج
                    // ناتجها في حقل القيمة مباشرة (توأم الزيارة السريعة).
                    AddRecordScreen(
                      compact: true,
                      editEntry: editEntry,
                      editKind: editKind,
                      editDebt: editDebt,
                      onSaved: () => Navigator.of(sheetCtx).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class AddRecordScreen extends ConsumerStatefulWidget {
  const AddRecordScreen({
    super.key,
    this.onSaved,
    this.scrollController,
    this.compact = false,
    this.horizontal = false,
    this.onExpandedContent,
    this.editEntry,
    this.editKind = 'r',
    this.editDebt,
  });

  /// يُستدعى بعد حفظٍ ناجح — تمرّره الورقة السفلية لإغلاقها؛ null = لا شيء.
  final VoidCallback? onSaved;

  /// وحدة تمرير خارجية (لورقة الإدخال السفلية القابلة للسحب).
  final ScrollController? scrollController;

  /// وضع مضغوط داخل الورقة: يُخفي شريط ملخص اليوم ويقلّل الحشوة.
  final bool compact;

  /// تخطيطٌ أفقي متعدد الأعمدة (لوح الكمبيوتر المرسى فقط): يوزّع مجموعات
  /// الحقول على أعمدةٍ بـ Row من Expanded بدل القائمة العمودية — كل الحقول
  /// والمفاتيح والمنطق والحفظ تبقى حرفياً، فقط توزيع build يختلف. الهاتف
  /// (false الافتراضي) لا يتأثر إطلاقاً.
  final bool horizontal;

  /// إشعارٌ بصري بحت (اللوح المرسى فقط): يُبلّغ الغلاف بأن للمحتوى أقساماً
  /// مفتوحة (دين/تركيبات) فيتوسّع تلقائياً. لا يمسّ أي حقل/منطق/حفظ.
  final void Function(bool needsRoom)? onExpandedContent;

  /// م100 — وضع التعديل: السجل/التركيبة الأصلية تُعبّأ في النموذج،
  /// والحفظ يستبدلها (إنشاء بالمدخلات الجديدة ثم حذفٌ متسلسل للأصل —
  /// بنفس مساري الحفظ والحذف المجرَّبين، لا مسار تعديل هشّ).
  final Map<String, Object?>? editEntry;

  /// نوع الأصل: r سجل، p تركيبة.
  final String editKind;

  /// دين الأصل المرتبط إن وُجد (لتعبئة طريقة الدفع والدفعة الأولى).
  final Map<String, Object?>? editDebt;

  @override
  ConsumerState<AddRecordScreen> createState() => _AddRecordScreenState();
}

class _AddRecordScreenState extends ConsumerState<AddRecordScreen> {
  @override
  void initState() {
    super.initState();
    // م100 — وضع التعديل: تعبئة النموذج من السجل الأصلي فوراً.
    final e = widget.editEntry;
    if (e != null) _prefillFromEntry(e, widget.editDebt);
    // مسودة «زيارة جديدة» من قائمة مرضى العيادة — توأم query
    // {patient, clinic}: اسم مربوط + هاتف + عيادة مسبقة.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final draft = ref.read(addVisitDraftProvider);
      if (draft == null || !mounted) return;
      ref.read(addVisitDraftProvider.notifier).state = null;
      setState(() {
        nameCtl.text = '${draft['name'] ?? ''}';
        selectedPatient = nameCtl.text.trim();
        if (jsTruthy(draft['phone'])) {
          phoneCtl.text = '${draft['phone']}';
        }
        if (jsTruthy(draft['clinic'])) {
          clinic = '${draft['clinic']}';
        }
      });
    });
  }

  /// م100 — رقم للنص (بلا كسور عبثية؛ الصفر = حقل فارغ).
  static String _numText(Object? v) {
    final n = jsNumOr0(v);
    if (n == 0) return '';
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : '$n';
  }

  /// م100 — تعبئة كل حقول النموذج من سجل/تركيبة قائمة (+دينها إن وُجد).
  void _prefillFromEntry(JMap e, JMap? d) {
    String s(Object? v) {
      final t = '${v ?? ''}';
      return t == 'null' ? '' : t;
    }

    nameCtl.text = s(jsOr(e['name'], e['patient_name']));
    selectedPatient = nameCtl.text.trim();
    phoneCtl.text = s(e['phone']);
    phone2Ctl.text = s(e['phone2']);
    showPhone2 = phone2Ctl.text.trim().isNotEmpty;
    if (s(e['date']).isNotEmpty) date = s(e['date']);
    clinic = s(e['clinic']);
    notesCtl.text = s(jsOr(e['notes'], d?['notes']));
    isDebt = e['payment'] == 'دين' || jsTruthy(e['isDebt']);
    // طريقة الدفع الحقيقية: للدين من صف الدين، وإلا من السجل نفسه.
    final pay = isDebt ? s(d?['payment']) : s(e['payment']);
    payment = pay == 'دين' ? '' : pay;
    if (widget.editKind == 'p') {
      service = s(e['service']).isNotEmpty ? s(e['service']) : 'تركيبات';
      amountCtl.text = _numText(jsOr(e['total'], e['amount']));
      labName = s(e['labName']);
      prosType = s(e['prosType']);
      final u = jsNumOr0(e['prosUnits']);
      prosUnitsCtl.text = (u == 0 ? 1 : u).toStringAsFixed(0);
      prosUnitPriceCtl.text = _numText(e['prosUnitPrice']);
      labValueCtl.text = _numText(e['labValue']);
    } else {
      service = s(e['service']);
      amountCtl.text = _numText(e['amount']);
    }
    if (isDebt) {
      firstPayCtl.text = _numText(jsOr(d?['paidAmount'], d?['paid_amount']));
    }
    // تقرير الأسنان (على السجل، وللدين نسخته على صف الدين — م103).
    final rep = jsOr(e['report'], d?['report']);
    if (rep is Map && rep['entries'] is List) {
      reportEntries = [
        for (final x in rep['entries'] as List)
          if (x is Map) Map<String, Object?>.from(x),
      ];
      reportMeta = rep['meta'] is Map
          ? Map<String, Object?>.from(rep['meta'] as Map)
          : <String, Object?>{};
      hasReport = reportEntries.isNotEmpty;
    }
  }

  final nameCtl = TextEditingController();
  final phoneCtl = TextEditingController();
  final phone2Ctl = TextEditingController();
  final amountCtl = TextEditingController();
  final firstPayCtl = TextEditingController();
  final labValueCtl = TextEditingController();
  final notesCtl = TextEditingController();
  final prosUnitsCtl = TextEditingController(text: '1');
  final prosUnitPriceCtl = TextEditingController();

  String date = getCurrentDate();
  String clinic = '';
  String service = '';
  String payment = '';
  bool isDebt = false;
  bool showPhone2 = false;
  List<PatientSuggestion> suggestions = const [];

  // ── نظام «التحاليل الثلاثية» — تحليلٌ واحدٌ ثابتُ الاسم والسعر (معزول مالياً) ──
  // التفعيل يظهر قائمة طريقة الدفع فقط — الاسم والسعر ثابتان من الإعدادات.
  bool hasAnalysis = false;
  String analysisPay = 'كاش';

  /// المريض المحدد — يُضبط فقط باختيار اقتراح صريح (سلوك الأصل)؛
  /// تغيير الاسم بعده يفكّ الربط.
  String selectedPatient = '';

  // تقرير الأسنان (وضع «تحديد الأسنان» كما في AddRecord.vue).
  bool hasReport = false;
  List<JMap> reportEntries = [];
  JMap reportMeta = {};

  // حقول المختبر للتركيبات.
  String labName = '';
  String prosType = '';

  @override
  void dispose() {
    for (final c in [
      nameCtl,
      phoneCtl,
      phone2Ctl,
      amountCtl,
      firstPayCtl,
      labValueCtl,
      notesCtl,
      prosUnitsCtl,
      prosUnitPriceCtl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// onReportTgl + فتح الحوار: التفعيل يفتح المحدد؛ الإلغاء يمسح كل شيء.
  Future<void> _openReport() async {
    final result = await showToothReportDialog(
      context,
      entries: reportEntries,
      meta: reportMeta,
      teethOnly: true,
      patientName: nameCtl.text.trim(),
      patientPhone: phoneCtl.text.trim(),
      notation: ref.read(notationSystemProvider),
    );
    if (!mounted) return;
    setState(() {
      if (result == null) {
        hasReport = false;
        reportEntries = [];
        reportMeta = {};
      } else {
        reportEntries = result.entries;
        reportMeta = result.meta;
        hasReport = reportEntries.isNotEmpty;
      }
    });
  }

  /// onProsTypeChange — سعر النوع الافتراضي يملأ سعر الوحدة وقيمة المخبر.
  void _onProsTypeChange(List<JMap> labTypes) {
    JMap? sel;
    for (final t in labTypes) {
      if ('${t['name']}' == prosType) {
        sel = t;
        break;
      }
    }
    if (sel != null && jsTruthy(sel['defaultPrice'])) {
      prosUnitPriceCtl.text = jsNumOr0(sel['defaultPrice']).toStringAsFixed(0);
      _onUnitsChange();
      return;
    }
    setState(() {});
  }

  /// onUnitsOrPriceChange — قيمة المخبر = وحدات × سعر الوحدة.
  void _onUnitsChange() {
    final units = jsNumOr0(prosUnitsCtl.text);
    final price = jsNumOr0(prosUnitPriceCtl.text);
    labValueCtl.text = ((units == 0 ? 1 : units) * price).toStringAsFixed(0);
    setState(() {});
  }

  void _applyDefaults(
    List<String> clinics,
    List<String> services,
    List<String> payments,
  ) {
    if (clinic.isEmpty && clinics.isNotEmpty) clinic = clinics.first;
    // م34 — المعالجة الافتراضية: آخر اختيار للمستخدم ← المُعدّة في
    // الإعدادات ← أول القائمة (توأم defaultService في الأصل).
    if (service.isEmpty && services.isNotEmpty) {
      service = defaultServiceFor(
        ref.read(localDbProvider),
        ref.read(appConfigProvider),
        services,
      );
    }
    if (payment.isEmpty && payments.isNotEmpty) payment = payments.first;
  }

  // ── الاقتراحات (الهاتف أولاً + الاسم) ──
  void _refreshNameSuggestions(String q) {
    final repos = ref.read(reposProvider);
    setState(() {
      if (selectedPatient.isNotEmpty && q.trim() != selectedPatient.trim()) {
        selectedPatient = ''; // فكّ الربط عند تغيير الاسم (الحارس).
      }
      suggestions = q.trim().length < 2
          ? const []
          : localNameSearch(
              q,
              selectedClinic: clinic,
              records: repos.records.getAll(),
              prosthetics: repos.prosthetics.getAll(),
              debts: repos.debts.getAll(),
            );
    });
  }

  void _refreshPhoneSuggestions(String phone) {
    // م167/ب — مريضٌ مربوط فعلاً ⇒ كتابة الهاتف لا تفتح اقتراحات جديدة
    // (اختيار الاسم يلغي اقتراحات الهاتف والعكس — مصدرٌ واحدٌ نشط).
    if (selectedPatient.isNotEmpty) {
      if (suggestions.isNotEmpty) {
        setState(() => suggestions = const []);
      }
      return;
    }
    final repos = ref.read(reposProvider);
    final found = phoneFirstSearch(
      phone,
      selectedClinic: clinic,
      records: repos.records.getAll(),
      prosthetics: repos.prosthetics.getAll(),
      debts: repos.debts.getAll(),
    );
    if (found.isNotEmpty || suggestions.isNotEmpty) {
      setState(() => suggestions = found);
    }
  }

  /// selectPatientName — الربط الصريح الوحيد: اسم + هاتفان + رسالة.
  void _selectSuggestion(PatientSuggestion s) {
    if (clinic.isNotEmpty && s.clinic.isNotEmpty && s.clinic != clinic) {
      _snack('هذا المريض مسجَّل في عيادة أخرى — لا يمكن ربطه بالعيادة الحالية');
      setState(() => suggestions = const []);
      return;
    }
    setState(() {
      selectedPatient = s.name;
      nameCtl.text = s.name;
      if (s.phone.isNotEmpty && phoneCtl.text.trim().isEmpty) {
        phoneCtl.text = s.phone;
      }
      if (s.phone2.isNotEmpty && phone2Ctl.text.trim().isEmpty) {
        phone2Ctl.text = s.phone2;
        showPhone2 = true;
      }
      suggestions = const [];
    });
    _snack('تم الربط بسجل المريض: ${s.name}');
  }

  // ── المعلومات الطبية ──
  /// م96 — هاتف صف المريض المخزن (للمفتاح الهوياتي وقراءته الآمنة).
  String _patientRowPhone(String nm) =>
      '${ref.read(reposProvider).patients.getById(nm)?['phone'] ?? ''}';

  bool get _hasMedical {
    final nm = nameCtl.text.trim();
    if (selectedPatient.isEmpty || selectedPatient != nm) return false;
    final cfg = ref.read(appConfigProvider);
    // م96 — عزل هوياتي كامل: عيادة + هاتف (لا قراءة عارية بالاسم).
    final med = medicalScopedRead(
      cfg['patientMedical'],
      nm,
      clinic,
      phoneCtl.text,
      rowPhone: _patientRowPhone(nm),
    );
    return medicalHasData(med);
  }

  Future<void> _openMedicalInfo() async {
    final nm = nameCtl.text.trim();
    if (nm.isEmpty) {
      _snack('أدخل اسم المريض أولاً');
      return;
    }
    final cfg = ref.read(appConfigProvider);
    final rowPhone = _patientRowPhone(nm);
    final saved = medicalScopedRead(
      cfg['patientMedical'],
      nm,
      clinic,
      phoneCtl.text,
      rowPhone: rowPhone,
    );
    final result = await showMedicalInfoDialog(
      context,
      patientName: nm,
      initial: saved is Map ? Map<String, Object?>.from(saved) : const {},
    );
    if (result == null || !mounted) return;
    final repos = ref.read(reposProvider);
    final cur = Map<String, Object?>.from(ref.read(appConfigProvider));
    repos.settings.set('app.config', {
      ...cur,
      'patientMedical': medicalScopedWrite(
        cur['patientMedical'],
        nm,
        clinic,
        phoneCtl.text,
        result,
        rowPhone: rowPhone,
      ),
    });
    ref.read(configRevProvider.notifier).state++;
    // الإضافة الصريحة فعلٌ على هذا المريض ⇒ يصبح محدداً (سلوك الأصل).
    setState(() => selectedPatient = nm);
    _snack('تم حفظ المعلومات الطبية');
  }

  /// م90 — حارس السميّين: قبل حفظ زيارةٍ باسمٍ له وجودٌ سابق في العيادة
  /// المختارة، يوضَّح مصير الحفظ حين يكون الهاتف هو الفيصل — فلا يُنشأ
  /// سميٌّ بالخطأ ولا تُلحق زيارةُ سميٍّ جديد بملف مريضٍ قائم بصمت.
  ///
  ///  الحالات (بنفس قاعدة تقسيم م90 حرفياً):
  ///  • اسمٌ جديد كلياً، أو هاتفٌ مطابق لهوية قائمة، أو إضافة هاتفٍ أول
  ///    لمريض بلا هاتف ⇒ حفظٌ صامت (لا حوار).
  ///  • هاتفٌ فارغ والاسم القائم له هاتف ⇒ حوار: نفس المريض أم أدخل هاتفاً؟
  ///  • هاتفٌ مختلف عن كل هواتف الاسم ⇒ حوار: سيُنشأ مريض جديد مستقل.
  Future<bool> _confirmTwinIdentity() async {
    final nm = nameCtl.text.trim();
    if (nm.isEmpty) return true;
    final repos = ref.read(reposProvider);
    final typedPhone = phoneCtl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    final rows = <Map<String, Object?>>[
      for (final r in repos.records.getByPatient(nm))
        if ('${r['clinic'] ?? ''}' == clinic) r,
      for (final p in repos.prosthetics.getAll())
        if ('${p['patient_name'] ?? p['name'] ?? ''}' == nm &&
            '${p['clinic'] ?? ''}' == clinic)
          p,
      for (final d in repos.debts.getDebtsByPatient(nm))
        if ('${d['clinic'] ?? ''}' == clinic) d,
    ];
    if (rows.isEmpty) return true;
    final phones = distinctIdentityPhones(rows);

    if (typedPhone.isEmpty) {
      if (phones.isEmpty) return true; // كلاهما بلا هاتف — نفس الملف كما كان.
      return _twinDialog(
        'يوجد مريض مسجّل بهذا الاسم في هذه العيادة.\n\n'
        'إن كان هذا مريضاً جديداً مختلفاً فارجع وأدخل رقم هاتفه للتمييز '
        'بينهما — وإلا ستُسجَّل الزيارة ضمن ملف المريض القائم.',
        proceedLabel: 'متابعة لنفس المريض',
      );
    }
    if (phones.isEmpty || phones.contains(typedPhone)) return true;
    return _twinDialog(
      'يوجد مريض بهذا الاسم في هذه العيادة برقم هاتف مختلف.\n\n'
      'بالمتابعة ستُنشأ بطاقة مريضٍ جديدة مستقلة مميّزة بهذا الرقم — '
      'وإن كان نفس المريض فارجع وصحّح رقم الهاتف.',
      proceedLabel: 'إنشاء مريض جديد',
    );
  }

  Future<bool> _twinDialog(
    String message, {
    required String proceedLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.people_alt_rounded,
              size: 16,
              color: BrandColors.goldDark,
            ),
            SizedBox(width: 6),
            Text(
              'اسم مكرر في العيادة',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: BrandColors.goldDark,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 12.5, height: 1.7),
        ),
        actions: [
          TextButton(
            key: const Key('twin-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('رجوع', style: TextStyle(fontSize: 12.5)),
          ),
          FilledButton(
            key: const Key('twin-proceed'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(proceedLabel, style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// م96 — الحاسبة المصغرة من داخل حالة النموذج (توأم _openCalculator في
  /// الزيارة السريعة حرفياً): إلغاء تركيز الكيبورد ثم فتح الحوار بسياق
  /// النموذج نفسه وإدراج الناتج في حقل القيمة — كان الاستدعاء عبر مفتاح
  /// عام من ترويسة الورقة فلا يُدرج (بلاغ ما بعد 94).
  Future<void> _openCalcInsert() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final v = await showMiniCalculator(context);
    if (v != null && mounted) {
      setState(
        () => amountCtl.text = v == v.roundToDouble()
            ? v.toStringAsFixed(0)
            : '$v',
      );
    }
  }

  Future<void> _save() async {
    // م167/ب — رقم هاتف ناقص (غير فارغ وأقل من 10 أرقام) يوقف الحفظ؛
    // الفارغ يمر كما كان (الحقل اختياري — لا كسر للبيانات القديمة).
    for (final ctl in [phoneCtl, phone2Ctl]) {
      final digits = ctl.text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty && digits.length < 10) {
        _snack('⚠ رقم الهاتف ناقص — الصيغة 09XXXXXXXX');
        return;
      }
    }
    // م149 — قاعدة تكرار التحليل: إن كانت علامة «التحاليل الثلاثية» مؤشَّرة
    // والمريض ممنوعاً (لم تمضِ المدة المضبوطة منذ آخر تحليل) يتوقف الحفظ
    // **كله** برسالة الخطأ حتى يزيل المستخدم العلامة — قرار المالك الصريح.
    {
      final cfg = ref.read(appConfigProvider);
      final wouldWriteAnalysis = widget.editEntry == null &&
          hasAnalysis &&
          triAnalysesEnabled(cfg) &&
          triAnalysesPrice(cfg) > 0;
      if (wouldWriteAnalysis) {
        // م153 — بنطاق العيادة المختارة وهاتف النموذج (استثناء السميَّين).
        final blocked = triRepeatCheck(
          ref,
          patientName: nameCtl.text.trim(),
          clinic: clinic,
          phone: phoneCtl.text.trim(),
        );
        if (blocked != null) {
          await showTriRepeatBlockedDialog(context, blocked);
          return;
        }
      }
    }
    if (!mounted) return;
    // م90 — حارس السميّين قبل أي كتابة.
    if (!await _confirmTwinIdentity()) return;
    if (!mounted) return;
    // م101/م117 — يوم احتساب الإيراد:
    //  • إضافةٌ جديدة، أو تعديلٌ **غيّر التاريخ** فعلاً ⇒ يُسأل «أين يُحسب؟».
    //  • تعديلٌ بلا تغيير تاريخ ⇒ يُحتفظ بيوم الاحتساب الأصلي بلا سؤال
    //    (فلا يُزعَج الطبيب ولا يضيع اختيار «السجلات والمالية فقط»).
    final String incomeDay;
    final e = widget.editEntry;
    if (e != null && date == '${e['date'] ?? ''}') {
      incomeDay =
          '${e['incomeDate'] ?? ''}'; // الأصلي كما هو (قد يكون فارغاً/none).
    } else {
      final asked = await askIncomeDay(context, date);
      if (asked == null || !mounted) return;
      incomeDay = asked;
    }
    final repos = ref.read(reposProvider);
    // م104/م117 — اليوم الفعلي للاحتساب مقفول؟ تنبيه ومتابعة بالتأكيد.
    // «none» خارج كل جداول اليوم فلا يُحرَس؛ الفارغ يعني تاريخ السجل.
    final guardDay = (incomeDay.isNotEmpty && incomeDay != kNoIncomeDay)
        ? incomeDay
        : (incomeDay == kNoIncomeDay ? '' : date);
    if (!await confirmClosedDayWrite(context, repos.settings, guardDay)) {
      return;
    }
    if (!mounted) return;
    final config = ref.read(appConfigProvider);
    try {
      final input = SaveRecordInput(
        incomeDate: incomeDay,
        name: nameCtl.text,
        date: date,
        amount: jsNumOr0(amountCtl.text),
        clinic: clinic,
        service: service,
        payment: payment,
        isDebt: isDebt,
        firstPay: jsNumOr0(firstPayCtl.text),
        phone: phoneCtl.text.trim(),
        phone2: phone2Ctl.text.trim(),
        notes: notesCtl.text.trim(),
        labValue: jsNumOr0(labValueCtl.text),
        labName: labName,
        prosType: prosType,
        prosUnits: jsNumOr0(prosUnitsCtl.text) == 0
            ? 1
            : jsNumOr0(prosUnitsCtl.text),
        prosUnitPrice: jsNumOr0(prosUnitPriceCtl.text),
        report: hasReport && reportEntries.isNotEmpty
            ? {'entries': reportEntries, 'meta': reportMeta}
            : null,
        // نظام «التحاليل الثلاثية» — دالة نقية تعيد null في وضع التعديل أو
        // حين الميزة معطّلة أو السعر صفر، وإلا تعيد AnalysisInput بالاسم
        // والسعر الثابتَين من الإعدادات.
        analysis: triAnalysisFor(
          creating: widget.editEntry == null,
          checked: hasAnalysis,
          cfg: config,
          payment: analysisPay,
        ),
      );

      // ═══ م100 — وضع التعديل: إنشاء البديل أولاً ثم حذف الأصل ═══
      // الترتيب مقصود: فشلُ الإنشاء يُبقي الأصل سليماً (لا فقدان)؛
      // وفشلُ الحذف بعده يترك نسخة مكررة ظاهرة تُحذف يدوياً — أهون
      // الشرّين في سجل طبي. التحقق يسبق كل شيء.
      if (widget.editEntry != null) {
        final err = validateRecordInput(input);
        if (err != null) {
          _snack(err);
          return;
        }
        final oldId = '${widget.editEntry!['id']}';
        final result = saveNewRecord(repos, config, input);
        deleteEntryCascade(
          repos,
          config,
          id: oldId,
          source: widget.editKind == 'p' ? 'p' : 'r',
        );
        recordAudit(
          repos.db,
          action: 'record.editReplace',
          entity: widget.editKind == 'p' ? 'prosthetics' : 'records',
          entityId: result.entryId,
          detail: {'note': 'تعديل من الرئيسية', 'replaced': oldId},
        );
        _snack('تم تعديل السجل');
        ref.read(patientsRevProvider.notifier).state++;
        ref.read(financeRevProvider.notifier).state++;
        widget.onSaved?.call();
        return;
      }

      final result = saveNewRecord(repos, config, input);
      _snack(result.message);
      // م34 — تذكّر آخر معالجة اختارها المستخدم (تفضيل محلي فوري).
      rememberTreatment(ref.read(localDbProvider), service);
      ref.read(patientsRevProvider.notifier).state++;
      setState(() {
        nameCtl.clear();
        phoneCtl.clear();
        phone2Ctl.clear();
        amountCtl.clear();
        firstPayCtl.clear();
        labValueCtl.clear();
        notesCtl.clear();
        isDebt = false;
        showPhone2 = false;
        selectedPatient = '';
        suggestions = const [];
        date = getCurrentDate();
        hasReport = false;
        reportEntries = [];
        reportMeta = {};
        labName = '';
        prosType = '';
        prosUnitsCtl.text = '1';
        prosUnitPriceCtl.clear();
        // نظام «التحاليل الثلاثية» — تصفير حالة التحليل بعد الحفظ.
        hasAnalysis = false;
        analysisPay = 'كاش';
      });
      // في الورقة السفلية: تُغلق بعد حفظٍ ناجح (جدول الدخل يتحدّث عبر
      // patientsRevProvider). خارج الورقة (onSaved == null) لا أثر.
      widget.onSaved?.call();
    } on ArgumentError catch (e) {
      // تحقّق مدخلات — رسالة عربية جاهزة للمستخدم.
      _snack('${e.message}');
    } catch (e, s) {
      // م77 — كان هذا المسار **مفتوحاً**: `on ArgumentError` وحده يلتقط
      // أخطاء التحقق، بينما `saveNewRecord` يفتح معاملة SQLite. فقرصٌ
      // ممتلئ أو قاعدة مغلقة أو خرق قيد يرمي `StateError`/`SqliteException`
      // كان يمرّ بلا التقاط، فتبتلعه المنطقة صامتاً **ويظنّ الطبيب أن
      // الزيارة حُفظت**. في سجلّ طبي، كتابةٌ يُظَنّ أنها نجحت أخطر بكثير
      // من كتابة تفشل بصوت عالٍ.
      //
      // المعاملة نفسها ذرّية (نقاط حفظ متداخلة) فلا صفّ نصفيّ على القرص —
      // الناقص كان إبلاغ المستخدم وتسجيل الأثر، لا سلامة البيانات.
      recordError(e, s, context: 'add_record:_save');
      _snack('تعذّر الحفظ — لم تُسجَّل الزيارة. أعد المحاولة');
    }
  }

  @override
  Widget build(BuildContext context) {
    final clinics = ref.watch(clinicsProvider);
    final config = ref.watch(appConfigProvider);
    ref.watch(patientsRevProvider); // شريط اليوم يحدّث بعد كل حفظ
    final services = (config['services'] is List)
        ? (config['services'] as List).map((e) => '$e').toList()
        : const <String>[];
    final payments = (config['payments'] is List)
        ? (config['payments'] as List).map((e) => '$e').toList()
        : const <String>['كاش', 'تحويل'];
    _applyDefaults(clinics, services, payments);

    final repos = ref.watch(reposProvider);
    final records = repos.records.getAll();
    final prosthetics = repos.prosthetics.getAll();
    final debts = repos.debts.getAll();
    final cur = ref.watch(currencyProvider);
    final n = formatNumber;

    final tPatients = todayPatients(records, prosthetics);
    final tIncome = todayIncome(records, prosthetics, debts);
    final tDebt = todayDebt(debts);

    final pros = isProsthetic(service);
    // إشعارٌ بصري بحت للوح المرسى: أقسامٌ مفتوحة (دين/تركيبات) ⇒ توسّع
    // تلقائي. بعد الإطار (لا داخل البناء) فلا setState-during-build، ولا
    // أثر على أي حقل/منطق. الهاتف لا يمرّر onExpandedContent فلا يتأثر.
    if (widget.onExpandedContent != null) {
      // نظام «التحاليل» — منطقة التحليل المنبسطة تحتاج مساحةً أيضاً.
      final needsRoom = isDebt || pros || hasAnalysis;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onExpandedContent!(needsRoom);
      });
    }
    final amount = jsNumOr0(amountCtl.text);
    final lab = jsNumOr0(labValueCtl.text);
    final prosNet = (amount - lab).clamp(0, double.infinity);
    // النسبة الحية للمعاينة فقط — الحفظ يجمّد لقطته الخاصة.
    final prosPctLive = resolveDoctorPct(
      config,
      clinic: clinic,
      service: service,
      isPros: true,
    );
    final prosDocShare = prosNet * (prosPctLive / 100);
    final prosClinShare = prosNet * ((100 - prosPctLive) / 100);

    // م167 — النمط الناعم الموحد (م163): تعبئة خافتة + حد شعري + زوايا
    // 12 + تركيز بلون العلامة — نظام واحد لكل الحقول في النسختين.
    OutlineInputBorder fieldBorder(Color color, [double w = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: w),
        );
    InputDecoration dec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12.5, color: BrandColors.faint),
      isDense: true,
      filled: true,
      fillColor: BrandColors.ink.withValues(alpha: .045),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      enabledBorder: fieldBorder(BrandColors.line, .7),
      focusedBorder: fieldBorder(BrandColors.brand600, 1.3),
      border: fieldBorder(BrandColors.line, .7),
    );
    // م167/ب — ملصق عائم داخل الحقل (للأقسام المتمددة: تركيبات/دين).
    InputDecoration vdec(String label, {String hint = ''}) =>
        dec(hint).copyWith(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          floatingLabelStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: BrandColors.brandText,
          ),
        );
    // م167 — إيقاع موحد: ملصق 10.5 فوق الحقل وارتفاع ثابت 46 لكل صف.
    Widget labeled(String label, Widget field) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: BrandColors.mut,
            ),
          ),
        ),
        SizedBox(height: 46, child: field),
      ],
    );

    // ═══ التخطيط الأفقي متعدد الأعمدة (لوح الكمبيوتر المرسى فقط) ═══
    // فرعٌ جديد معزول تماماً: يوزّع نفس الحقول (بمفاتيحها ومنطقها حرفياً)
    // على أعمدةٍ أفقية بدل القائمة العمودية. الهاتف/الشاشة الكاملة
    // (horizontal:false الافتراضي) لا يمرّان به إطلاقاً.
    if (widget.horizontal) {
      return _horizontalBody(
        context: context,
        clinics: clinics,
        services: services,
        payments: payments,
        config: config,
        cur: cur,
        n: n,
        pros: pros,
        prosNet: prosNet,
        prosPctLive: prosPctLive,
        prosDocShare: prosDocShare,
        prosClinShare: prosClinShare,
        dec: dec,
        labeled: labeled,
      );
    }

    // م94 — المضغوط (ورقة الإدخال): قائمة منكمشة بلا تمرير ذاتي — التمرير
    // كله للتمريرة الخارجية الواحدة في الورقة (توأم الزيارة السريعة)،
    // وبلا حشوة جانبية (الورقة توفّر 16 من الجانبين).
    return ListView(
      controller: widget.scrollController,
      shrinkWrap: widget.compact,
      physics: widget.compact ? const NeverScrollableScrollPhysics() : null,
      padding: widget.compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(14, 8, 14, 90),
      children: [
        // ═══ م96: ترويسة الورقة داخل النموذج — العنوان + زر الحاسبة ═══
        //     (توأم ترويسة الزيارة السريعة؛ الحاسبة بحالة النموذج نفسها
        //      فتُدرج ناتجها في حقل القيمة مباشرة.)
        if (widget.compact) ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.editEntry != null ? 'تعديل زيارة' : 'زيارة جديدة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.brandText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.editEntry != null
                          ? 'عدّل ما تشاء ثم احفظ — يستبدل السجل الأصلي'
                          : 'كل خيارات الإدخال — تُحفظ فوراً',
                      style: TextStyle(fontSize: 10.5, color: BrandColors.mut2),
                    ),
                  ],
                ),
              ),
              Material(
                color: const Color.fromRGBO(201, 162, 75, .1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(
                    color: Color.fromRGBO(201, 162, 75, .3),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('rec-calc'),
                  onTap: _openCalcInsert,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.calculate_rounded,
                      size: 20,
                      color: BrandColors.goldDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        // ═══ شريط ملخص اليوم — يُخفى داخل ورقة الإدخال المضغوطة (دخل اليوم
        //     صار له تبويب الرئيسية) ═══
        if (!widget.compact)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: BrandColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: BrandColors.line.withValues(alpha: .5),
                width: .6,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                _todayCell(
                  key: const Key('today-patients'),
                  value: tPatients > 0 ? '$tPatients' : '—',
                  label: 'مريض',
                  onTap: () => _openSheet('patients'),
                ),
                _todayCell(
                  key: const Key('today-income'),
                  value: tIncome > 0 ? n(tIncome) : '—',
                  label: 'دخل اليوم',
                  onTap: () => _openSheet('income'),
                ),
                _todayCell(
                  key: const Key('today-debt'),
                  value: tDebt > 0 ? n(tDebt) : '—',
                  label: 'دين اليوم',
                  color: tDebt > 0 ? BrandColors.red : BrandColors.goldDark,
                  onTap: () => _openSheet('debt'),
                ),
              ],
            ),
          ),

        // ═══ بطاقة الإدخال ═══ (المضغوط: بلا بطاقة — الحقول على سطح
        // الورقة مباشرة، توأم الزيارة السريعة — م94)
        _maybeCard(
          compact: widget.compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // م167 — في المضغوط: زر «اليوم» انتقل لرأس الورقة وسطر
              // «بيانات الزيارة» أُسقط (رأسٌ واحد لا ثلاثة أسطر).
              if (!widget.compact) ...[
                Row(
                  children: [
                    Icon(
                      Icons.edit_rounded,
                      size: 15,
                      color: BrandColors.brandIcon,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'إدخال جديد',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: BrandColors.brandText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // ── الصف 1: التاريخ + العيادة (متناظران) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: labeled(
                      'التاريخ',
                      InkWell(
                        key: const Key('rec-date'),
                        borderRadius: BorderRadius.circular(4),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.parse(date),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setState(
                              () => date =
                                  '${picked.year.toString().padLeft(4, '0')}-'
                                  '${picked.month.toString().padLeft(2, '0')}-'
                                  '${picked.day.toString().padLeft(2, '0')}',
                            );
                          }
                        },
                        child: InputDecorator(
                          decoration: dec('').copyWith(
                            // م167/ب — «اليوم» أيقونة داخل الحقل (يساره).
                            suffixIcon: IconButton(
                              key: const Key('rec-today'),
                              tooltip: 'اليوم',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                setState(() => date = getCurrentDate());
                                ref
                                    .read(selectedMonthProvider.notifier)
                                    .state = getCurrentDate().substring(0, 7);
                              },
                              icon: Icon(Icons.today_rounded,
                                  size: 17, color: BrandColors.brand700),
                            ),
                            suffixIconConstraints: const BoxConstraints(
                                minWidth: 36, minHeight: 36),
                          ),
                          child: Center(
                            child: Text(
                              _enDate(date),
                              maxLines: 1,
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: labeled(
                      'العيادة',
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: const Key('rec-clinic'),
                        icon: const SizedBox.shrink(),
                        initialValue: clinic.isEmpty ? null : clinic,
                        decoration: dec(''),
                        items: [
                          for (final c in clinics)
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (v) => setState(() => clinic = v ?? ''),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── الصف 2: الاسم أولاً ثم الهاتف (م167/ب — قرار المالك)،
              // نصفان متساويان وزر الرقم الثاني suffix داخل حقل الهاتف ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: labeled(
                      'اسم المريض',
                      TextField(
                        key: const Key('rec-name'),
                        controller: nameCtl,
                        decoration: dec('ابحث أو أدخل اسماً'),
                        onChanged: _refreshNameSuggestions,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: labeled(
                      'رقم الهاتف',
                      TextField(
                        key: const Key('rec-phone'),
                        controller: phoneCtl,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        decoration: dec('09XXXXXXXX').copyWith(
                          suffixIcon: showPhone2
                              ? null
                              : IconButton(
                                  key: const Key('rec-phone2-add'),
                                  tooltip: 'رقم ثانٍ',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      setState(() => showPhone2 = true),
                                  icon: Icon(
                                    Icons.add_rounded,
                                    size: 16,
                                    color: BrandColors.brand700,
                                  ),
                                ),
                          suffixIconConstraints: const BoxConstraints(
                              minWidth: 34, minHeight: 34),
                        ),
                        onChanged: _refreshPhoneSuggestions,
                      ),
                    ),
                  ),
                ],
              ),
              if (showPhone2) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('rec-phone2'),
                        controller: phone2Ctl,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        decoration: dec('رقم ثانٍ (اختياري)'),
                      ),
                    ),
                    IconButton(
                      key: const Key('rec-phone2-del'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        showPhone2 = false;
                        phone2Ctl.clear();
                      }),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: BrandColors.red,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ],

              // ── لوحة اقتراحات المرضى (تحت الهاتف) ──
              if (suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: BrandColors.gold.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: BrandColors.gold.withValues(alpha: .25),
                    ),
                  ),
                  child: Column(
                    children: [
                      for (final s in suggestions)
                        InkWell(
                          key: Key('rec-suggest-${s.name}'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _selectSuggestion(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          s.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (s.clinic.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          child: Text(
                                            s.clinic,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: BrandColors.brandText,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (s.phone.isNotEmpty)
                                  Text(
                                    s.phone,
                                    textDirection: TextDirection.ltr,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BrandColors.mut2,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),

              // ── الصف 3: المعالجة + طريقة الدفع (متناظران) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: labeled(
                      'المعالجة',
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: const Key('rec-service'),
                        icon: const SizedBox.shrink(),
                        initialValue: service.isEmpty ? null : service,
                        decoration: dec(''),
                        items: [
                          for (final s in services)
                            DropdownMenuItem(value: s, child: Text(s)),
                        ],
                        onChanged: (v) => setState(() {
                          service = v ?? '';
                          // م55 — اختيار المعالجة يُظهر سعرها المضبوط في
                          // الإعدادات فوراً في حقل القيمة (كان يملأ الفارغ
                          // فقط، فتبديل المعالجة يُبقي سعر السابقة). الحقل
                          // يبقى حراً للتعديل اليدوي بعد الملء، ومعالجة
                          // بلا سعر مضبوط لا تمس ما كتبه المستخدم.
                          final prices = config['servicePrices'];
                          final p0 = prices is Map ? prices[service] : null;
                          if (jsNumOr0(p0) > 0) {
                            amountCtl.text = jsNumOr0(p0).toStringAsFixed(0);
                          }
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: labeled(
                      'طريقة الدفع',
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: const Key('rec-payment'),
                        icon: const SizedBox.shrink(),
                        initialValue: payment.isEmpty ? null : payment,
                        decoration: dec(''),
                        items: [
                          for (final p in payments)
                            DropdownMenuItem(value: p, child: Text(p)),
                        ],
                        onChanged: (v) => setState(() => payment = v ?? ''),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ── الصف 4: القيمة + (دين/التحاليل) — نصفان متوازنان
              // بنفس ارتفاع الحقل، بلا شريحة «موعد» (م167 — قرار المالك) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: labeled(
                      'القيمة ($cur)',
                      TextField(
                        key: const Key('rec-amount'),
                        controller: amountCtl,
                        keyboardType: TextInputType.number,
                        decoration: dec('0'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: labeled(
                      'خيارات',
                      Container(
                        decoration: BoxDecoration(
                          color: BrandColors.ink.withValues(alpha: .045),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: BrandColors.line, width: .7),
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _miniSwitch(
                              key: const Key('rec-debt'),
                              value: isDebt,
                              onChanged: (v) =>
                                  setState(() => isDebt = v),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'دين',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: isDebt
                                    ? BrandColors.goldDark
                                    : BrandColors.mut,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ── م167/ج: «التحاليل الثلاثية» سطرٌ كامل بارز (كانت
              // منكمشة كأنها إضافة هامشية — ملاحظة المالك) ──
              if (widget.editEntry == null &&
                  triAnalysesEnabled(config)) ...[
                const SizedBox(height: 10),
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: hasAnalysis
                        ? BrandColors.green.withValues(alpha: .08)
                        : BrandColors.ink.withValues(alpha: .045),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasAnalysis
                          ? BrandColors.green.withValues(alpha: .45)
                          : BrandColors.line,
                      width: hasAnalysis ? 1 : .7,
                    ),
                  ),
                  child: Center(child: _analToggle(config)),
                ),
              ],

              // ── قسم التركيبات ──
              if (pros) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: BrandColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: BrandColors.line, width: .7),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              key: const Key('rec-labname'),
                              initialValue: labName.isEmpty ? null : labName,
                              decoration: vdec('المختبر'),
                              items: [
                                for (final l in labsList(config))
                                  DropdownMenuItem(value: l, child: Text(l)),
                              ],
                              onChanged: (v) => setState(() {
                                labName = v ?? '';
                                // م162 — النوع المختار ليس من أنواع
                                // المختبر الجديد ⇒ يُفرَّغ ليُختار منه.
                                final ts = labTypesFor(config, labName);
                                if (prosType.isNotEmpty &&
                                    !ts.any(
                                        (t) => '${t['name']}' == prosType)) {
                                  prosType = '';
                                }
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              key: const Key('rec-prostype'),
                              initialValue: prosType.isEmpty ? null : prosType,
                              decoration: vdec('نوع التركيبة'),
                              items: [
                                // م162 — أنواع المختبر المختار وحده.
                                for (final t in labTypesFor(config, labName))
                                  DropdownMenuItem(
                                    value: '${t['name']}',
                                    child: Text('${t['name']}'),
                                  ),
                              ],
                              onChanged: (v) {
                                prosType = v ?? '';
                                _onProsTypeChange(
                                    labTypesFor(config, labName));
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('rec-prosunits'),
                              controller: prosUnitsCtl,
                              keyboardType: TextInputType.number,
                              decoration: vdec('عدد الواحدات', hint: '0'),
                              onChanged: (_) => _onUnitsChange(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              key: const Key('rec-prosunitprice'),
                              controller: prosUnitPriceCtl,
                              keyboardType: TextInputType.number,
                              decoration: vdec('سعر الوحدة', hint: '0'),
                              onChanged: (_) => _onUnitsChange(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              key: const Key('rec-lab'),
                              controller: labValueCtl,
                              keyboardType: TextInputType.number,
                              decoration: vdec('قيمة المعمل', hint: '0'),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // معاينة التقسيم الحية — الملصقات والصيغ الحرفية.
                      _previewRow(
                        'صافي الربح:',
                        n(prosNet),
                        BrandColors.goldDark,
                        key: const Key('pros-net'),
                      ),
                      _previewRow(
                        'نسبة الطبيب (${prosPctLive.toStringAsFixed(0)}%):',
                        n(prosDocShare),
                        const Color(0xFF065F46),
                        key: const Key('pros-doc'),
                      ),
                      _previewRow(
                        'نسبة العيادة (${(100 - prosPctLive).toStringAsFixed(0)}%):',
                        n(prosClinShare),
                        const Color(0xFF047857),
                        key: const Key('pros-clin'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),

              // ── م167: رقاقتان متساويتان بارتفاع موحد (كانتا مفتاحين
              // عائمين بلا احتواء) — نفس المفاتيح والسلوك حرفياً ──
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: BrandColors.ink.withValues(alpha: .045),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: BrandColors.line, width: .7),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          _miniSwitch(
                            key: const Key('rec-report-tgl'),
                            value: hasReport,
                            onChanged: (v) {
                              if (v) {
                                setState(() => hasReport = true);
                                _openReport();
                              } else {
                                setState(() {
                                  hasReport = false;
                                  reportEntries = [];
                                  reportMeta = {};
                                });
                              }
                            },
                          ),
                          Flexible(
                            child: InkWell(
                              key: const Key('rec-report-open'),
                              onTap: hasReport ? _openReport : null,
                              child: Text(
                                hasReport && reportEntries.isNotEmpty
                                    ? 'تحديد الأسنان (${teethCount(reportEntries)})'
                                    : 'تحديد الأسنان',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: hasReport
                                      ? BrandColors.brandText
                                      : BrandColors.mut,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: BrandColors.ink.withValues(alpha: .045),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: BrandColors.line, width: .7),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          _miniSwitch(
                            key: const Key('rec-medical-tgl'),
                            value: _hasMedical,
                            // النقرة تفتح النافذة دائماً — الحالة انعكاس
                            // للبيانات الحقيقية (سلوك الأصل).
                            onChanged: (_) => _openMedicalInfo(),
                          ),
                          Flexible(
                            child: InkWell(
                              key: const Key('rec-medical-open'),
                              onTap: _openMedicalInfo,
                              child: Text(
                                'المعلومات الطبية',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _hasMedical
                                      ? BrandColors.brandText
                                      : BrandColors.mut,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // ── قسم الدين ──
              if (isDebt) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: BrandColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: BrandColors.line, width: .7),
                  ),
                  child: TextField(
                    key: const Key('rec-firstpay'),
                    controller: firstPayCtl,
                    keyboardType: TextInputType.number,
                    decoration: vdec('الدفعة الأولى', hint: '0'),
                  ),
                ),
              ],

              // ── نظام «التحاليل» — منطقة التحليل المنبسطة ──
              if (hasAnalysis) ...[
                const SizedBox(height: 10),
                _analysisSection(keyPrefix: 'rec'),
              ],

              // ── معلومات مختصرة (قرار المالك — ميزة الملاحظات المختصرة) ──
              // كانت «ملاحظات» حبيسةَ قسم الدين؛ صارت حقلاً دائماً لكل
              // زيارة/دفعة: تُخزَّن على صف السجل نفسه (record.notes)
              // فتلتصق به وتعبر المزامنة ولا تظهر إلا في سياقه.
              const SizedBox(height: 10),
              TextField(
                key: const Key('rec-notes'),
                controller: notesCtl,
                maxLines: 2,
                minLines: 1,
                decoration: dec('معلومات مختصرة (اختياري)'),
              ),

              // زر الحفظ داخل المحتوى — في المضغوط بهوية زر «حفظ
              // الزيارة» الحبي في ورقة الزيارة السريعة حرفياً (م94).
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('rec-save'),
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.brand600,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: Icon(
                  widget.compact ? Icons.check_rounded : Icons.save_rounded,
                  size: widget.compact ? 19 : 18,
                ),
                label: Text(
                  widget.editEntry != null
                      ? 'حفظ التعديل'
                      : (widget.compact ? 'حفظ الزيارة' : 'حفظ البيانات'),
                  style: TextStyle(
                    fontSize: widget.compact ? 13 : 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// ══════════════════════════════════════════════════════════════════════
  ///  التخطيط الأفقي متعدد الأعمدة — لوح الكمبيوتر المرسى فقط
  /// ══════════════════════════════════════════════════════════════════════
  ///
  ///  يوزّع مجموعات الحقول على أعمدةٍ عبر Row من Expanded يستغل عرض اللوح:
  ///   ① هوية المريض: [اليوم][التاريخ/العيادة] · [الهاتف/الاسم] · الاقتراحات
  ///   ② المعالجة والقيمة: [المعالجة/القيمة] · [الأسنان/الطبية] · التركيبات
  ///   ③ الدفع والخيارات: [الدفع/دين/موعد] · الدين · الملاحظات
  ///   ④ أزرار: الحفظ الذهبي + الحاسبة
  ///
  ///  كل حقلٍ بمفتاحه الحرفي وكل سلوكه (نفس callbacks الوضع العمودي بلا
  ///  تغيير) — الفرق التوزيع فقط. غلاف SingleChildScrollView رأسي احتياطي
  ///  يحمي عند الارتفاعات الصغيرة.
  Widget _horizontalBody({
    required BuildContext context,
    required List<String> clinics,
    required List<String> services,
    required List<String> payments,
    required JMap config,
    required String cur,
    required String Function(num) n,
    required bool pros,
    required num prosNet,
    required double prosPctLive,
    required num prosDocShare,
    required num prosClinShare,
    required InputDecoration Function(String) dec,
    required Widget Function(String, Widget) labeled,
  }) {
    // ── العناصر الذرّية (منسوخة حرفياً من الوضع العمودي بمفاتيحها) ──

    // زر «اليوم».
    // م147 — زر «اليوم» انتقل إلى داخل حقل التاريخ (suffix صغير) بدل سطرٍ
    // مستقل في ترويسة القسم: أقرب لمكانه الوظيفي وأوفر مساحةً (طلب المالك).
    void setToday() {
      setState(() => date = getCurrentDate());
      ref.read(selectedMonthProvider.notifier).state =
          getCurrentDate().substring(0, 7);
    }

    // م146/و — نظام قياسٍ واحد موحد؛ (م167: صف الأرباع ألغى rowGap).

    // م146 — زخرفة «كثيفة»: المسمى يعوم داخل إطار الحقل بدل سطرٍ مستقل
    // فوقه (نمط النماذج المكتبية الحديث) — يوفّر ~25 نقطة لكل صف، وهو
    // جوهر ميزانية اللاتمرير على شاشة 768.
    InputDecoration ddec(String label, {String hint = ''}) =>
        dec(hint).copyWith(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          floatingLabelStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: BrandColors.brandText,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        );

    final dateField = InkWell(
      key: const Key('rec-date'),
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.parse(date),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked != null) {
          setState(
            () => date =
                '${picked.year.toString().padLeft(4, '0')}-'
                '${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}',
          );
        }
      },
      child: InputDecorator(
        decoration: ddec('التاريخ').copyWith(
          // م167/ب — «اليوم» أيقونة فقط داخل الحقل (يساره).
          suffixIcon: IconButton(
            key: const Key('rec-today'),
            tooltip: 'اليوم',
            visualDensity: VisualDensity.compact,
            onPressed: setToday,
            icon: Icon(Icons.today_rounded,
                size: 17, color: BrandColors.brand700),
          ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 32,
          ),
        ),
        child: Center(
          heightFactor: 1,
          child: Text(
            _enDate(date),
            textDirection: TextDirection.ltr,
            style: const TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w800),
            maxLines: 1,
          ),
        ),
      ),
    );

    final clinicField = DropdownButtonFormField<String>(
      isExpanded: true,
      key: const Key('rec-clinic'),
      icon: const SizedBox.shrink(),
      initialValue: clinic.isEmpty ? null : clinic,
      decoration: ddec('العيادة'),
      items: [
        for (final c in clinics) DropdownMenuItem(value: c, child: Text(c)),
      ],
      onChanged: (v) => setState(() => clinic = v ?? ''),
    );

    // م167 — حقلان مفردان لشبكة الأرباع؛ زر الرقم الثاني suffix داخل
    // حقل الهاتف (كان مربعاً عائماً يكسر تساوي الأعمدة).
    final phoneField = TextField(
      key: const Key('rec-phone'),
      controller: phoneCtl,
      style: const TextStyle(fontSize: 14),
      keyboardType: TextInputType.phone,
      textDirection: TextDirection.ltr,
      decoration: ddec('رقم الهاتف', hint: '09XXXXXXXX').copyWith(
        suffixIcon: showPhone2
            ? null
            : IconButton(
                key: const Key('rec-phone2-add'),
                tooltip: 'رقم ثانٍ',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => showPhone2 = true),
                icon: Icon(
                  Icons.add_rounded,
                  size: 16,
                  color: BrandColors.brand700,
                ),
              ),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
      onChanged: _refreshPhoneSuggestions,
    );

    final nameField = TextField(
      key: const Key('rec-name'),
      controller: nameCtl,
      style: const TextStyle(fontSize: 14),
      decoration: ddec('اسم المريض', hint: 'ابحث أو أدخل اسماً'),
      onChanged: _refreshNameSuggestions,
    );

    final phone2Row = Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('rec-phone2'),
            controller: phone2Ctl,
            style: const TextStyle(fontSize: 14),
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: ddec('رقم ثانٍ', hint: 'اختياري'),
          ),
        ),
        IconButton(
          key: const Key('rec-phone2-del'),
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() {
            showPhone2 = false;
            phone2Ctl.clear();
          }),
          icon: const Icon(
            Icons.close_rounded,
            size: 15,
            color: BrandColors.red,
          ),
        ),
        const Spacer(),
      ],
    );

    // اقتراحات الأسماء/الهواتف — سقفٌ بارتفاعها كي لا تكسر ميزانية
    // اللاتمرير أثناء الكتابة؛ تتمرر داخلياً عند الamounts الكثيرة.
    final suggestionsPanel = Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: BrandColors.gold.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.gold.withValues(alpha: .25)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 126),
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (final s in suggestions)
                InkWell(
                  key: Key('rec-suggest-${s.name}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _selectSuggestion(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  s.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (s.clinic.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text(
                                    s.clinic,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: BrandColors.brandText,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (s.phone.isNotEmpty)
                          Text(
                            s.phone,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 11,
                              color: BrandColors.mut2,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final serviceField = DropdownButtonFormField<String>(
      isExpanded: true,
      key: const Key('rec-service'),
      icon: const SizedBox.shrink(),
      initialValue: service.isEmpty ? null : service,
      decoration: ddec('المعالجة'),
      items: [
        for (final s in services) DropdownMenuItem(value: s, child: Text(s)),
      ],
      onChanged: (v) => setState(() {
        service = v ?? '';
        final prices = config['servicePrices'];
        final p0 = prices is Map ? prices[service] : null;
        if (jsNumOr0(p0) > 0) {
          amountCtl.text = jsNumOr0(p0).toStringAsFixed(0);
        }
      }),
    );

    // م146 — الحاسبة زرٌّ صغير داخل حقل القيمة نفسه (suffix) بدل زرٍّ ضخم
    // في عمودٍ بعيد: أقرب لمكان الاستعمال وأوفر مساحةً (طلب المالك حرفياً).
    final amountField = TextField(
      key: const Key('rec-amount'),
      controller: amountCtl,
      style: const TextStyle(fontSize: 14),
      keyboardType: TextInputType.number,
      decoration: ddec('القيمة ($cur)', hint: '0').copyWith(
        suffixIcon: IconButton(
          key: const Key('rec-calc'),
          tooltip: 'الحاسبة',
          onPressed: _openCalcInsert,
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            Icons.calculate_rounded,
            size: 19,
            color: BrandColors.goldDark,
          ),
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
      ),
      onChanged: (_) => setState(() {}),
    );

    // م146 — «رقاقة ميزة» موحّدة: بديل مفاتيح التبديل (toggles) لفتح
    // المحرّرات. المفتاح كان يوحي بإعدادٍ ثنائي بينما الفعل «افتح محرراً»؛
    // الرقاقة تعرض الحالة (تعبئة/عدّاد) وتفتح بالنقر، وزرُّ مسحٍ صغير
    // للإلغاء حيث يلزم (نمط الأنظمة المكتبية القياسي).
    Widget featureChip({
      required Key key,
      required IconData icon,
      required String label,
      required bool active,
      required VoidCallback onTap,
      Key? clearKey,
      VoidCallback? onClear,
    }) {
      final fg = active ? BrandColors.brandText : BrandColors.mut;
      return Material(
        color: active
            ? BrandColors.brand600.withValues(alpha: .10)
            : BrandColors.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: active
                ? BrandColors.brand600.withValues(alpha: .45)
                : BrandColors.line,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 5, 6, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                if (onClear != null) ...[
                  const SizedBox(width: 2),
                  InkWell(
                    key: clearKey,
                    customBorder: const CircleBorder(),
                    onTap: onClear,
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: BrandColors.mut2,
                    ),
                  ),
                ] else
                  const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      );
    }

    // م147 — «تحديد الأسنان» أيقونةٌ فقط بجانب حقل المعالجة (طلب المالك):
    // مربّعٌ صغيرٌ 42 بشارة عدٍّ عند التحديد، يفتح المخطط بالنقر. الضغط
    // المطوّل يمسح التحديد (بديل زر المسح في الرقاقة القديمة).
    final teethActive = hasReport && reportEntries.isNotEmpty;
    final teethIconBtn = Tooltip(
      message: teethActive
          ? 'تحديد الأسنان (${teethCount(reportEntries)})'
          : 'تحديد الأسنان',
      child: Material(
        color: teethActive
            ? BrandColors.brand600.withValues(alpha: .10)
            : BrandColors.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: teethActive
                ? BrandColors.brand600.withValues(alpha: .45)
                : BrandColors.line,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('rec-report-open'),
          onTap: () {
            if (!hasReport) setState(() => hasReport = true);
            _openReport();
          },
          onLongPress: teethActive
              ? () => setState(() {
                  hasReport = false;
                  reportEntries = [];
                  reportMeta = {};
                })
              : null,
          child: SizedBox(
            width: 46,
            height: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  size: 18,
                  color: teethActive ? BrandColors.brandText : BrandColors.mut,
                ),
                if (teethActive)
                  PositionedDirectional(
                    top: 4,
                    end: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: BrandColors.brand600,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${teethCount(reportEntries)}',
                        style: const TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    final medicalChip = featureChip(
      key: const Key('rec-medical-open'),
      icon: Icons.medical_information_outlined,
      label: _hasMedical ? 'المعلومات الطبية ✓' : 'المعلومات الطبية',
      active: _hasMedical,
      onTap: _openMedicalInfo,
    );

    // م146 — الدفع شريط أزرارٍ مقسّم واحد (كاش | تحويل | دين) بدل قائمةٍ
    // منسدلة + مفتاح دينٍ منفصل: أوضاعٌ متنافية تُطبَّق فوراً (النمط
    // المكتبي القياسي للاختيار الفوري من 2-5 خيارات). يربط نفس الحالة
    // القديمة حرفياً: payment + isDebt — لا تغيير في نموذج البيانات.
    final segPays = [
      for (final p in payments)
        if (p != 'دين') p,
    ];
    final paySelected = segPays.contains(payment) ? payment : segPays.first;
    final segStyle = SegmentedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      backgroundColor: BrandColors.surface2,
      foregroundColor: BrandColors.mut,
      selectedBackgroundColor: BrandColors.brand600,
      selectedForegroundColor: Colors.white,
      side: BorderSide(color: BrandColors.line),
      // لا textStyle هنا: يرث خط العلامة من الثيم (تحديده يدوياً كان
      // يطمس عائلة الخط فتُرسم التسميات بخطٍ غريب).
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
    );
    // م146/هـ (ملاحظة المالك): «كاش/تحويل تُختار مرةً واحدة» — الشريط
    // المقسّم يحمل طريقة الدفع وحدها وتبقى محددةً دائماً، و«دين» زرُّ
    // تبديلٍ مستقل بجانبه (بهوية الدين الذهبية) لا يزاحمها ولا يكررها:
    // تفعيله يفتح حقل الدفعة الأولى فقط، ومسمّى الحقل يُظهر الطريقة
    // المختارة تلقائياً — لا مصدرين لحقيقةٍ واحدة.
    final debtToggle = SegmentedButton<String>(
      key: const Key('rec-debt-toggle'),
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        backgroundColor: BrandColors.surface2,
        foregroundColor: BrandColors.goldDark,
        selectedBackgroundColor: BrandColors.goldDark,
        selectedForegroundColor: Colors.white,
        side: BorderSide(color: BrandColors.gold.withValues(alpha: .45)),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      ),
      showSelectedIcon: false,
      emptySelectionAllowed: true,
      segments: const [ButtonSegment(value: 'دين', label: Text('دين'))],
      selected: {if (isDebt) 'دين'},
      onSelectionChanged: (s) => setState(() => isDebt = s.contains('دين')),
    );

    final paySegmented = Row(
      children: [
        // عمود مسمياتٍ ثابت (م146/و): يحاذي شريط الدفع مع شريط التحاليل
        // تحته على خطٍّ رأسيٍّ واحد — شبكة لا سطوراً متناثرة.
        SizedBox(
          width: 118,
          child: Text(
            'طريقة الدفع',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: BrandColors.brandText,
            ),
          ),
        ),
        SegmentedButton<String>(
          key: const Key('rec-payment-seg'),
          style: segStyle,
          showSelectedIcon: false,
          segments: [
            for (final p in segPays) ButtonSegment(value: p, label: Text(p)),
          ],
          selected: {paySelected},
          onSelectionChanged: (s) => setState(() => payment = s.first),
        ),
        const SizedBox(width: 10),
        debtToggle,
        const SizedBox(width: 10),
        // م167/ج — «التحاليل الثلاثية» رقاقة بارزة بجانب «دين» (كانت
        // سطراً صغيراً معزولاً وهي ميزة أساسية — ملاحظة المالك).
        if (widget.editEntry == null && triAnalysesEnabled(config))
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: hasAnalysis
                  ? BrandColors.green.withValues(alpha: .10)
                  : BrandColors.surface2,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hasAnalysis
                    ? BrandColors.green.withValues(alpha: .50)
                    : BrandColors.line,
              ),
            ),
            child: _analToggle(config),
          ),
        const Spacer(),
        // م167 — رقاقة المعلومات الطبية هنا (كانت يتيمةً بسطر العنوان)؛
        // تنكمش بأمان في العروض الضيقة بدل الفيضان.
        Flexible(
          child: FittedBox(fit: BoxFit.scaleDown, child: medicalChip),
        ),
      ],
    );

    // صفّ الدين — حقل الدفعة الأولى وحده: مسمّاه يحمل الطريقة المختارة
    // (لا شريط كاش/تحويل مكرر)، وعرضه موزون لا يبتلع السطر.
    final debtRow = Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('rec-firstpay'),
            controller: firstPayCtl,
            style: const TextStyle(fontSize: 14),
            keyboardType: TextInputType.number,
            decoration: ddec(
              'الدفعة الأولى (${segPays.contains(payment) ? payment : segPays.first})',
              hint: '0',
            ),
          ),
        ),
        const Spacer(),
      ],
    );

    // قسم التركيبات — صفّا إدخالٍ كثيفان + سطرُ معاينةٍ واحد.
    // م146/و — بلا إطار: تظليلٌ خفيف يجمّع الحقول بصرياً (تقليل الصناديق).
    final prosSection = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: BrandColors.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: const Key('rec-labname'),
                  initialValue: labName.isEmpty ? null : labName,
                  decoration: ddec('المختبر'),
                  items: [
                    for (final l in labsList(config))
                      DropdownMenuItem(value: l, child: Text(l)),
                  ],
                  onChanged: (v) => setState(() => labName = v ?? ''),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: const Key('rec-prostype'),
                  initialValue: prosType.isEmpty ? null : prosType,
                  decoration: ddec('نوع التركيبة'),
                  items: [
                    // م162 — أنواع المختبر المختار وحده.
                    for (final t in labTypesFor(config, labName))
                      DropdownMenuItem(
                        value: '${t['name']}',
                        child: Text('${t['name']}'),
                      ),
                  ],
                  onChanged: (v) {
                    prosType = v ?? '';
                    _onProsTypeChange(labTypesFor(config, labName));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('rec-prosunits'),
                  controller: prosUnitsCtl,
                  style: const TextStyle(fontSize: 14),
                  keyboardType: TextInputType.number,
                  decoration: ddec('عدد الواحدات'),
                  onChanged: (_) => _onUnitsChange(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: const Key('rec-prosunitprice'),
                  controller: prosUnitPriceCtl,
                  style: const TextStyle(fontSize: 14),
                  keyboardType: TextInputType.number,
                  decoration: ddec('سعر الوحدة'),
                  onChanged: (_) => _onUnitsChange(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  key: const Key('rec-lab'),
                  controller: labValueCtl,
                  style: const TextStyle(fontSize: 14),
                  keyboardType: TextInputType.number,
                  decoration: ddec('قيمة المعمل'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // المعاينة الحية سطرٌ واحد بثلاث خلايا متباعدة (كانت ثلاثة أسطر).
          Row(
            children: [
              Expanded(
                child: _previewRow(
                  'صافي الربح:',
                  n(prosNet),
                  BrandColors.goldDark,
                  key: const Key('pros-net'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _previewRow(
                  'الطبيب (${prosPctLive.toStringAsFixed(0)}%):',
                  n(prosDocShare),
                  const Color(0xFF065F46),
                  key: const Key('pros-doc'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _previewRow(
                  'العيادة (${(100 - prosPctLive).toStringAsFixed(0)}%):',
                  n(prosClinShare),
                  const Color(0xFF047857),
                  key: const Key('pros-clin'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final notesField = TextField(
      key: const Key('rec-notes'),
      controller: notesCtl,
      style: const TextStyle(fontSize: 14),
      maxLines: 2,
      minLines: 1,
      decoration: ddec('معلومات مختصرة', hint: 'اختياري'),
    );

    // م167 — زر الحفظ بنفس ارتفاع الحقول وزواياها (نظام واحد).
    final saveBtn = FilledButton.icon(
      key: const Key('rec-save'),
      onPressed: _save,
      style: FilledButton.styleFrom(
        backgroundColor: BrandColors.brand600,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.check_rounded, size: 19),
      label: Text(
        widget.editEntry != null ? 'حفظ التعديل' : 'حفظ الزيارة',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );

    // ── عنوان قسمٍ صغير موحد ──
    Widget colTitle(IconData icon, String text, {bool pad = true}) => Padding(
      padding: EdgeInsets.only(bottom: pad ? 8 : 0),
      child: Row(
        children: [
          Icon(icon, size: 15, color: BrandColors.brandIcon),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: BrandColors.brandText,
              ),
            ),
          ),
        ],
      ),
    );

    // فاصل قسمٍ رقيق — إيقاعٌ بصري موحد بين الأقسام.
    Widget sectionGap() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        height: 1,
        color: BrandColors.line.withValues(alpha: .45),
      ),
    );

    // توسعةٌ ناعمة: تنمو وتنكمش بلا قفزات (طلب المالك — لا تشويه عند
    // التوسيع). AnimatedSize يتكفل بالانتقال، والمحتوى يظهر أو يختفي.
    Widget smooth(bool show, Widget child) => AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: show
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: child,
            )
          : const SizedBox(width: double.infinity),
    );

    // ═══ م146 «عقد التصميم د» — عمودٌ واحدٌ مقسّم داخل اللوح الجانبي ═══
    // الميزانية الرأسية مضبوطة لأقصر شاشةٍ مكتبيةٍ شائعة (‎768) بلا تمرير
    // حتى مع فتح التركيبات والدين والتحاليل معاً؛ وSingleChildScrollView
    // في اللوح المضيف حارسُ طوارئ للشاشات الأقصر فحسب.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 1) هوية المريض — شبكة أرباع متساوية تماماً (م167):
        // التاريخ | العيادة | اسم المريض | رقم الهاتف ──
        colTitle(Icons.person_rounded, 'هوية المريض'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: dateField),
            const SizedBox(width: 12),
            Expanded(child: clinicField),
            const SizedBox(width: 12),
            Expanded(child: nameField),
            const SizedBox(width: 12),
            Expanded(child: phoneField),
          ],
        ),
        if (showPhone2) ...[const SizedBox(height: 8), phone2Row],
        if (suggestions.isNotEmpty) suggestionsPanel,
        sectionGap(),

        // ── 2) المعالجة والقيمة (الرقاقة انتقلت لشريط الدفع — م167) ──
        colTitle(Icons.medical_services_rounded, 'المعالجة والقيمة'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // حقل المعالجة وبجانبه زر تحديد الأسنان الأيقوني الصغير.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: serviceField),
                  const SizedBox(width: 8),
                  teethIconBtn,
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: amountField),
          ],
        ),
        smooth(pros, prosSection),
        sectionGap(),

        // ── 3) الدفع ──
        paySegmented,
        smooth(isDebt, debtRow),
        // م167/ج — الصحُّ انتقل لشريط الدفع؛ يبقى هنا شريطُ دفعِ
        // التحليل وحده حين تكون الميزة مفعّلة ومؤشَّرة.
        if (widget.editEntry == null && triAnalysesEnabled(config))
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  if (hasAnalysis) ...[
                    SizedBox(
                      width: 118,
                      child: Text(
                        'دفع التحليل',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.brandText,
                        ),
                      ),
                    ),
                    SegmentedButton<String>(
                      key: const Key('rec-analysis-pay'),
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: BrandColors.surface2,
                        foregroundColor: BrandColors.mut,
                        selectedBackgroundColor: BrandColors.green,
                        selectedForegroundColor: Colors.white,
                        side: BorderSide(
                          color: BrandColors.green.withValues(alpha: .40),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                      ),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'كاش', label: Text('كاش')),
                        ButtonSegment(value: 'تحويل', label: Text('تحويل')),
                      ],
                      selected: {analysisPay},
                      onSelectionChanged: (s) =>
                          setState(() => analysisPay = s.first),
                    ),
                  ],
                ],
              ),
            ),
          ),
        sectionGap(),

        // ── 4) معلومات مختصرة + الحفظ — ارتفاعان متطابقان (م167) ──
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: notesField),
            const SizedBox(width: 12),
            SizedBox(width: 158, height: 46, child: saveBtn),
          ],
        ),
      ],
    );
  }

  /// م94 — غلاف البطاقة: في المضغوط (ورقة الإدخال) تُرسم الحقول على سطح
  /// الورقة مباشرة بلا بطاقة ولا حشوة مزدوجة (توأم الزيارة السريعة)،
  /// وفي الشاشة الكاملة تبقى البطاقة كما كانت.
  Widget _maybeCard({required bool compact, required Widget child}) => compact
      ? child
      : Card(
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        );

  /// نظام «التحاليل الثلاثية» — علامة صحٍّ + عنوان «التحاليل الثلاثية» بجانب
  /// مفتاح «دين». لا يظهر إلا في وضع الإنشاء (editEntry == null) وحين
  /// الميزة مفعّلة من الإعدادات — كان يظهر دائماً حتى في وضع التعديل حيث
  /// تُتجاهل قيمه صامتاً (خطأ مؤكد). الافتراض عند التفعيل: طريقة الدفع
  /// من دفع الزيارة إن كانت كاش/تحويل وإلا كاش.
  Widget _analToggle(JMap config) {
    // يُخفى في وضع التعديل أو حين الميزة معطّلة.
    if (widget.editEntry != null || !triAnalysesEnabled(config)) {
      return const SizedBox.shrink();
    }
    // م167/ج — مكوّن بارز بوزن «دين»: صحٌّ أكبر وخطٌّ أوضح (كان يبدو
    // إضافةً هامشية وهو ميزة أساسية — ملاحظة المالك).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          height: 26,
          child: Checkbox(
            key: const Key('rec-analysis-toggle'),
            value: hasAnalysis,
            activeColor: BrandColors.green,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => setState(() {
              hasAnalysis = v ?? false;
              if (hasAnalysis) {
                analysisPay = (payment == 'كاش' || payment == 'تحويل')
                    ? payment
                    : 'كاش';
              }
            }),
          ),
        ),
        const SizedBox(width: 5),
        Text('التحاليل الثلاثية',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: hasAnalysis ? BrandColors.green : BrandColors.mut,
            )),
      ],
    );
  }

  /// نظام «التحاليل الثلاثية» — منطقة مبسّطة: قائمة طريقة الدفع فقط.
  /// الاسم والسعر ثابتان من الإعدادات — لا قائمة أسماء ولا حقل سعر.
  Widget _analysisSection({
    required String keyPrefix,
    // م146 — الوضع الكثيف للوح المكتبي: حشوة أصغر وارتفاعٌ طبيعي.
    bool dense = false,
  }) {
    return Container(
      padding: EdgeInsets.all(dense ? 8 : 11),
      decoration: BoxDecoration(
        color: BrandColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BrandColors.green.withValues(alpha: .35)),
      ),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        key: Key('$keyPrefix-analysis-pay'),
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

  /// مفتاح تبديل مصغّر بنمط iOS (المسار الفاتح والإبهام الأبيض الكبير).
  Widget _miniSwitch({
    required Key key,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return Transform.scale(
      scale: .78,
      alignment: AlignmentDirectional.centerStart,
      child: Switch(
        key: key,
        value: value,
        onChanged: onChanged,
        activeTrackColor: BrandColors.brand600,
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        inactiveTrackColor: BrandColors.faint2.withValues(alpha: .25),
        trackOutlineColor: WidgetStatePropertyAll(BrandColors.line),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _todayCell({
    required Key key,
    required String value,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: BrandColors.line.withValues(alpha: .35),
                width: .5,
              ),
            ),
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  // الفارغ «—» ذهبي كما الأصل.
                  color: value == '—'
                      ? BrandColors.goldDark
                      : (color ?? BrandColors.brandText),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: (color ?? BrandColors.brandText).withValues(
                    alpha: .72,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _previewRow(
    String label,
    String value,
    Color color, {
    required Key key,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 11.5, color: BrandColors.mut),
            ),
          ),
          Text(
            value,
            key: key,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ═══ لوحات تفصيل العدادات ═══

  void _openSheet(String kind) {
    final repos = ref.read(reposProvider);
    final records = repos.records.getAll();
    final prosthetics = repos.prosthetics.getAll();
    final debts = repos.debts.getAll();
    final cur = ref.read(currencyProvider);
    final n = formatNumber;

    // م98 — كشف الدخل صار «كشفَ حساب» بمدى تاريخي وفلاتر — ودجةُ حالةٍ
    // مستقلة (تاريخا من/إلى + فلترا العيادة والدفع)، والافتراض اليوم
    // فيبقى فتحُه المعتاد «دخل اليوم» كما كان حرفياً.
    if (kind == 'income') {
      final cfg = ref.read(appConfigProvider);
      final clinics = [
        if (cfg['clinics'] is List)
          for (final c in cfg['clinics'] as List) '$c',
      ];
      final payments = [
        if (cfg['payments'] is List)
          for (final p in cfg['payments'] as List) '$p',
      ];
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: BrandColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => _IncomeStatementSheet(
          records: records,
          prosthetics: prosthetics,
          clinics: clinics,
          payments: payments,
          currency: cur,
        ),
      );
      return;
    }

    final title = kind == 'patients' ? 'مرضى اليوم' : 'دين اليوم';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrandColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        Widget clinicHeader(String clinic) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Row(
            children: [
              Icon(
                Icons.local_hospital_rounded,
                size: 14,
                color: BrandColors.brandIcon,
              ),
              const SizedBox(width: 5),
              Text(
                clinic,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: BrandColors.brandText,
                ),
              ),
            ],
          ),
        );

        Widget rowCard(Widget child) => Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: BrandColors.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BrandColors.line),
          ),
          child: child,
        );

        final children = <Widget>[];
        if (kind == 'patients') {
          final groups = todayPatientsByClinic(records, prosthetics);
          if (groups.isEmpty) {
            children.add(_sheetEmpty('لا مرضى اليوم'));
          }
          for (final g in groups) {
            children.add(clinicHeader(g.clinic));
            for (final p in g.patients) {
              children.add(
                rowCard(
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (p.services.isNotEmpty)
                              Text(
                                p.services.join('، '),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: BrandColors.mut2,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${p.visits} زيارة',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: BrandColors.mut,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          }
        } else {
          final groups = todayDebtByClinic(debts);
          if (groups.isEmpty) {
            children.add(_sheetEmpty('لا ديون اليوم 🎉'));
          }
          for (final g in groups) {
            children.add(clinicHeader(g.clinic));
            for (final p in g.patients) {
              children.add(
                rowCard(
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${p.service.isNotEmpty ? '${p.service} · ' : ''}'
                              'الإجمالي ${n(p.total)} · المدفوع ${n(p.paid)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: BrandColors.mut2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${n(p.remaining)} $cur',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'إجمالي ${g.clinic}',
                        style: TextStyle(fontSize: 11, color: BrandColors.mut),
                      ),
                    ),
                    Text(
                      '${n(g.total)} $cur',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.red,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BrandColors.faint2,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      kind == 'patients'
                          ? Icons.people_rounded
                          : kind == 'income'
                          ? Icons.credit_card_rounded
                          : Icons.error_outline_rounded,
                      size: 17,
                      color: kind == 'debt'
                          ? BrandColors.red
                          : BrandColors.brandIcon,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        key: Key('sheet-$kind'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sheetEmpty(String msg) => Padding(
    padding: const EdgeInsets.all(18),
    child: Center(
      child: Text(msg, style: TextStyle(fontSize: 12, color: BrandColors.mut2)),
    ),
  );
}

/// ============================================================================
///  م98 — «كشف الحساب»: كشف الدخل بمدى تاريخي وفلاتر
/// ============================================================================
///
///  تطوير لوحة «دخل اليوم» بطلب المالك الحرفي:
///    ١) الأحدث إضافةً يتصدّر دائماً (فرز incomeByClinicRange على createdAt).
///    ٢) فلترة بالعيادة وطريقة الدفع (الكل افتراضاً، ويتراكبان).
///    ٣) مدى تاريخي «من/إلى» بتقويمَين (الأقصى اليوم) — الافتراض
///       من=إلى=اليوم فيبقى الفتح المعتاد «دخل اليوم» بعينه، ومدُّ المدى
///       يقلب العنوان إلى «كشف حساب من س إلى ص» ويعرض تاريخ كل صف.
///
///  الإجماليات (لكل عيادة والكلي) تتبع المدى والفلاتر معاً — مفتاح
///  الإجمالي `sheet-income-total` القديم بعينه فلا يمسّ اختبار م23.
class _IncomeStatementSheet extends StatefulWidget {
  const _IncomeStatementSheet({
    required this.records,
    required this.prosthetics,
    required this.clinics,
    required this.payments,
    required this.currency,
  });

  final List<Map<String, Object?>> records;
  final List<Map<String, Object?>> prosthetics;
  final List<String> clinics;
  final List<String> payments;
  final String currency;

  @override
  State<_IncomeStatementSheet> createState() => _IncomeStatementSheetState();
}

class _IncomeStatementSheetState extends State<_IncomeStatementSheet> {
  late String _from;
  late String _to;
  String? _clinic; // null = الكل
  String? _payment; // null = الكل

  @override
  void initState() {
    super.initState();
    _from = getCurrentDate();
    _to = _from;
  }

  bool get _isToday => _from == _to && _from == getCurrentDate();
  bool get _multiDay => _from != _to;

  String get _title => _isToday
      ? 'دخل اليوم'
      : _multiDay
      ? 'كشف حساب من $_from إلى $_to'
      : 'كشف حساب يوم $_from';

  DateTime _parse(String d) => DateTime.parse(d);
  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _parse(isFrom ? _from : _to),
      firstDate: DateTime(2020),
      lastDate: now,
      locale: const Locale('ar'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _from = _fmt(picked);
        // «إلى» لا تسبق «من».
        if (_to.compareTo(_from) < 0) _to = _from;
      } else {
        _to = _fmt(picked);
        if (_to.compareTo(_from) < 0) _from = _to;
      }
    });
  }

  Widget _dateChip({
    required Key key,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) => Expanded(
    child: InkWell(
      key: key,
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: BrandColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: BrandColors.line),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_month_rounded,
              size: 14,
              color: BrandColors.brandIcon,
            ),
            const SizedBox(width: 5),
            Text(
              '$label: ',
              style: TextStyle(fontSize: 11, color: BrandColors.mut2),
            ),
            Expanded(
              child: Text(
                value,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _filterDrop({
    required Key key,
    required String label,
    required String? value,
    required List<String> options,
    required void Function(String?) onChanged,
  }) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: BrandColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BrandColors.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          key: key,
          value: value,
          isExpanded: true,
          isDense: true,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: BrandColors.ink,
          ),
          hint: Text(
            '$label: الكل',
            style: TextStyle(fontSize: 11.5, color: BrandColors.mut2),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                '$label: الكل',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            for (final o in options)
              DropdownMenuItem<String?>(
                value: o,
                child: Text(
                  o,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    final cur = widget.currency;
    final groups = incomeByClinicRange(
      widget.records,
      widget.prosthetics,
      from: _from,
      to: _to,
      clinic: _clinic,
      payment: _payment,
    );
    num grand = 0;
    for (final g in groups) {
      grand += g.total;
    }

    // خيارات الفلاتر: عيادات الإعدادات + «بدون عيادة»، وطرق الدفع +
    // «دين» (دفعات الديون تحمل هذه القيمة في صفوف السجلات).
    final clinicOptions = [...widget.clinics, kNoClinic];
    final paymentOptions = [
      ...widget.payments,
      if (!widget.payments.contains('دين')) 'دين',
    ];

    Widget clinicHeader(String clinic) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.local_hospital_rounded,
            size: 14,
            color: BrandColors.brandIcon,
          ),
          const SizedBox(width: 5),
          Text(
            clinic,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: BrandColors.brandText,
            ),
          ),
        ],
      ),
    );

    Widget rowCard(Widget child) => Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: BrandColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BrandColors.line),
      ),
      child: child,
    );

    final children = <Widget>[];
    if (groups.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(18),
          child: Center(
            child: Text(
              _isToday ? 'لا دخل اليوم' : 'لا دخل في المدى المحدد',
              style: TextStyle(fontSize: 12, color: BrandColors.mut2),
            ),
          ),
        ),
      );
    }
    for (final g in groups) {
      children.add(clinicHeader(g.clinic));
      for (final p in g.patients) {
        final sub = [
          if (p.service.isNotEmpty) p.service,
          if (p.payment.isNotEmpty) p.payment,
          if (_multiDay) p.date,
        ].join(' · ');
        children.add(
          rowCard(
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (sub.isNotEmpty)
                        Text(
                          sub,
                          style: TextStyle(
                            fontSize: 11,
                            color: BrandColors.mut2,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${n(p.amount)} $cur',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.goldDark,
                  ),
                ),
              ],
            ),
          ),
        );
      }
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'إجمالي ${g.clinic}',
                  style: TextStyle(fontSize: 11, color: BrandColors.mut),
                ),
              ),
              Text(
                '${n(g.total)} $cur',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (groups.isNotEmpty) {
      children.add(const Divider(height: 16));
      children.add(
        Row(
          children: [
            const Expanded(
              child: Text(
                'الإجمالي',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${n(grand)} $cur',
              key: const Key('sheet-income-total'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: BrandColors.goldDark,
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: BrandColors.faint2,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.credit_card_rounded,
                  size: 17,
                  color: BrandColors.brandIcon,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _title,
                    key: const Key('sheet-income'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            // ── المدى التاريخي: من / إلى ──
            Row(
              children: [
                _dateChip(
                  key: const Key('income-range-from'),
                  label: 'من',
                  value: _from,
                  onTap: () => _pick(isFrom: true),
                ),
                const SizedBox(width: 8),
                _dateChip(
                  key: const Key('income-range-to'),
                  label: 'إلى',
                  value: _to,
                  onTap: () => _pick(isFrom: false),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // ── الفلترة: العيادة / طريقة الدفع ──
            Row(
              children: [
                _filterDrop(
                  key: const Key('income-filter-clinic'),
                  label: 'العيادة',
                  value: _clinic,
                  options: clinicOptions,
                  onChanged: (v) => setState(() => _clinic = v),
                ),
                const SizedBox(width: 8),
                _filterDrop(
                  key: const Key('income-filter-payment'),
                  label: 'الدفع',
                  value: _payment,
                  options: paymentOptions,
                  onChanged: (v) => setState(() => _payment = v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
