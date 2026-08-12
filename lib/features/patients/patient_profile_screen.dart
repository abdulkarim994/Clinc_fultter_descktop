/// ملف المريض الشامل — نقل جوهر PatientProfile.vue فوق المستودعات المنقولة:
/// ترويسة بإحصاءات محسوبة من السجلات الفعلية، قائمة السجلات والتركيبات،
/// الديون مع سداد قسط (المصدر الوحيد للحقيقة: مصفوفة الأقساط + إعادة اشتقاق
/// المجاميع بنفس recomputeDebts المنقول)، والخطة العلاجية المخزنة في
/// config.treatmentPlans (تُدمج بنيوياً عبر المزامنة).
library;

import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/data_revision.dart' show bumpDataRevision;
import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/shiny_fab.dart' show ShinyFab;
import '../desktop/desktop_gate.dart' show isDesktopUi;
import '../desktop/widgets/desktop_dialogs.dart' show showDesktopDialog;
import '../../core/utils/js_compat.dart';
import '../../data/rates/rate_snapshot.dart' show resolveDoctorPct;
import '../../core/widgets/double_confirm.dart';
import '../archive/month_stats.dart' show byDateNewestFirst;
import '../finance/installment_dialog.dart'
    show showDebtPaymentsDialog, showInstallmentDialog;
import '../finance/finance_screen.dart' show financeRevProvider;
import 'clinic_scope.dart' show medicalScopedRead, medicalScopedWrite;
import 'record_row_logic.dart';
import 'treatment_plan_store.dart';
import '../print/print_service.dart';
import '../print/reports.dart' show patientFilePdf, pdfLogoBytes;
import '../print/treatment_tables.dart' show formatNumber;
import '../records/tooth_report_dialog.dart'
    show showToothReportDialog, activeTeeth, teethKeysOf;
import 'audit_log.dart' show appendAudit, hasAudit;
import 'audit_trail.dart' show AuditAction, recordAudit;
import '../xrays/xray_camera_screen.dart' show XrayCameraScreen;
import '../xrays/xray_section.dart';
import '../xrays/xray_store.dart' show xrayKeysFor;
import '../appointments/appointments_tab.dart'
    show apptBookDraftProvider, apptGoDayProvider;
import '../shell/app_shell.dart' show activeTabProvider;
import '../appointments/appt_lifecycle.dart'
    show apptStatusColor, apptStatusLabel, patientUpcomingAppointments;
import '../appointments/appointments_logic.dart' show to12h;
import '../desktop/desktop_shell.dart' show desktopTabProvider;
import '../records/analysis_actions.dart' show promptAddAnalysisToVisit;
import '../records/day_close_store.dart' show confirmClosedDayWrite;
import '../records/income_day_dialog.dart' show askIncomeDay;
import '../records/medical_info_dialog.dart';
import '../records/tooth_notation.dart' show ToothLabel;
import '../records/tooth_label_widget.dart';
import '../records/tooth_summary.dart';
import 'patients_logic.dart'
    show
        PatientAgg,
        TreatmentCardGroup,
        distinctIdentityPhones,
        editPatientCascade,
        patientForClinic,
        rowMatchesIdentity,
        treatmentCards;
import 'patients_tab.dart'
    show addVisitDraftProvider, homeJumpProvider, patientsRevProvider;
import 'profile_actions.dart'
    show deleteEntryCascade, deletePatientData, updateRecAmount;
import 'quick_info_dialog.dart' show showQuickInfoDialog;
import 'quick_visit_sheet.dart' show showQuickVisitSheet;
import '../settings/analyses3.dart' show triAnalysesEnabled;
import '../staff/staff_gate.dart' show gateStaff, staffAllowed;

typedef JMap = Map<String, Object?>;

class PatientProfileScreen extends ConsumerStatefulWidget {
  const PatientProfileScreen({
    super.key,
    required this.patientName,
    this.clinic = '',
    this.identity = '',
    this.autoPrint = false,
  });

  final String patientName;

  /// عزل العيادة — التجميعة والصفوف تقتصر عليها عند تمريرها (توأم
  /// المسار المتداخل clinic/patient في الأصل).
  final String clinic;

  /// م90 — الهوية الفرعية عند تشابه الأسماء داخل العيادة الواحدة:
  /// `p:<هاتف>` أو `none` (من التجميعة المنقسمة)، و'' = السلوك القائم
  /// حرفياً (كل الصفوف). فعليّتها تُشتق حيّاً في الحالة — لو زال الانقسام
  /// (وُحِّدت الهواتف بعد فتح الشاشة) تُهمَل فلا يختفي صفٌّ من الملف.
  final String identity;

  /// فتح الطباعة مباشرة (توأم query print=1).
  final bool autoPrint;

  @override
  ConsumerState<PatientProfileScreen> createState() =>
      _PatientProfileScreenState();
}

class _PatientProfileScreenState extends ConsumerState<PatientProfileScreen> {
  String get name => widget.patientName;
  String get clinic => widget.clinic;

  /// م172 — متحكم قسم الأشعة: يربط زرَّي «رفع/تصوير» العائمين بمساره.
  final _xrayCtl = XraySectionController();

  /// قسم الملف النشط — activeSection (visits|debts|xrays|plan).
  String activeSection = 'visits';
  // م65 — بطاقة الملخص قابلة للطي (مطوية افتراضياً — توفير مساحة):
  // الشريط المضغوط يعرض خلاصة سطر واحد، واللمس يوسع للبطاقة الكاملة.
  bool summaryOpen = false;

  bool _inClinic(JMap r) => clinic.isEmpty || r['clinic'] == clinic;

  List<JMap> get _recordsRaw => [
    for (final r in ref.read(reposProvider).records.getByPatient(name))
      if (_inClinic(r)) r,
  ];

  List<JMap> get _prosRaw => [
    for (final r in ref.read(reposProvider).prosthetics.getAll())
      if ('${r['patient_name'] ?? r['name'] ?? ''}' == name && _inClinic(r)) r,
  ];

  List<JMap> get _debtsRaw => [
    for (final d in ref.read(reposProvider).debts.getDebtsByPatient(name))
      if (_inClinic(d)) d,
  ];

  /// م90 — الهوية الفعلية الآن: تُعتمد هوية الفتح ما دامت مجموعة
  /// (اسم|عيادة) منقسمة فعلاً (هاتفان مختلفان فأكثر بين كل صفوفها)؛ وإلا
  /// أُهملت — فتعديلُ بياناتٍ وحَّد الهواتف لا يُخفي صفوفاً من الملف.
  String _identityNow() {
    if (widget.identity.isEmpty) return '';
    final rows = [..._recordsRaw, ..._prosRaw, ..._debtsRaw];
    return distinctIdentityPhones(rows).length >= 2 ? widget.identity : '';
  }

  List<JMap> _byIdentity(List<JMap> rows) {
    final id = _identityNow();
    if (id.isEmpty) return rows;
    return [
      for (final r in rows)
        if (rowMatchesIdentity(r, id)) r,
    ];
  }

  /// م90 — صفوف الملف الثلاثة بعد ترشيح الهوية: كلُّ ما تحتها (الإحصاءات،
  /// الأقسام، الطباعة) يرى صفوف هذه الهوية وحدها تلقائياً.
  List<JMap> get _records => _byIdentity(_recordsRaw);

  List<JMap> get _pros => _byIdentity(_prosRaw);

  List<JMap> get _debts => _byIdentity(_debtsRaw);

  // v55 — بطاقات دين الملف مطوية افتراضياً (نمط v54).
  final Set<String> expandedProfDebts = {};

  @override
  void initState() {
    super.initState();
    // م79 — تسجيل الاطّلاع. «من اطّلع على ملف هذا المريض؟» هو أكثر ما
    // يُسأل عنه في تحقيق تسريب بيانات صحية، ولم يكن يُسجَّل إطلاقاً.
    //
    // يُسجَّل بعد الإطار الأول لا داخل initState: الكتابة على القاعدة
    // أثناء بناء الشجرة تُخالف انضباط هذا المشروع، والتأخير غير محسوس.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      recordAudit(
        ref.read(localDbProvider),
        action: AuditAction.viewPatient,
        entity: 'patients',
        // **هنا يُخزَّن مفتاح المريض صراحةً — وهو الاستثناء المقصود.**
        //
        // القاعدة في هذا المشروع ألّا تدخل بيانات المرضى السجلّات. لكن
        // سجلّ التدقيق حالة معاكسة: سجلٌّ يقول «اطّلع أحدٌ على مريضٍ ما»
        // بلا تحديد **عديم القيمة تماماً** — والسؤال الذي وُجد لأجله هو
        // «من اطّلع على ملف فلان؟». فإخفاء المعرّف هنا يُفرغ الميزة.
        //
        // ولذلك لا يمرّ [entityId] عبر الحاجب، بخلاف [detail]. والحماية
        // تأتي من مكان آخر: الجدول مقيَّد بالمالك في RLS، وسياسته إدراج
        // فقط، فلا يقرؤه غير صاحبه ولا يعيد أحد كتابته.
        entityId: widget.patientName,
        detail: {
          'clinic': widget.clinic,
          'autoPrint': widget.autoPrint,
          // م90 — تمييز السميّين في سجل الاطلاع أيضاً.
          if (widget.identity.isNotEmpty) 'identity': widget.identity,
        },
      );
    });
    if (widget.autoPrint) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _printPatientSummary(),
      );
    }
  }

  /// للاستدعاء من build: من الإعدادات المُراقَبة (لا قراءة موفّر مبطَل
  /// أثناء البناء). وللاستدعاء من الأحداث: عبر ref.read (آمن في callbacks).
  /// v29 — المصدر الوحيد للمراحل: مخزن «كل مرحلة صف مستقل». الاستيراد
  /// من الإعدادات القديمة يجري مرة واحدة عند أول قراءة (بمعرّفاتها).
  TreatmentPlanStore get _planStore =>
      TreatmentPlanStore(ref.read(reposProvider).settings);

  List<JMap> _stagesFrom(Map<String, Object?> cfg) => [
    // م97 — مفتاح الهوية (عيادة + هاتف): عزل الخطة عن مشابهي الاسم.
    for (final st in _planStore.read(
      name,
      clinic,
      phone: _medPhone(),
      legacyConfig: cfg,
    ))
      st.toJson(),
  ];

  /// نبضة إعادة قراءة بعد كتابة صف مرحلة.
  void _planChanged() {
    ref.read(configRevProvider.notifier).state++;
    setState(() {});
  }

  /// الدين المرتبط بسجل/تركيبة — _linkedDebtOf حرفياً.
  JMap? _linkedDebtOf(JMap rec) {
    final debts = ref.read(reposProvider).debts.getAll();
    final debtId = jsOr(rec['debtId'], rec['_debtId']);
    if (jsTruthy(debtId)) {
      for (final d in debts) {
        if (d['id'] == debtId) return d;
      }
      return null;
    }
    for (final d in debts) {
      if (d['recordId'] == rec['id'] || d['prostheticId'] == rec['id']) {
        return d;
      }
    }
    return null;
  }

  /// القراءة القانونية للأسنان — _resolveTeeth: أسنان الدين المرتبط تفوز،
  /// ثم تقرير الصف نفسه (بشكليه: مصفوفة أو {entries, meta}).
  (List<JMap>, JMap) _resolveTeeth(JMap rec) {
    List<JMap> asList(Object? v) => v is List
        ? [
            for (final e in v)
              if (e is Map) Map<String, Object?>.from(e),
          ]
        : const [];
    JMap asMap(Object? v) => v is Map ? Map<String, Object?>.from(v) : const {};

    final debt = _linkedDebtOf(rec);
    if (debt != null) {
      final dr = debt['report'];
      if (dr is List && dr.isNotEmpty) {
        return (asList(dr), asMap(debt['reportMeta']));
      }
      if (dr is Map && asList(dr['entries']).isNotEmpty) {
        return (
          asList(dr['entries']),
          asMap(jsOr(dr['meta'], debt['reportMeta'])),
        );
      }
    }
    final r = rec['report'];
    if (r is List && r.isNotEmpty) {
      return (asList(r), asMap(rec['reportMeta']));
    }
    if (r is Map && asList(r['entries']).isNotEmpty) {
      return (asList(r['entries']), asMap(jsOr(r['meta'], rec['reportMeta'])));
    }
    // م103 — ملاذ أخير شافٍ للبيانات القائمة: صف «دفعة» ظاهرٌ في الملف
    // بينما أسنانُ معالجته محفوظة على صف أصل الدين **المخفي** (isDebt) —
    // ديونٌ أُنشئت قبل نسخة التقرير على الدين. نصعد عبر debt.recordId/
    // prostheticId إلى الأصل ونقرأ تقريره. عرضٌ محض — لا كتابة.
    if (debt != null) {
      final originId =
          '${jsOr(debt['recordId'], jsOr(debt['prostheticId'], ''))}';
      if (originId.isNotEmpty && originId != '${rec['id']}') {
        final repos = ref.read(reposProvider);
        final origin =
            repos.records.getById(originId) ??
            repos.prosthetics.getById(originId);
        final or = origin?['report'];
        if (or is List && or.isNotEmpty) {
          return (asList(or), asMap(origin!['reportMeta']));
        }
        if (or is Map && asList(or['entries']).isNotEmpty) {
          return (
            asList(or['entries']),
            asMap(jsOr(or['meta'], origin!['reportMeta'])),
          );
        }
      }
    }
    return (const [], const {});
  }

  /// مفاتيح أسنان صف للعرض المضغوط.
  /// قائمة الأسنان المهيكلة (رباعي + رقم + وسم لبني) — teethList حرفياً
  /// بلا تكرار. م100/7: العلم p يقرأ وسم `d:'P'` (غيابه = دائم، فالصفوف
  /// القديمة تمرّ كما كانت)، وسنّا الدائم واللبني بنفس الموضع لا يندمجان.
  List<({String q, int n, bool p})> _teethStructured(JMap rec) {
    final (report, _) = _resolveTeeth(rec);
    final seen = <String>{};
    final out = <({String q, int n, bool p})>[];
    for (final e in report) {
      for (final t in activeTeeth(e['teeth'])) {
        final q = '${jsOr(t['q'], 'UR')}';
        final n = jsNumOr0(t['n']).toInt();
        final p = '${t['d'] ?? ''}' == 'P';
        if (seen.add('$q:$n${p ? ':P' : ''}')) out.add((q: q, n: n, p: p));
      }
    }
    return out;
  }

  /// محرر أسنان سجل — openTeethSelector/onTeethConfirm: يحفظ على الصف
  /// (سجل أو تركيبة) وعلى الدين المرتبط (المصدر الوحيد لحقيقة المعالجة)،
  /// تعديل إداري: يختم upsertLocal الساعة والقذارة دون أي حقل نشاط.
  Future<void> _openTeethSelector(JMap rec) async {
    // م127 — تعديل الأسنان المعالجة ضمن صلاحية تعديل السجلات.
    if (!gateStaff(context, 'records.edit')) return;
    final (report, meta) = _resolveTeeth(rec);
    final result = await showToothReportDialog(
      context,
      entries: report,
      meta: meta,
      teethOnly: true,
      patientName: name,
      notation: ref.read(notationSystemProvider),
    );
    if (result == null) return;
    final repos = ref.read(reposProvider);
    final ts = jsIsoNow();
    // م65 — قيد سجل التعديلات لتغيير الأسنان (توأم _saveTeethToRecord):
    // «تحديد الأسنان: N سن ← M سن».
    final oldCount = teethKeysOf(report).length;
    final newCount = teethKeysOf(result.entries).length;
    final patch = {
      'report': result.entries,
      'reportMeta': result.meta,
      'updated_at': ts,
      '_edited': true,
      '_audit': appendAudit(
        rec,
        {'report': 'changed'},
        valueOverrides: {'report': (old: '$oldCount سن', new_: '$newCount سن')},
      ),
    };
    // _saveTeethToRecord — سجل أولاً ثم تركيبة.
    final r = repos.records.getById('${rec['id']}');
    if (r != null) {
      // v31 — كتابة مطابقة للنيّة: تُطبَّق حقول التعديل فقط.
      repos.records.upsertLocal({...r, ...patch}, base: r);
    } else {
      final p = repos.prosthetics.getById('${rec['id']}');
      if (p != null) {
        repos.prosthetics.upsertLocal({...p, ...patch}, base: p);
      }
    }
    // _writeTeethToDebt — نسخة واحدة على الدين المرتبط.
    final debt = _linkedDebtOf(rec);
    if (debt != null) {
      repos.debts.upsertLocal({
        ...debt,
        'report': result.entries,
        'reportMeta': result.meta,
      }, base: debt);
      // م103 — وإن كان الصفُّ المحرَّر بطاقةَ «دفعة» ظاهرة، فالحقيقة
      // الكاملة محفوظة أيضاً على صف أصل الدين المخفي (isDebt/تركيبة
      // دَينية): ننسخ التقرير إليه كذلك فلا تتباعد النسخ الثلاث أبداً
      // (تباعدٌ رُصد فعلاً على الخادم قبل هذا الإصلاح).
      final originId =
          '${jsOr(debt['recordId'], jsOr(debt['prostheticId'], ''))}';
      if (originId.isNotEmpty && originId != '${rec['id']}') {
        final or0 = repos.records.getById(originId);
        if (or0 != null) {
          repos.records.upsertLocal({
            ...or0,
            'report': result.entries,
            'reportMeta': result.meta,
            'updated_at': ts,
          }, base: or0);
        } else {
          final op0 = repos.prosthetics.getById(originId);
          if (op0 != null) {
            repos.prosthetics.upsertLocal({
              ...op0,
              'report': result.entries,
              'reportMeta': result.meta,
              'updated_at': ts,
            }, base: op0);
          }
        }
      }
    }
    setState(() {});
  }

  // v50 — «طباعة تقرير الأسنان» حُذفت نهائياً من قائمة ⋮ بطلب المالك
  // (الدالة وخيار القائمة والاستيراد أُزيلوا؛ بانية التقرير نفسها باقية
  // في مكتبة الطباعة).

  /// م43/v55 — بطاقة الدين داخل الملف بنمط v54 المطوي: العنوان الرئيسي
  /// **اسم المعالجة** (لا اسم المريض — نحن في ملفه أصلاً)، «المتبقي»
  /// الأحمر وزر «دفعة» حاضران دائماً بالرأس، شريط تقدم رفيع دائم،
  /// والتفاصيل (الثلاثي والشريط العريض وسجل الدفعات) بنقرة الرأس.
  Widget _debtCard(JMap d) {
    final id = '${d['id']}';
    final isPaid = d['status'] == 'paid';
    final total = jsNumOr0(jsOr(d['totalAmount'], d['total']));
    final paid = jsNumOr0(d['paidAmount']);
    final remaining = jsNumOr0(d['remaining']);
    final pct = total > 0 ? ((paid / total) * 100).clamp(0, 100).round() : 0;
    final isPros = d['type'] == 'prosthetic';
    final n = formatNumber;
    final expanded = expandedProfDebts.contains(id);

    Widget cell(String label, num v, Color color) => Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10.5, color: BrandColors.mut2)),
        const SizedBox(height: 2),
        Text(
          n(v),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );

    return Container(
      key: Key('debt-card-$id'),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(16),
        // حد ملون بالحالة — rgba(45,212,160,.5) / rgba(255,68,85,.5).
        border: Border.all(
          color: isPaid
              ? const Color.fromRGBO(45, 212, 160, .5)
              : const Color.fromRGBO(255, 68, 85, .5),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(10, 48, 36, .06),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── الرأس المطوي — نقرة تفتح/تطوي ──
          InkWell(
            key: Key('pd-head-$id'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(
              () => expanded
                  ? expandedProfDebts.remove(id)
                  : expandedProfDebts.add(id),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // العنوان الرئيسي: اسم المعالجة.
                            Text(
                              '${jsOr(d['service'], 'دين')}',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFC9A24B),
                              ),
                            ),
                            _statusChip(isPaid, remaining, total, paid),
                            if (isPros)
                              _miniBadge(
                                'تركيبات',
                                const Color(0xFF1B5E47),
                                const Color.fromRGBO(27, 94, 71, .1),
                                const Color.fromRGBO(27, 94, 71, .25),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${d['date'] ?? ''}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: BrandColors.mut2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // المتبقي — أبرز رقم بالبطاقة.
                  Column(
                    children: [
                      Text(
                        'المتبقي',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: BrandColors.mut2,
                        ),
                      ),
                      Text(
                        n(remaining),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  // زر الدفعة السريع — حاضر دائماً بلا توسيع.
                  if (!isPaid)
                    Container(
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: BrandColors.brandGradient,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: Key('pay-$id'),
                          borderRadius: BorderRadius.circular(50),
                          onTap: () => _payInstallment(d),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_circle_outline_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'دفعة',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: BrandColors.mut,
                    ),
                  ),
                  // كبب الخيارات (نفس أفعاله).
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: PopupMenuButton<String>(
                      key: Key('debt-kebab-$id'),
                      tooltip: 'خيارات',
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 17,
                        color: BrandColors.mut2,
                      ),
                      onSelected: (v) {
                        switch (v) {
                          case 'pay':
                            _payInstallment(d);
                          case 'payments':
                            _showDebtPayments(d);
                        }
                      },
                      itemBuilder: (context) => [
                        if (!isPaid)
                          const PopupMenuItem(
                            value: 'pay',
                            child: Text(
                              'تسجيل دفعة',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'payments',
                          child: Text(
                            'سجل الدفعات',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── شريط تقدم رفيع دائم — النسبة تُقرأ وهي مطوية ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                key: Key('debt-progress-$id'),
                value: pct / 100,
                minHeight: 4,
                backgroundColor: const Color.fromRGBO(15, 42, 32, .08),
                color: isPaid
                    ? const Color(0xFF1E7A52)
                    : const Color(0xFFC9A24B),
              ),
            ),
          ),

          // ── التفاصيل الموسعة (بنقرة الرأس) ──
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // شبكة المبالغ الثلاثية.
                  Row(
                    children: [
                      Expanded(
                        child: cell('الإجمالي', total, const Color(0xFFB45309)),
                      ),
                      Expanded(
                        child: cell('المدفوع', paid, const Color(0xFF065F46)),
                      ),
                      Expanded(
                        child: cell(
                          'المتبقي',
                          remaining,
                          const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // شريط التقدم العريض + «X% مسدد».
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      minHeight: 8,
                      backgroundColor: const Color.fromRGBO(15, 42, 32, .08),
                      color: isPaid
                          ? const Color(0xFF1E7A52)
                          : const Color(0xFFC9A24B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      '$pct% مسدد',
                      style: TextStyle(fontSize: 10.5, color: BrandColors.mut2),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // سجل الدفعات.
                  _goldOutlineBtn(
                    key: Key('debt-payments-$id'),
                    label: isPaid ? 'عرض سجل الدفعات' : 'الدفعات',
                    icon: Icons.receipt_long_rounded,
                    expand: true,
                    onTap: () => _showDebtPayments(d),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(bool isPaid, num remaining, num total, num paid) {
    final partial = !isPaid && paid > 0;
    final (bg, fg, border, label) = isPaid
        ? (
            const Color.fromRGBO(45, 212, 160, .12),
            const Color(0xFF1E7A52),
            const Color.fromRGBO(45, 212, 160, .28),
            'مسدد',
          )
        : partial
        ? (
            const Color.fromRGBO(255, 149, 0, .12),
            const Color(0xFFB8860B),
            const Color.fromRGBO(255, 149, 0, .28),
            'جزئي',
          )
        : (
            const Color.fromRGBO(255, 68, 85, .12),
            const Color(0xFFC0392B),
            const Color.fromRGBO(255, 68, 85, .28),
            'غير مسدد',
          );
    return _miniBadge(label, fg, bg, border);
  }

  Widget _miniBadge(String label, Color fg, Color bg, Color border) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      );

  // v55 — _gradientBtn أُزيلت: زر «دفعة» المدمج في رأس البطاقة حل محل
  // زر «تسجيل دفعة» العريض.

  Widget _goldOutlineBtn({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool expand = false,
  }) {
    final btn = Material(
      color: const Color.fromRGBO(201, 162, 75, .08),
      borderRadius: BorderRadius.circular(50),
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: const Color.fromRGBO(201, 162, 75, .3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: const Color(0xFF9C7A2E)),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9C7A2E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }

  /// سجل دفعات الدين — ورقة بأقساطه مرتبة كالأصل.
  /// v34 — سجل الدفعات **الموحّد** (نفس نافذة قسم الديون بالمالية
  /// حرفياً): معلومات الدين + شريط التقدم + دفعات مرقمة + إلغاء دفعة
  /// بنقرتين — كانت النسخة القديمة ورقة عرض فقط بلا حذف.
  void _showDebtPayments(JMap d) async {
    await showDebtPaymentsDialog(
      context,
      ref,
      d,
      onChanged: () {
        bumpDataRevision(ref); // م-إصلاح — نبض موحّد لكل الشاشات.
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() {});
  }

  /// سداد قسط — عبر إجراء confirmInst الموحّد (يحدّث الدين **وينشئ سجل
  /// الدفعة المرتبط** الذي تتغذى عليه الخزينة والأرشيف — إصلاح جولة الترميم).
  /// v33 — نافذة تسجيل الدفعة **الموحّدة** (نفس نافذة قسم الديون
  /// بالمالية حرفياً): التاريخ + طريقة الدفع من إعدادات الحساب + معاينة
  /// التقسيم — كانت النسخة القديمة حقل مبلغ فقط وتثبّت «كاش» بالكود.
  void _payInstallment(JMap debt) async {
    // م119 — تسجيل دفعات الديون صلاحية مستقلة.
    if (!gateStaff(context, 'debts.pay')) return;
    final outcome = await showInstallmentDialog(context, ref, debt);
    if (outcome == null) return;
    bumpDataRevision(ref); // م-إصلاح — نبض موحّد لكل الشاشات المرتبطة.
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome.isFull ? 'تم سداد الدين بالكامل!' : 'تم تسجيل الدفعة',
          ),
        ),
      );
    }
  }

  /// زر واتساب — sendWaTemplate: قوالب الإعدادات بملء {name}/{center}
  /// وإلا فتح المحادثة مباشرة (url_launcher).
  Future<void> _openWhatsApp() async {
    // م-عزل الهوية — الهاتف من مُحلّل الهوية المفتوحة (_knownPhone) لا من
    // patients.getById(name): بعد فصل صف المريض بالمعرّف الهاتفي صار
    // getById(name) يعيد null للتوائم فيتعطّل واتساب. _knownPhone يتبع
    // الهوية المعروضة (كبقية مسارات الهاتف في الملف).
    final phone = _knownPhone().replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا رقم هاتف لهذا المريض')));
      return;
    }
    final cfg = ref.read(appConfigProvider);
    final templates = [
      for (final t in (cfg['waTemplates'] as List? ?? const []))
        if (t is Map && (jsTruthy(t['lbl']) || jsTruthy(t['msg'])))
          Map<String, Object?>.from(t),
    ];
    String fill(Object? msg) => '${msg ?? ''}'
        .replaceAll('{name}', name)
        .replaceAll('{center}', '${cfg['centerName'] ?? ''}')
        .replaceAll('{clinic}', '')
        .replaceAll('{time}', '');
    String? text;
    if (templates.isNotEmpty) {
      final chosen = await showDialog<JMap>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('قالب الرسالة'),
          children: [
            for (final t in templates)
              SimpleDialogOption(
                key: Key('wa-tpl-${t['lbl']}'),
                onPressed: () => Navigator.pop(context, t),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t['lbl'] ?? ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      fill(t['msg']),
                      style: TextStyle(fontSize: 11, color: BrandColors.mut),
                    ),
                  ],
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, {'msg': ''}),
              child: const Text(
                'بلا قالب — فتح المحادثة فقط',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
      if (chosen == null) return;
      text = fill(chosen['msg']);
    }
    final url = (text != null && text.isNotEmpty)
        ? 'https://wa.me/$phone?text=${Uri.encodeComponent(text)}'
        : 'https://wa.me/$phone';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذّر فتح واتساب')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(appConfigProvider); // مُراقب — يعيد البناء نظيفاً
    ref.watch(patientsRevProvider);
    final repos = ref.watch(reposProvider);
    final patient = repos.patients.getById(name);
    final records = _records;
    final pros = _pros;
    final debts = _debts;
    // v55 — المسددة تختفي تلقائياً من قسم الدين وعدّاده (تبقى صفوفها
    // في القاعدة تاريخاً صامتاً فلا تختل الإجماليات ولا سجل الدفعات).
    final activeDebts = [
      for (final d in debts)
        if (d['status'] != 'paid') d,
    ];
    final stages = _stagesFrom(cfg);
    final cur = ref.watch(currencyProvider);
    final n = formatNumber;

    // التجميعة المعزولة بالعيادة — patientForClinic (نفس رياضيات الخريطة).
    // م-عزل الهوية — تُمرَّر الهوية الفعلية الآن فتُرشَّح الصفوف المجمَّعة
    // بها: ترويسةُ الإجمالي/المدفوع/الديون/الزيارات تطابق صفوف الهوية
    // (_records/_pros/_debts) نفسها — إصلاح لقطة المالك 0/0/0.
    final idNow = _identityNow();
    final agg =
        patientForClinic(
          name,
          clinic,
          records: repos.records.getAll(),
          prosthetics: repos.prosthetics.getAll(),
          debts: repos.debts.getAll(),
          identity: idNow,
        ) ??
        PatientAgg(name);
    final cards = treatmentCards(
      patient: agg,
      patientName: name,
      clinic: clinic,
      prosthetics: repos.prosthetics.getAll(),
      debts: repos.debts.getAll(),
      identity: idNow,
    );
    final tpDone = stages.where((st) => st['done'] == true).length;

    // الزيارات — توأم patientRecords حرفياً: القيود بلا **أصل الدين**
    // (filter !isDebt) فلا تظهر قيمة الدين الكاملة في السجلات؛ الدفعات
    // تظهر بمبالغها المدفوعة وحدها (والدين نفسه في قسم الديون). الأحدث
    // أولاً.
    // م29 — الفرز byNewestFirst الحرفي: مفتاح النشاط (_activityAt وإلا
    // زمن التاريخ) ثم كسر التعادل بالمعرّف تنازلياً — فالدفعة الأخيرة
    // دائماً بالأعلى حتى ضمن اليوم نفسه (كان الفرز بسلسلة التاريخ فقط
    // يخلط دفعات اليوم الواحد: «دفعة 2» فوق «دفعة 3»).
    final allEntries =
        [
            ...records.map((r) => ({...r, '_kind': 'r'})),
            ...pros.map((p) => ({...p, '_kind': 'p'})),
          ]
              // نظام «التحاليل» — صف التحليل معزولٌ عن قائمة سجلات الملف
              // (لا يظهر كسجلٍ علاجي؛ دخله المخبري خارج المالية العامة).
              .where((r) =>
                  !jsTruthy(r['isDebt']) && !jsTruthy(r['isAnalysis']))
              .toList()
          // م113 — بالتاريخ أولاً (الأحدث أعلى) ثم الأحدث نشاطاً ضمن اليوم.
          ..sort(byDateNewestFirst);

    final headerPhone = () {
      // أول هاتف من قيود المريض (patientPhone حرفياً) ثم صف المرضى.
      for (final e in agg.entries) {
        if (jsTruthy(e['phone'])) return '${e['phone']}';
      }
      return '${patient?['phone'] ?? ''}' == 'null'
          ? ''
          : '${patient?['phone'] ?? ''}';
    }();

    return Scaffold(
      // م44 — الشريط الشفاف: شريحة علوية بتدرج الهوية بارتفاع شريط
      // النظام (أيقونات بيضاء على أخضر — لا فاتح على فاتح).
      body: Column(
        children: [
          Container(
            key: const Key('pp-statusbar-cap'),
            height: MediaQuery.paddingOf(context).top,
            decoration: const BoxDecoration(
              gradient: BrandColors.brandGradient,
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                // v48 — هوامش جانبية مقلصة (14←9) كي تتسع بطاقة السجل إلى
                // ~95% من عرض الشاشة (طلب المالك) مع بقاء الأقسام كلها
                // محاذاةً للحواف نفسها — تناسق عام.
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 24),
                children: [
                  // ── هيدر الأصل: رجوع مربع + اسم/عيادة + اتصال + (i) + ⋮ ──
                  Row(
                    children: [
                      Material(
                        color: BrandColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: BrandColors.line),
                        ),
                        child: InkWell(
                          key: const Key('pp-back'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(context).maybePop(),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.arrow_back_rounded, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: BrandColors.brandText,
                              ),
                            ),
                            if (clinic.isNotEmpty)
                              Text(
                                clinic,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: BrandColors.mut,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // م121 + م-تكافؤ — فصل الاتصال عن عرض الرقم (قرار
                      // المالك): صلاحية patients.phones تحجب **رؤية**
                      // الرقم فقط (يظهر في الترويسة أعلاه محجوباً)، أما
                      // زر الاتصال فمتاح دائماً — الموظف يتصل بالمريض
                      // دون أن يقرأ رقمه.
                      if (headerPhone.isNotEmpty)
                        IconButton(
                          key: const Key('pp-call'),
                          tooltip: 'اتصال',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => launchUrl(
                            Uri.parse(
                              'tel:${headerPhone.replaceAll(RegExp(r'[^0-9+]'), '')}',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: Icon(
                            Icons.call_rounded,
                            size: 19,
                            color: BrandColors.brandIcon,
                          ),
                        ),
                      // م121 — المعلومات الطبية صلاحية مستقلة (خصوصية صحية).
                      if (staffAllowed('patients.medical'))
                        IconButton(
                          key: const Key('pp-medical'),
                          tooltip: 'المعلومات الطبية',
                          visualDensity: VisualDensity.compact,
                          onPressed: _openMedical,
                          icon: Icon(
                            Icons.info_outline_rounded,
                            size: 19,
                            color: BrandColors.brandIcon,
                          ),
                        ),
                      Material(
                        color: BrandColors.gold.withValues(alpha: .12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: BrandColors.gold.withValues(alpha: .3),
                          ),
                        ),
                        child: InkWell(
                          key: const Key('pp-actions'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: _openActionsSheet,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: Icon(Icons.more_vert_rounded, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // ── بطاقة الملخص القابلة للطي (م65) — توفير مساحة: الشريط
                  // المضغوط يعرض الخلاصة بسطر واحد، واللمس يوسع للبطاقة الكاملة
                  // بترتيب PatientProfile.vue الحرفي. ──
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        InkWell(
                          key: const Key('pp-summary-toggle'),
                          onTap: () =>
                              setState(() => summaryOpen = !summaryOpen),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: summaryOpen
                                      ? Text(
                                          'الملخص المالي',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: BrandColors.mut,
                                          ),
                                        )
                                      : FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment:
                                              AlignmentDirectional.centerStart,
                                          child: Row(
                                            children: [
                                              _miniStat(
                                                'الإجمالي',
                                                n(agg.grossTotal),
                                                BrandColors.mut,
                                              ),
                                              _miniDot(),
                                              _miniStat(
                                                'المدفوع',
                                                n(agg.total),
                                                const Color(0xFF065F46),
                                              ),
                                              _miniDot(),
                                              _miniStat(
                                                'الديون',
                                                agg.debtRemaining > 0
                                                    ? n(agg.debtRemaining)
                                                    : '0',
                                                agg.debtRemaining > 0
                                                    ? BrandColors.red
                                                    : const Color(0xFF16A34A),
                                              ),
                                              if (stages.isNotEmpty) ...[
                                                _miniDot(),
                                                Text(
                                                  'خطة $tpDone/${stages.length}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF16A34A),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                ),
                                Icon(
                                  summaryOpen
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  size: 19,
                                  color: BrandColors.mut,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (summaryOpen)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            child: Column(
                              children: [
                                // الملخص المالي الثلاثي — pp-stat حرفياً.
                                Row(
                                  children: [
                                    _ppStat(
                                      'الإجمالي',
                                      n(agg.grossTotal),
                                      cur,
                                      BrandColors.mut,
                                      key: const Key('pp-total'),
                                    ),
                                    _ppStat(
                                      'المدفوع',
                                      n(agg.total),
                                      cur,
                                      const Color(0xFF065F46),
                                      key: const Key('pp-paid'),
                                    ),
                                    _ppStat(
                                      'الديون',
                                      agg.debtRemaining > 0
                                          ? n(agg.debtRemaining)
                                          : '0',
                                      agg.debtRemaining > 0 ? cur : '',
                                      agg.debtRemaining > 0
                                          ? BrandColors.red
                                          : const Color(0xFF16A34A),
                                      key: const Key('pp-debt'),
                                      onTap: agg.debtRemaining > 0
                                          ? () => setState(
                                              () => activeSection = 'debts',
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                                // بطاقات المعالجات الديناميكية لكل نوع خدمة.
                                if (cards.isNotEmpty) ...[
                                  const Divider(height: 20),
                                  GridView.count(
                                    crossAxisCount: 3,
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    mainAxisSpacing: 6,
                                    crossAxisSpacing: 6,
                                    // م41 — الخلية تطول مع تكبير الخط: لا قص.
                                    childAspectRatio:
                                        1.7 /
                                        math.pow(
                                          MediaQuery.textScalerOf(
                                                context,
                                              ).scale(10) /
                                              10,
                                          1.3,
                                        ),
                                    children: [
                                      for (final c in cards) _tcCard(c, n),
                                    ],
                                  ),
                                ],
                                if (stages.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.checklist_rounded,
                                          size: 12,
                                          color: Color(0xFF16A34A),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'خطة علاج: $tpDone/${stages.length} مرحلة',
                                          key: const Key('pp-plan-line'),
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF16A34A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── تبويبات الأقسام — rec-filter-bar حرفياً ──
                  Row(
                    children: [
                      _secTab('visits', 'الزيارات', Icons.description_rounded),
                      _secTab(
                        'debts',
                        'الديون${activeDebts.isNotEmpty ? ' (${activeDebts.length})' : ''}',
                        Icons.add_circle_outline_rounded,
                      ),
                      // م171 — المواعيد بعد الديون وقبل الأشعة (طلب المالك).
                      _secTab(
                        'appts',
                        'المواعيد${_patientAppts().isNotEmpty ? ' (${_patientAppts().length})' : ''}',
                        Icons.event_note_rounded,
                      ),
                      _secTab(
                        'xrays',
                        'الأشعة',
                        Icons.add_circle_outline_rounded,
                      ),
                      _secTab('plan', 'خطة العلاج', Icons.check_box_outlined),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── الخطة العلاجية ──
                  if (activeSection == 'plan')
                    _Section(
                      title: 'خطة العلاج',
                      trailing: IconButton(
                        key: const Key('tp-add'),
                        icon: const Icon(
                          Icons.add_circle_rounded,
                          color: BrandColors.brand600,
                        ),
                        onPressed: () async {
                          final ctl = TextEditingController();
                          final desc = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('مرحلة جديدة'),
                              content: TextField(
                                key: const Key('tp-desc'),
                                controller: ctl,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  hintText: 'وصف المرحلة الجديدة...',
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('إلغاء'),
                                ),
                                FilledButton(
                                  key: const Key('tp-save'),
                                  onPressed: () =>
                                      Navigator.pop(context, ctl.text.trim()),
                                  child: const Text('إضافة'),
                                ),
                              ],
                            ),
                          );
                          if (desc != null && desc.isNotEmpty) {
                            // م127 — كتابة خطة العلاج ضمن صلاحية تعديل السجلات.
                            if (!mounted ||
                                !gateStaff(this.context, 'records.edit')) {
                              return;
                            }
                            _planStore.add(
                              name,
                              clinic,
                              desc,
                              phone: _medPhone(),
                            );
                            _planChanged();
                          }
                        },
                      ),
                      child: stages.isEmpty
                          ? Padding(
                              padding: EdgeInsets.all(10),
                              child: Text(
                                'لا توجد مراحل — أضف مرحلة',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: BrandColors.mut2,
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                for (var i = 0; i < stages.length; i++)
                                  CheckboxListTile(
                                    key: Key('tp-stage-$i'),
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    value: stages[i]['done'] == true,
                                    title: Text(
                                      '${stages[i]['desc']}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        decoration: stages[i]['done'] == true
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    subtitle:
                                        '${stages[i]['doneDate'] ?? ''}'
                                            .isNotEmpty
                                        ? Text(
                                            'أُنجز: ${stages[i]['doneDate']}',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                            ),
                                          )
                                        : null,
                                    // حذف المرحلة — توأم removeStage (زر ✕ لكل مرحلة
                                    // في TreatmentPlan.vue): stages.splice(i, 1).
                                    secondary: IconButton(
                                      key: Key('tp-remove-$i'),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 16,
                                        color: Color(0xFFDC2626),
                                      ),
                                      tooltip: 'حذف المرحلة',
                                      onPressed: () {
                                        // v29 — الحذف = شاهد قبر على صف المرحلة نفسه:
                                        // ينتشر حتماً لكل الأجهزة ولا يُبعث أبداً.
                                        if (!gateStaff(
                                          context,
                                          'records.edit',
                                        )) {
                                          return;
                                        }
                                        _planStore.remove(
                                          name,
                                          clinic,
                                          '${stages[i]['id']}',
                                          phone: _medPhone(),
                                        );
                                        _planChanged();
                                      },
                                    ),
                                    onChanged: (v) {
                                      // v29 — يمس صف هذه المرحلة وحدها.
                                      if (!gateStaff(context, 'records.edit')) {
                                        return;
                                      }
                                      _planStore.setDone(
                                        name,
                                        clinic,
                                        '${stages[i]['id']}',
                                        v == true,
                                        doneDate: getCurrentDate(),
                                        phone: _medPhone(),
                                      );
                                      _planChanged();
                                    },
                                  ),
                              ],
                            ),
                    ),
                  const SizedBox(height: 12),

                  // ── الديون ──
                  if (activeSection == 'debts') ...[
                    // م43/v55 — بطاقة الدين المطوية (نمط v54) والمسددة مختفية
                    // تلقائياً من القسم.
                    if (activeDebts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 34),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.check_rounded,
                              size: 40,
                              color: Color(0xFF1E7A52),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'لا توجد ديون',
                              style: TextStyle(
                                fontSize: 12,
                                color: BrandColors.mut2,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final d in activeDebts) ...[
                        _debtCard(d),
                        const SizedBox(height: 8),
                      ],
                    const SizedBox(height: 4),
                  ],

                  // ── السجلات والتركيبات (الزيارات) ──
                  // v48 — بطاقات السجلات خرجت من بطاقة القسم لتتسع إلى ~95%
                  // من عرض الشاشة (طلب المالك): رأس القسم صار سطراً خفيفاً
                  // بشريط الذهب والعنوان نفسيهما، والبطاقات بنات مباشرة للقائمة.
                  if (activeSection == 'visits') ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
                      child: Row(
                        children: [
                          Container(
                            width: 5,
                            height: 17,
                            decoration: BoxDecoration(
                              color: BrandColors.gold,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'السجلات (${allEntries.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: BrandColors.brand900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (allEntries.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(10),
                        child: Text(
                          'لا سجلات بعد',
                          style: TextStyle(
                            fontSize: 12,
                            color: BrandColors.mut2,
                          ),
                        ),
                      )
                    else
                      // م82 — مفتاحٌ ثابت لكل بطاقة سجلّ.
                      //
                      //  كانت البطاقات بلا مفاتيح، فأي تغيير في القائمة (حذف سجل،
                      //  إضافة دفعة، إعادة ترتيب) يجعل خوارزمية المطابقة تستبدل
                      //  الشجرة الفرعية كاملةً بدل تحريكها — والبطاقة الواحدة شجرة
                      //  ضخمة (دالة بناء بـ329 سطراً). المفتاح يجعل التحديث نقلاً
                      //  لا إعادة بناء.
                      //
                      //  ولمَ لم تُحوَّل إلى قائمة كسولة؟ لأنها ليست القائمة الجذر:
                      //  هي داخل عمود ضمن `ListView` أعلى منها، وتحويلها يستلزم
                      //  إعادة بناء الشاشة على شرائح — تغييرٌ واسع لا تمسكه
                      //  الاختبارات الحالية، ولا يستحق مخاطرته على شاشة عاملة.
                      //  المفتاح يقتنص أكبر مكسب بأقل خطر.
                      for (var i = 0; i < allEntries.length; i++)
                        KeyedSubtree(
                          key: ValueKey('rec-${allEntries[i]['id'] ?? i}'),
                          child: _recordRowCard(
                            allEntries[i],
                            i,
                            cur,
                            n,
                            debts,
                            records,
                          ),
                        ),
                  ],

                  // ── م171 — المواعيد: حجوزات المريض القادمة، النقر
                  // ينقل ليوم الحجز في تبويب المواعيد، وزر حجزٍ سريع ──
                  if (activeSection == 'appts')
                    _Section(
                      title: 'المواعيد المحجوزة',
                      child: _appointmentsBody(),
                    ),

                  // ── صور الأشعة ──
                  if (activeSection == 'xrays')
                    _Section(
                      title: 'صور الأشعة',
                      // العيادة تُمرَّر لوسم الصور الجديدة (المرحلة H — دائم)
                      // وترشيح العزل خلف علمه.
                      // م-عزل الهوية — الهاتف (هوية الفتح إن انقسمت، وإلا
                      // هاتف الصف/السجلات) يعزل معرض السميّ.
                      child: XraySection(
                        patientName: name,
                        clinic: widget.clinic,
                        phone: _medPhone(),
                        controller: _xrayCtl, // م172
                      ),
                    ),

                  // م58 — زر «إضافة زيارة» العريض استُبدل بالدائرة العائمة
                  // الذهبية (floatingActionButton) التي تفتح ورقة الزيارة
                  // السريعة — مساحة سفلية كي لا تحجب الدائرة آخر قسم.
                  const SizedBox(height: 56),
                ],
              ),
            ),
          ),
        ],
      ),
      // م58/م59 — الدائرة العائمة الخاصة بالمريض (هوية ShinyFab).
      // م172 — صارت **سياقيةً بحسب التبويب** (قرار المالك): الزيارات «+»،
      // الديون «تسجيل دفعة» ذهبيةً إن وُجد دينٌ مفتوح، المواعيد «حجز
      // موعد»، الأشعة زرا «تصوير/رفع» متراصان، وخطة العلاج بلا زر.
      floatingActionButton: _contextFab(activeDebts),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // ═══ م11: بطاقة الزيارة التوأم (RecordRow) ═══

  /// ألوان أرباع بالمر — palmer-UR/UL/LR/LL كالأصل.
  static const _palmerColors = {
    'UR': Color(0xFF15604A),
    'UL': Color(0xFF0E7490),
    'LR': Color(0xFFA16207),
    'LL': Color(0xFF9333EA),
  };

  Widget _recordRowCard(
    JMap e,
    int i,
    String cur,
    String Function(Object?) n,
    List<JMap> debts,
    List<JMap> records,
  ) {
    final isP = e['_kind'] == 'p';
    final teeth = _teethStructured(e);
    // م100 — نظام العرض المُزامَن (Palmer/FDI) لرقائق أسنان البطاقة.
    final sys = ref.read(notationSystemProvider);
    final amount = jsNumOr0(isP ? e['total'] : e['amount']);
    // م65 — «معدل» يظهر أيضاً لمن لديه قيود _audit بلا علم _edited
    // (تعديل بيانات المريض في Vue لا يرفع العلم لكنه يكتب القيود).
    final isModified = jsTruthy(e['_edited']) || hasAudit(e);
    final isDebtPay = jsTruthy(e['isDebtPayment']);
    JMap? linkedDebt;
    for (final d in debts) {
      if (isP ? d['prostheticId'] == e['id'] : d['recordId'] == e['id']) {
        linkedDebt = d;
        break;
      }
    }
    final rawPayment = '${e['payment'] ?? ''}';
    // displayPayment — توأم RecordRow: «دين» يبقى «دين»؛ غيره كما هو.
    final payment = rawPayment == 'دين' ? 'دين' : rawPayment;
    final isCash = payment == 'كاش' || payment == 'نقد' || payment == 'نقدي';
    final isDebtRow = payment == 'دين';

    // الدين المرتبط بدفعة (لأجل الخدمة النظيفة ورقم الدفعة والشارة).
    JMap? payDebt;
    if (isDebtPay) {
      final did = '${e['debtId'] ?? ''}';
      for (final d in debts) {
        if ('${d['id'] ?? ''}' == did) {
          payDebt = d;
          break;
        }
      }
    }

    // العرض عبر الدوال النقية (record_row_logic — مُختبَرة في م27).
    final serviceLabel = recordDisplayService(e, payDebt: payDebt, isPros: isP);
    final instLabel = installmentLabelFor(e, payDebt, records);
    final String? installmentLabel = instLabel.isEmpty ? null : instLabel;

    // v48 — الشارة مصغّرة إلى ~70% من حجمها السابق (خط 11.5←8،
    // حشوة 7/1.5←5/1) لتسكن زاوية البطاقة العلوية اليمنى بلا تزاحم.
    Widget topBadge(
      String label,
      Color color, {
      Key? key,
      VoidCallback? onTap,
    }) {
      final chip = Container(
        key: onTap == null ? key : null,
        margin: const EdgeInsets.only(left: 3),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      );
      if (onTap == null) return chip;
      return InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: chip,
      );
    }

    // ═══ v48 — هندسة البطاقة الموحّدة (طلب المالك — ١٢ بنداً) ═══
    //   • ارتفاع واحد لكل البطاقات مهما اختلف المحتوى — التناظر مضمون
    //     (يتدرّج مع مقياس خط النظام حمايةً من القص).
    //   • عنقود الشارات المصغّر (~70%) يسكن الزاوية العلوية اليمنى فوق
    //     المحتوى (Stack) — «معدل» أولها عند الزاوية تماماً.
    //   • اسم المعالجة هو البطل: أكبر خطاً، مرتسٍ يميناً بنقطة موحدة
    //     عبر كل البطاقات (v49) فتتراص الأسماء تحت بعض.
    //   • عمود الأسنان الثابت بمكانه (م29/م41: يضيق تدريجياً فوق مقياس
    //     «كبير»)؛ رقاقات أصغر قليلاً بتباعد متساوٍ، وFittedBox يمنع
    //     أي فيضان مهما كثرت الأسنان.
    //   • المبلغ فوق التاريخ متراصفين يساراً قرب الكبب، والكبب ⋮ على
    //     بعد ٦ نقاط من الحافة اليسرى — لا عنصر يلاصق حواف البطاقة.
    final ts = MediaQuery.textScalerOf(context).scale(10) / 10;
    final teethColWidth = ts <= 1.35
        ? 84.0
        : math.max(48.0, 84.0 - (ts - 1.35) * 130);
    // م144 — فتحة ثابتة لعمود المبلغ/التاريخ (نمط عمود الأسنان نفسه):
    // كان العمود Flexible بحصة 1 من 9 فيمنحه Flutter ~20ن فقط على عرض
    // هاتف حقيقي (360ن)، وFittedBox يعيد تصغير النص ليطابقها — فبدا
    // المبلغ والتاريخ ضئيلين مهما رُفع حجم الخط (شكوى المالك مرتين).
    // الفتحة الثابتة تضمن الرسم بالحجم الكامل دائماً، وتتدرّج مع مقياس
    // خط النظام، وتتراصف عبر كل البطاقات (تناظرٌ أدق من المرن).
    final amountColWidth = 72.0 * ts.clamp(1.0, 1.6);
    // م64 — الشارات الفعلية بعد إزالة شارة الدفعة الخضراء: دين، تركيبات،
    // معدل (لم تعد isDebtPay ترسم شارة).
    final hasBadges =
        isP ||
        (linkedDebt != null && linkedDebt['status'] != 'paid') ||
        isModified;
    // v49 — 92←74: فراغ أبيض أقل فتظهر معالجات أكثر بالشاشة الواحدة
    // (طلب المالك) مع بقاء الارتفاع موحداً وكل حمايات التقليص.
    final cardH = 74.0 * ts.clamp(1.0, 1.8);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      height: cardH,
      decoration: BoxDecoration(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BrandColors.line),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── ١) اسم المعالجة — البطل، مرتسٍ يميناً بنقطة موحدة ──
                // v49 — بدل التمركز: محاذاة يمينية ثابتة بمسافة بسيطة عن
                // الحافة (حشوة البداية 12) فتتراص الأسماء تحت بعض
                // بتناظر تام عبر كل البطاقات (طلب المالك).
                Expanded(
                  flex: 5,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      serviceLabel,
                      key: Key('rr-service-$i'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // ── ٢) عمود الأسنان الثابت (موضع دائم لا يتحرك) ──
                SizedBox(
                  width: teethColWidth,
                  height: double.infinity,
                  child: teeth.isEmpty
                      ? const SizedBox.shrink(key: Key('rr-teeth-empty'))
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: teethColWidth,
                            child: Wrap(
                              key: Key('rr-teeth-$i'),
                              spacing: 4,
                              runSpacing: 4,
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                // م105 — تعدد الأرباع ⇒ شبكة Palmer الصليبية
                                // (خط أفقي بين الفكين + وسطي عمودي، ونصفها
                                // لفكٍّ واحد) بأقسام مضغوطة بالمدى واتجاهٍ
                                // سريري مرآتي — كصور المالك حرفياً.
                                // م104 — ربعٌ واحد ⇒ خلية القوس بالمدى.
                                ...() {
                                  final refs = [
                                    for (final t in teeth)
                                      (q: t.q, n: t.n, primary: t.p),
                                  ];
                                  final cross = toothCrossModel(
                                    refs,
                                    system: sys,
                                  );
                                  if (cross != null) {
                                    return [
                                      // انكماش ذاتي: شبكة FDI الكاملة أعرض
                                      // من عمود 84ن — تتقلص لتلائمه بدل
                                      // الفيضان (Palmer تمر بلا تقليص).
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        // م106 — مقياس أكبر (كان 0.8 صغيراً
                                        // جداً بشكوى المالك): الانكماش
                                        // الذاتي يحمي من تجاوز عرض العمود،
                                        // فالرفع يكبّر كل ما اتسع له.
                                        child: ToothCrossView(
                                          cross,
                                          quadrantColor: (q) =>
                                              _palmerColors[q] ??
                                              BrandColors.brand600,
                                          scale: 1.15,
                                        ),
                                      ),
                                    ];
                                  }
                                  return [
                                    for (final g in summarizeTeethRefs(
                                      refs,
                                      system: sys,
                                    ))
                                      ToothLabelView(
                                        ToothLabel(
                                          g.text,
                                          g.quadrant,
                                          palmerBorder: g.palmerBorder,
                                        ),
                                        color:
                                            _palmerColors[g.quadrant] ??
                                            BrandColors.brand600,
                                        scale: 0.7,
                                      ),
                                  ];
                                }(),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 6),
                // ── ٣) الوسط: طريقة الدفع | دفعة N ──
                Expanded(
                  flex: 3,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            payment,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isCash
                                  ? const Color(0xFF22C55E)
                                  : isDebtRow
                                  ? BrandColors.red
                                  : BrandColors.brandText,
                            ),
                          ),
                        ),
                        if (installmentLabel != null)
                          Text(
                            ' | $installmentLabel',
                            key: Key('rr-inst-$i'),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: BrandColors.mut2,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // ── ٤) المبلغ والتاريخ فوق بعض بمحاذاة يسارية ──
                // م144 — فتحة ثابتة (amountColWidth) بدل Flexible الجائعة:
                // حصة 1 من 9 كانت تهبط لـ~20ن على الهواتف فيتقزّم النص
                // (م133 عالج فيضان 35ن لكن بثمن التقزّم). الثابتة ترسم
                // 17/13/12 بحجمها الكامل، وFittedBox داخلها يبقى صمّام
                // أمان «لا فيضان أبداً» (v48/v49) للمبالغ الطويلة جداً
                // أو مقاييس الخط الكبيرة — تصغيرٌ رشيق داخل الفتحة فقط.
                SizedBox(
                  width: amountColWidth,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              n(amount),
                              key: Key('rr-amount-$i'),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              ' $cur',
                              style: TextStyle(
                                fontSize: 13,
                                color: BrandColors.mut2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          fmtDisplayDate('${e['date'] ?? ''}'),
                          style: TextStyle(
                            fontSize: 12,
                            color: BrandColors.mut2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // ── ٥) قائمة ⋮ قرب الحافة اليسرى (فجوة ٦ نقاط فقط) ──
                SizedBox(
                  width: 30,
                  child: PopupMenuButton<String>(
                    key: Key('rr-kebab-$i'),
                    tooltip: 'خيارات',
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 17,
                      color: BrandColors.mut2,
                    ),
                    onSelected: (v) {
                      switch (v) {
                        case 'edit-value':
                          _editEntryAmount(e);
                        case 'select-teeth':
                          _openTeethSelector(e);
                        // معلومات مختصرة — ملاحظة هذه الدفعة/الزيارة حصراً.
                        case 'quick-info':
                          showQuickInfoDialog(
                            context,
                            ref,
                            kind: e['_kind'] == 'p' ? 'p' : 'r',
                            id: '${e['id']}',
                            patientName:
                                '${e['name'] ?? e['patient_name'] ?? ''}',
                          );
                        case 'debt':
                          setState(() => activeSection = 'debts');
                        case 'delete':
                          _deleteEntry(e);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        key: Key('rr-edit-$i'),
                        value: 'edit-value',
                        child: const Row(
                          children: [
                            Icon(Icons.edit_rounded, size: 15),
                            SizedBox(width: 8),
                            Text(
                              'تعديل القيمة',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        key: Key('rr-teeth-$i'),
                        value: 'select-teeth',
                        child: const Row(
                          children: [
                            Icon(Icons.mood_rounded, size: 15),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'تحديد الأسنان المعالجة',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // معلومات مختصرة (قرار المالك — ميزة الملاحظات
                      // المختصرة): عرض/تعديل ملاحظة هذا الصف وحده.
                      PopupMenuItem(
                        key: Key('rr-note-$i'),
                        value: 'quick-info',
                        child: const Row(
                          children: [
                            Icon(Icons.sticky_note_2_outlined, size: 15),
                            SizedBox(width: 8),
                            Text(
                              'معلومات مختصرة',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      // v50 — «طباعة تقرير الأسنان» أُزيلت نهائياً من
                      // القائمة بطلب المالك.
                      if (linkedDebt != null)
                        PopupMenuItem(
                          value: 'debt',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 15,
                                color: Color(0xFF0E7490),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'الدين المرتبط',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: const Color(0xFF0E7490),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(height: 6),
                      PopupMenuItem(
                        key: Key('rr-del-$i'),
                        value: 'delete',
                        child: const Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 15,
                              color: BrandColors.red,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'حذف السجل',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: BrandColors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // عنقود الزاوية العلوية اليمنى — فوق المحتوى كي يبقى منقوراً:
          // «معدل» أولاً (عند الزاوية تماماً) ثم تركيبات ثم دين — نفس
          // المفاتيح والنقر (سجل التعديلات في _showAuditLog) حرفياً.
          if (hasBadges)
            PositionedDirectional(
              top: 6,
              start: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isModified)
                    topBadge(
                      'معدل',
                      BrandColors.goldDark,
                      key: Key('rr-modified-$i'),
                      onTap: () => _showAuditLog(e),
                    ),
                  if (isP) topBadge('تركيبات', BrandColors.goldDark),
                  if (linkedDebt != null && linkedDebt['status'] != 'paid')
                    topBadge('دين', BrandColors.red),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ═══ م11: لوحة الإجراءات وأفعال الهيدر ═══

  /// م-عزل الهوية — هاتف الهوية المفتوحة: إن فُتح الملف بهوية سميٍّ
  /// `p:<هاتف>` (تشابهٌ داخل العيادة) فهاتفُها هو المعرّف القاطع لكل ما
  /// يتبع الهوية (طبية/خطة/معرض أشعة) — لا هاتفَ أول صفٍّ بالاسم (يخلط
  /// السميّين). فارغٌ حين لا هوية منقسمة (السلوك القديم).
  String _identityPhone() {
    final id = _identityNow();
    return id.startsWith('p:') ? id.substring(2) : '';
  }

  String _knownPhone() {
    // الهوية المفتوحة أولاً — فلا يُلتقط هاتف سميٍّ من صفوفه.
    final idp = _identityPhone();
    if (idp.isNotEmpty) return idp;
    for (final e in ref.read(reposProvider).records.getByPatient(name)) {
      if (jsTruthy(e['phone'])) return '${e['phone']}';
    }
    return '';
  }

  /// م96 — هاتف صف المريض المخزن (المرجع القياسي لمفتاح المعلومات الطبية).
  /// م-عزل الهوية — تتقدّمه هوية الفتح المنقسمة (هاتفها القاطع).
  String _rowPhone() {
    final idp = _identityPhone();
    if (idp.isNotEmpty) return idp;
    return '${ref.read(reposProvider).patients.getById(name)?['phone'] ?? ''}'
        .replaceAll('null', '');
  }

  /// هاتف مفتاح المعلومات الطبية: هوية الفتح ← هاتف الصف ← هاتف السجلات.
  String _medPhone() {
    final idp = _identityPhone();
    if (idp.isNotEmpty) return idp;
    final r = _rowPhone().trim();
    return r.isNotEmpty ? r : _knownPhone();
  }

  /// م58 — الدائرة العائمة: ورقة الزيارة السريعة (بلا مغادرة الملف).
  void _openQuickVisit() {
    // م119 — إضافة الزيارات صلاحية مستقلة.
    if (!gateStaff(context, 'records.add')) return;
    showQuickVisitSheet(
      context,
      name: name,
      clinic: clinic,
      phone: _knownPhone(),
      onFullOptions: _addVisit,
    );
  }

  /// زيارة جديدة — للرئيسية مربوطة بالمريض وعيادته (query الأصل).
  /// م58 — صار مسار «الخيارات الكاملة» من ورقة الزيارة السريعة.
  void _addVisit() {
    final phone = _knownPhone();
    ref.read(addVisitDraftProvider.notifier).state = {
      'name': name,
      'clinic': clinic,
      'phone': phone,
    };
    Navigator.of(context).popUntil((r) => r.isFirst);
    ref.read(homeJumpProvider.notifier).state++;
  }

  /// لوحة إجراءات الهيدر — Actions Bottom Sheet حرفياً.
  void _openActionsSheet() {
    // م150 — إغلاق الورقة/الحوار بسياق **الورقة نفسها** لا بسياق الشاشة:
    // على الكمبيوتر الملف داخل ملاّح DetailHost المتداخل والحوار على الملاّح
    // الجذري — Navigator.pop(context) بسياق الشاشة كان يُسقط شاشة الملف من
    // اللوح (لا الحوار)، فتبقى القائمة معلقة ويرتدّ الفعل التالي على حارس
    // !mounted بصمت (حذف المريض «لا يعمل أبداً» — بلاغ المالك 2026-08-09).
    Widget action(
      BuildContext sheetCtx,
      Key key,
      IconData icon,
      String label,
      VoidCallback onTap, {
      Color? color,
    }) => ListTile(
      key: key,
      dense: true,
      leading: Icon(icon, size: 18, color: color ?? BrandColors.brandIcon),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      onTap: () {
        Navigator.pop(sheetCtx);
        onTap();
      },
    );

    Widget body(BuildContext sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.goldDark,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          action(
            sheetCtx,
            const Key('pp-act-wa'),
            Icons.chat_rounded,
            'واتساب',
            _openWhatsApp,
            color: const Color(0xFF25D366),
          ),
          action(
            sheetCtx,
            const Key('pp-act-print'),
            Icons.print_rounded,
            'طباعة PDF',
            _printPatientSummary,
          ),
          action(
            sheetCtx,
            const Key('pp-act-edit'),
            Icons.edit_rounded,
            'تعديل بيانات المريض',
            _editPatientData,
          ),
          // م147 — «إضافة التحاليل الثلاثية»: يظهر فقط عند تفعيل الميزة
          // في الإعدادات (triAnalysesEnabled) وللمستخدم صلاحية records.add.
          // يضيف تحليلاً لآخر زيارة قائمة للمريض (لا زيارة جديدة).
          if (triAnalysesEnabled(ref.read(appConfigProvider)) &&
              staffAllowed('records.add'))
            action(
              sheetCtx,
              const Key('pp-act-add-analysis'),
              Icons.science_outlined,
              'إضافة التحاليل الثلاثية',
              _addTriAnalysisToLastVisit,
            ),
          // م171 — «حجز موعد» من ورقة إجراءات البطاقة (طلب المالك).
          if (staffAllowed('records.add'))
            action(
              sheetCtx,
              const Key('pp-act-book'),
              Icons.event_available_rounded,
              'حجز موعد',
              _bookAppointment,
            ),
          action(
            sheetCtx,
            const Key('pp-act-del'),
            Icons.delete_outline_rounded,
            'حذف المريض',
            _deletePatient,
            color: BrandColors.red,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );

    // نسخة الكمبيوتر: اللوحة نفسها حوار مركزي (لا ورقة بعرض الشاشة) —
    // مسار الهاتف أدناه كما هو حرفياً.
    if (isDesktopUi(context)) {
      showDesktopDialog<void>(context, width: 380, builder: body);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BrandColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: body,
    );
  }

  /// م171 — مواعيد المريض القادمة (المعلقة) بهويته (الاسم + هاتف الهوية
  /// لاستبعاد السميّ) — مصدر تبويب «المواعيد» وعدّاده.
  List<JMap> _patientAppts() => patientUpcomingAppointments(
        ref.read(reposProvider).appointments.getAll().cast<JMap>(),
        name,
        phone: _medPhone(),
      ).cast<JMap>();

  /// م171 — جسم تبويب «المواعيد»: قائمة الحجوزات القادمة (التاريخ/الوقت/
  /// العيادة/الحالة) — النقر ينقل ليوم الحجز، وزر حجزٍ سريع أعلى القائمة.
  Widget _appointmentsBody() {
    final appts = _patientAppts();
    String latin(String d) => d.replaceAll('-', '/');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // م172 — زر المربع أُزيل: الحجز صار بالزر العائم الدائري السفلي
        // (قرار المالك) — pp-fab-book.
        if (appts.isEmpty)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text('لا توجد مواعيد محجوزة قادمة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: BrandColors.mut2)),
          )
        else
          for (final a in appts)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: Material(
                color: BrandColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: BrandColors.line, width: .7),
                ),
                child: ListTile(
                key: Key('pp-appt-${a['id']}'),
                dense: true,
                leading: Icon(Icons.event_rounded,
                    size: 18,
                    color: apptStatusColor('${a['status'] ?? 'pending'}')),
                title: Text(
                  '${latin('${a['date'] ?? ''}')}'
                  '${'${a['time'] ?? ''}'.isNotEmpty ? ' • ${to12h('${a['time']}')}' : ''}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${'${a['clinic'] ?? ''}'.isNotEmpty ? '${a['clinic']} • ' : ''}'
                  '${apptStatusLabel('${a['status'] ?? 'pending'}')}',
                  style: TextStyle(fontSize: 11, color: BrandColors.mut),
                ),
                trailing: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 12, color: BrandColors.faint),
                // النقر يأخذ ليوم الحجز في تبويب المواعيد (طلب المالك).
                onTap: () => _goToApptDay('${a['date'] ?? ''}'),
              ),
              ),
            ),
      ],
    );
  }

  /// م171 — الانتقال ليوم حجزٍ محدد في تبويب المواعيد: يُبذر يوم الهبوط
  /// ثم يُفتح التبويب (الكمبيوتر: الأسبوع يبدأ منه؛ الهاتف: قائمة اليوم).
  void _goToApptDay(String date) {
    if (date.isEmpty) return;
    ref.read(apptGoDayProvider.notifier).state = date;
    if (isDesktopUi(context)) {
      ref.read(desktopTabProvider.notifier).state = 'calendar';
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
      ref.read(activeTabProvider.notifier).state = 'calendar';
    }
  }

  /// م172 — الزر العائم السياقي بحسب التبويب المفتوح (قرار المالك).
  Widget? _contextFab(List<JMap> activeDebts) {
    switch (activeSection) {
      case 'visits':
        // الزيارات — زر «+» القائم حرفياً (زيارة سريعة).
        return ShinyFab(
          key: const Key('pp-add-visit'),
          tooltip: 'إضافة زيارة',
          onTap: _openQuickVisit,
        );
      case 'debts':
        // الديون — «تسجيل دفعة» ذهبيةً، فقط إن وُجد دينٌ مفتوح.
        if (activeDebts.isEmpty) return null;
        return ShinyFab(
          key: const Key('pp-fab-pay'),
          tooltip: 'تسجيل دفعة',
          icon: Icons.payments_rounded,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomLeft,
            colors: [BrandColors.gold, BrandColors.goldDark],
          ),
          glowColor: BrandColors.gold,
          onTap: () => _payFromFab(activeDebts),
        );
      case 'appts':
        // المواعيد — «حجز موعد» دائري (بدل زر المربع — أُزيل).
        if (!staffAllowed('records.add')) return null;
        return ShinyFab(
          key: const Key('pp-fab-book'),
          tooltip: 'حجز موعد',
          icon: Icons.event_available_rounded,
          onTap: _bookAppointment,
        );
      case 'xrays':
        // الأشعة — زران متراصان: «تصوير مباشر» (هاتف فقط) فوق «رفع».
        if (!staffAllowed('records.add')) return null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isDesktopUi(context)) ...[
              ShinyFab(
                key: const Key('pp-fab-camera'),
                tooltip: 'تصوير مباشر',
                icon: Icons.photo_camera_rounded,
                size: 48,
                onTap: _openInAppCamera,
              ),
              const SizedBox(height: 10),
            ],
            ShinyFab(
              key: const Key('pp-fab-upload'),
              tooltip: 'رفع صورة / صور',
              icon: Icons.upload_rounded,
              size: 48,
              onTap: () => _xrayCtl.upload(),
            ),
          ],
        );
      default:
        return null; // خطة العلاج — بلا زر عائم.
    }
  }

  /// م172 — «تسجيل دفعة» من الزر العائم: دينٌ واحد يفتح نافذة الدفعة
  /// الموحدة مباشرةً، وأكثر يعرض ورقة اختيار الدين أولاً.
  void _payFromFab(List<JMap> activeDebts) {
    if (activeDebts.isEmpty) return;
    if (activeDebts.length == 1) {
      _payInstallment(activeDebts.first);
      return;
    }
    final n = formatNumber;
    final cur = ref.read(currencyProvider);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BrandColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('اختر الدين لتسجيل الدفعة',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.goldDark)),
            ),
            for (final d in activeDebts)
              ListTile(
                key: Key('pp-fab-pay-${d['id']}'),
                dense: true,
                leading: const Icon(Icons.payments_rounded,
                    size: 18, color: BrandColors.goldDark),
                title: Text('${d['service'] ?? d['name'] ?? 'دين'}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                subtitle: Text(
                    'المتبقي: ${n(jsNumOr0(d['remaining']))} $cur',
                    style: const TextStyle(
                        fontSize: 11, color: BrandColors.red)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _payInstallment(d);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// م172 — فتح الكاميرا الداخلية: كل لقطةٍ تُحفظ فوراً في مسار رفع
  /// الأشعة نفسه (عبر متحكم القسم) — لا تطبيق الكاميرا الأساسي.
  void _openInAppCamera() {
    if (!gateStaff(context, 'records.add')) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => XrayCameraScreen(
          patientName: name,
          onCapture: (fileName, bytes) =>
              _xrayCtl.addCaptured([(fileName, bytes)]),
        ),
      ),
    );
  }

  /// م171 — «حجز موعد» من بطاقة المريض: مسودة {اسم/هاتف/عيادة} ثم فتح
  /// تبويب المواعيد ليفتح معالجه/نموذجه معبأً.
  void _bookAppointment() {
    ref.read(apptBookDraftProvider.notifier).state = {
      'name': name,
      'phone': _medPhone(),
      'clinic': clinic,
    };
    if (isDesktopUi(context)) {
      ref.read(desktopTabProvider.notifier).state = 'calendar';
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
      ref.read(activeTabProvider.notifier).state = 'calendar';
    }
  }

  /// م147 — آخر زيارة قائمة للمريض: توأم بناء allEntries في build حرفياً
  /// (سجلات + تركيبات، باستبعاد أصل الدين والتحليل)، مُرتّبةٌ بالأحدث أولاً
  /// — فعنصرها الأول هو آخر زيارة. تُستدعى مستقلةً عن build كي تعمل من
  /// ورقة الإجراءات (خارج شجرة البناء).
  JMap? _lastVisitEntry() {
    final entries = [
      ..._records.map((r) => ({...r, '_kind': 'r'})),
      ..._pros.map((p) => ({...p, '_kind': 'p'})),
    ].where((r) => !jsTruthy(r['isDebt']) && !jsTruthy(r['isAnalysis'])).toList()
      ..sort(byDateNewestFirst);
    return entries.isEmpty ? null : entries.first;
  }

  /// إضافة تحليلٍ ثلاثيٍّ لآخر زيارة قائمة للمريض — من ثلاث نقاط بطاقة
  /// المريض. لا زيارة جديدة تُنشأ؛ التحليل يُلحق بآخر صفٍّ موجود عبر
  /// النافذة المشتركة (كاش/تحويل بسعر الإعدادات).
  Future<void> _addTriAnalysisToLastVisit() async {
    final visit = _lastVisitEntry();
    if (visit == null) {
      _snackMsg('لا توجد زيارة لإضافة تحليل إليها');
      return;
    }
    final added = await promptAddAnalysisToVisit(
      context,
      ref,
      analysisOf: '${visit['id'] ?? ''}',
      patientName: name,
      patientId: visit['patient_id'] as String?,
      clinic: '${visit['clinic'] ?? clinic}',
      date: '${visit['date'] ?? getCurrentDate()}',
      incomeDate: visit['incomeDate'] as String?,
    );
    if (added && mounted) {
      bumpDataRevision(ref);
      setState(() {});
    }
  }

  /// تعديل بيانات المريض — نفس نافذة قائمة العيادة (اكتساح 4 جداول).
  Future<void> _editPatientData() async {
    // م127 — إعادة كتابة اسم/هاتف المريض عبر الجداول صلاحية تعديل.
    if (!gateStaff(context, 'records.edit')) return;
    final repos = ref.read(reposProvider);
    // م35 — تعبئة النافذة من صفوف عيادة الملف وحدها.
    final all =
        [
          ...repos.records.getAll(),
          ...repos.prosthetics.getAll(),
          ...repos.debts.getAll(),
        ].where((r) => r['name'] == name && _inClinic(r)).toList()..sort(
          (a, b) => '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'),
        );
    String firstWith(String key) {
      for (final r in all) {
        if (jsTruthy(r[key])) return '${r[key]}';
      }
      return '';
    }

    final nameCtl = TextEditingController(text: name);
    final phoneCtl = TextEditingController(text: firstWith('phone'));
    final phone2Ctl = TextEditingController(text: firstWith('phone2'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعديل بيانات المريض'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('pp-edit-name'),
              controller: nameCtl,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'الاسم',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('pp-edit-phone'),
              controller: phoneCtl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'رقم الهاتف',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('pp-edit-phone2'),
              controller: phone2Ctl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'رقم ثانٍ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const Key('pp-edit-save'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    editPatientCascade(
      repos,
      origName: name,
      newName: nameCtl.text,
      phone: phoneCtl.text.trim(),
      phone2: phone2Ctl.text.trim(),
      clinic: clinic, // م35 — الاكتساح محصور بعيادة الملف.
    );
    ref.read(patientsRevProvider.notifier).state++;
    // ترحيل treatmentPlans مع الاسم يكتب app.config — نبضة الإعدادات.
    ref.read(configRevProvider.notifier).state++;
    if (nameCtl.text.trim() != name && mounted) {
      // الاسم تغير — أعد فتح الملف بالاسم الجديد.
      final nn = nameCtl.text.trim();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PatientProfileScreen(
            // م90 — الهاتف لم يتغيّر بإعادة التسمية: الهوية تُورَّث.
            patientName: nn,
            clinic: clinic,
            identity: widget.identity,
          ),
        ),
      );
    } else {
      setState(() {});
    }
    _snackMsg('تم تحديث بيانات المريض');
  }

  /// حذف المريض — deletePatientData حرفياً بعدّاد حماية المرضى.
  Future<void> _deletePatient() async {
    // م142 — البوابة كانت غائبة عن حذف المريض: نضيف صلاحية حذف السجلات.
    if (!gateStaff(context, 'records.delete')) return;
    final repos = ref.read(reposProvider);
    // م35 — الحذف معزول بالعيادة، وم-عزل الهوية — معزولٌ بالهوية أيضاً:
    // عدّ صفوف هذه الهوية وحدها فلا يعرض العدّاد صفوف السميّ.
    final idNow = _identityNow();
    final idPhone = _medPhone();
    bool mine(JMap r) =>
        r['name'] == name && _inClinic(r) && rowMatchesIdentity(r, idNow);
    final patRecs = repos.records.getAll().where(mine).length;
    final patPros = repos.prosthetics.getAll().where(mine).length;
    final patDebts = repos.debts.getAll().where(mine).length;
    // م142 — عدد صور الأشعة (يُحسب قبل تجريد config كي يطابق الفعلي المحذوف).
    // م-عزل الهوية — بمعرض الهوية (سطل «اسم|هاتف») + الاسم القديم.
    final cfg = ref.read(appConfigProvider);
    final imgs = xrayKeysFor(cfg, name, phone: idPhone).length;
    final ok = await confirmDelete(
      context,
      config: cfg,
      type: 'pat',
      title: clinic.isEmpty
          ? 'حذف جميع بيانات المريض «$name»؟'
          : 'حذف بيانات المريض «$name» في «$clinic»؟',
      msg:
          'سيتم حذف:\n'
          '• $patRecs سجل علاج\n'
          '• $patPros سجل تركيبات\n'
          '• $patDebts سجل ديون\n'
          '• $imgs صورة أشعة\n'
          'إجمالي: ${patRecs + patPros}\n'
          'لا يمكن التراجع عن هذا الحذف',
    );
    if (!ok || !mounted) return;
    final meter = ref.read(storageMeterProvider); // م142
    deletePatientData(
      repos,
      ref.read(appConfigProvider),
      name: name,
      clinic: clinic,
      // م-عزل الهوية — الحذف يرشّح بالهوية والهاتف: بيانات السميّ لا تُمس.
      identity: idNow,
      phone: idPhone,
      db: ref.read(localDbProvider), // م142 — حارس المحذوف + طابور R2
      meter: meter, // م142 — تحرير الحصة
    );
    ref.read(configRevProvider.notifier).state++;
    ref.read(patientsRevProvider.notifier).state++;
    // م142 — متصل ⇒ تصريف طابور حذف R2 فوراً + تبليغ الخادم بالقياس الجديد.
    if (ref.read(syncContextProvider).isOnline()) {
      unawaited(ref.read(xrayUploadQueueProvider)?.drainNow() ?? Future.value());
    }
    unawaited(meter.reportUp());
    _snackMsg('تم حذف جميع بيانات المريض: $name');
    Navigator.of(context).maybePop();
  }

  // ═══ م10-ج: مساعدات الواجهة والأفعال ═══

  static const _tcColors = [
    (Color(0x10EAB308), Color(0x26EAB308), Color(0xFFEAB308)),
    (Color(0x101B5E47), Color(0x261B5E47), Color(0xFF15604A)),
    (Color(0x1022C55E), Color(0x2622C55E), Color(0xFF22C55E)),
    (Color(0x10A855F7), Color(0x26A855F7), Color(0xFFA855F7)),
    (Color(0x10F97316), Color(0x26F97316), Color(0xFFF97316)),
    (Color(0x10EC4899), Color(0x26EC4899), Color(0xFFEC4899)),
  ];

  /// م65 — عنصر الخلاصة المضغوطة في شريط الملخص المطوي.
  Widget _miniStat(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: TextStyle(fontSize: 10.5, color: BrandColors.mut2),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _miniDot() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text('•', style: TextStyle(fontSize: 11, color: BrandColors.faint)),
  );

  Widget _ppStat(
    String label,
    String value,
    String cur,
    Color color, {
    required Key key,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: .22)),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: BrandColors.mut2),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              Text(
                cur,
                style: TextStyle(fontSize: 11.5, color: BrandColors.mut2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tcCard(TreatmentCardGroup c, String Function(Object?) n) {
    final colors = _tcColors[c.colorIdx];
    return InkWell(
      key: Key('tc-card-${c.service}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openTreatmentDetail(c, n),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.$1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.$2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              c.service,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: colors.$3,
              ),
            ),
            Text(
              n(c.paidTotal),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: colors.$3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secTab(String id, String label, IconData icon) {
    final on = activeSection == id;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5),
        child: Material(
          color: on ? BrandColors.goldDark : BrandColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: on ? BrandColors.goldDark : BrandColors.line,
            ),
          ),
          child: InkWell(
            key: Key('psec-$id'),
            borderRadius: BorderRadius.circular(24),
            onTap: () => setState(() => activeSection = id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 12,
                    color: on ? Colors.white : BrandColors.mut,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: on ? Colors.white : BrandColors.mut,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// نافذة تفصيل معالجة — قائمة السجلات وأقساطها (getTreatmentPayments).
  void _openTreatmentDetail(TreatmentCardGroup c, String Function(Object?) n) {
    final cur = ref.read(currencyProvider);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: Key('tc-detail-${c.service}'),
        title: Row(
          children: [
            Expanded(
              child: Text(c.service, style: const TextStyle(fontSize: 15)),
            ),
            Text(
              '${n(c.paidTotal)} $cur',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: BrandColors.goldDark,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final r in c.records)
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: BrandColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: BrandColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.date.isEmpty ? '—' : r.date,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${n(r.paid)} / ${n(r.amount)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: r.paid >= r.amount
                                  ? const Color(0xFF16A34A)
                                  : BrandColors.red,
                            ),
                          ),
                        ],
                      ),
                      if (r.isPros)
                        Text(
                          'المخبر ${n(r.labValue)} · الطبيب ${n(r.doctorShare)} · العيادة ${n(r.clinicShare)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: BrandColors.mut2,
                          ),
                        ),
                      if (r.debt != null &&
                          (r.debt!['installments'] is List) &&
                          (r.debt!['installments'] as List).isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'الدفعات:',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.mut,
                          ),
                        ),
                        for (final inst
                            in (r.debt!['installments'] as List)
                                .whereType<Map>()
                                .toList()
                                .reversed)
                          Text(
                            '· ${inst['date'] ?? ''} — ${n(jsNumOr0(inst['amount']))} $cur',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: BrandColors.mut2,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  /// م64 — سجل التعديلات (توأم openHistory + audit-box في RecordRow.vue):
  /// يقرأ مصفوفة _audit من القيد ويعرض القيود الأحدث أولاً ({الحقل،
  /// من ← إلى، الوقت}). فارغة ⇒ رسالة «لا توجد تعديلات مسجلة».
  void _showAuditLog(JMap e) {
    final raw = e['_audit'];
    final entries = <JMap>[
      for (final a in (raw is List ? raw : const []))
        if (a is Map) Map<String, Object?>.from(a),
    ]..sort((a, b) => jsNumOr0(b['at']).compareTo(jsNumOr0(a['at'])));

    String fmtWhen(Object? at) {
      final ms = jsNumOr0(at).toInt();
      if (ms <= 0) return '';
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BrandColors.surface,
        title: const Text(
          'سجل التعديلات',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 320,
          child: entries.isEmpty
              ? Text(
                  'لا توجد تعديلات مسجّلة لهذا السجل.',
                  style: TextStyle(fontSize: 12.5, color: BrandColors.mut2),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final a in entries)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: BrandColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: BrandColors.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${a['label'] ?? a['field'] ?? ''}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  fmtWhen(a['at']),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: BrandColors.mut2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${a['old'] ?? '—'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: BrandColors.red,
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Icon(
                                    Icons.arrow_back_rounded,
                                    size: 13,
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    '${a['new'] ?? '—'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: BrandColors.green,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  /// تعديل قيد — نافذة الأصل: تاريخ/نوع المعالجة (محروس عند وجود
  /// دفعات أو دين)/طريقة الدفع/القيمة/قيمة المعمل بمعاينة الحصص الحية
  /// من اللقطة المجمدة.
  Future<void> _editEntryAmount(JMap e) async {
    // م119 — تعديل السجلات صلاحية مستقلة.
    if (!gateStaff(context, 'records.edit')) return;
    final isP = e['_kind'] == 'p';
    final cfg = ref.read(appConfigProvider);
    final payments = [
      for (final pm in (cfg['payments'] as List? ?? const [])) '$pm',
    ];
    final services = [
      for (final sv in (cfg['services'] as List? ?? const []))
        if ('$sv' != 'تركيبات') '$sv',
    ];
    // الحارس: لا تغيير للنوع عند وجود دين مرتبط (دفعات/رصيد) — الأصل.
    final hasLinkedDebt = ref
        .read(reposProvider)
        .debts
        .getAll()
        .any(
          (d) => isP ? d['prostheticId'] == e['id'] : d['recordId'] == e['id'],
        );
    final canChangeService = !isP && !hasLinkedDebt;

    final amountCtl = TextEditingController(
      text: jsNumOr0(isP ? e['total'] : e['amount']).toStringAsFixed(0),
    );
    final labCtl = TextEditingController(
      text: jsNumOr0(e['labValue']).toStringAsFixed(0),
    );
    var date = '${e['date'] ?? ''}';
    var payment = '${e['payment'] ?? ''}';
    var service = '${e['service'] ?? ''}';
    // نسبة المعاينة: اللقطة المجمدة أو نسبة تركيبات العيادة الحالية.
    final snap = e['_rateSnapshot'];
    final snapPct = snap is Map ? num.tryParse('${snap['doctorPct']}') : null;
    final prosPct =
        snapPct ??
        resolveDoctorPct(cfg, clinic: '${e['clinic'] ?? ''}', isPros: true);

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDlg) {
          final amount = jsNumOr0(amountCtl.text);
          final lab = jsNumOr0(labCtl.text);
          final net = (amount - lab).clamp(0, double.infinity);
          final doc = net * (prosPct / 100);
          return AlertDialog(
            title: Text(
              'تعديل ${isP ? 'تركيبة' : 'سجل'}',
              style: const TextStyle(fontSize: 15),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    key: const Key('edit-date-btn'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.tryParse(date) ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setDlg(
                          () => date =
                              '${picked.year.toString().padLeft(4, '0')}-'
                              '${picked.month.toString().padLeft(2, '0')}-'
                              '${picked.day.toString().padLeft(2, '0')}',
                        );
                      }
                    },
                    icon: const Icon(Icons.event_rounded, size: 14),
                    label: Text(
                      date.isEmpty ? 'التاريخ' : date,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (canChangeService && services.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: const Key('edit-service'),
                      initialValue: services.contains(service) ? service : null,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'نوع المعالجة',
                      ),
                      items: [
                        for (final sv in services)
                          DropdownMenuItem(value: sv, child: Text(sv)),
                      ],
                      onChanged: (v) => setDlg(() => service = v ?? service),
                    )
                  else if (!isP)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: BrandColors.gold.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'لا يمكن تغيير نوع المعالجة لأن هذه العملية تحتوي على دفعات أو رصيد دين.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFFA16207),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (payments.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: const Key('edit-payment'),
                      initialValue: payments.contains(payment) ? payment : null,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'طريقة الدفع',
                      ),
                      items: [
                        for (final pm in payments)
                          DropdownMenuItem(value: pm, child: Text(pm)),
                      ],
                      onChanged: (v) => setDlg(() => payment = v ?? payment),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('edit-amount-input'),
                    controller: amountCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: isP ? 'الإجمالي' : 'القيمة',
                    ),
                    onChanged: (_) => setDlg(() {}),
                  ),
                  if (isP) ...[
                    const SizedBox(height: 8),
                    TextField(
                      key: const Key('edit-lab-input'),
                      controller: labCtl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'قيمة المعمل',
                      ),
                      onChanged: (_) => setDlg(() {}),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: BrandColors.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: BrandColors.line),
                      ),
                      child: Column(
                        children: [
                          _prevRow('الصافي:', formatNumber(net)),
                          _prevRow('حصة الطبيب:', formatNumber(doc)),
                          _prevRow('حصة العيادة:', formatNumber(net - doc)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                key: const Key('edit-amount-save'),
                style: FilledButton.styleFrom(
                  backgroundColor: BrandColors.gold,
                  foregroundColor: BrandColors.brand900,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    // م102 — تغيير تاريخ السجل: أين يُحسب الإيراد؟ (نفس تنبيه م101 —
    // كل مبلغ يُحسب في يومٍ واحد بالضبط؛ الإلغاء = لا حفظ).
    String? incomeDay;
    if (date != '${e['date'] ?? ''}') {
      if (!mounted) return;
      final picked = await askIncomeDay(context, date);
      if (picked == null) return;
      // م104 — يوم الاحتساب مقفول؟ تنبيه ومتابعة بالتأكيد فقط.
      if (!mounted) return;
      if (!await confirmClosedDayWrite(
        context,
        ref.read(reposProvider).settings,
        picked,
      )) {
        return;
      }
      // اختيار «بتاريخ السجل» = مسح الحقل؛ «إيراد اليوم» = تعيينه.
      incomeDay = picked == date ? '' : picked;
    }
    updateRecAmount(
      ref.read(reposProvider),
      ref.read(appConfigProvider),
      id: '${e['id']}',
      type: isP ? 'p' : 'r',
      newAmount: jsNumOr0(amountCtl.text),
      labValue: isP ? jsNumOr0(labCtl.text) : null,
      date: date,
      payment: payment,
      service: canChangeService ? service : null,
      incomeDate: incomeDay,
    );
    ref.read(patientsRevProvider.notifier).state++;
    ref.read(financeRevProvider.notifier).state++;
    setState(() {});
    _snackMsg('تم تعديل القيمة');
  }

  Widget _prevRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
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
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  /// حذف قيد — delRec بعدّاد dcConfirm نوع السجلات.
  Future<void> _deleteEntry(JMap e) async {
    // م119 — حذف السجلات صلاحية مستقلة.
    if (!gateStaff(context, 'records.delete')) return;
    final ok = await confirmDelete(
      context,
      config: ref.read(appConfigProvider),
      type: 'rec',
      title: 'حذف السجل',
      msg: 'هل أنت متأكد من حذف هذا السجل؟',
    );
    if (!ok) return;
    deleteEntryCascade(
      ref.read(reposProvider),
      ref.read(appConfigProvider),
      id: '${e['id']}',
      source: e['_kind'] == 'p' ? 'p' : 'r',
    );
    ref.read(patientsRevProvider.notifier).state++;
    ref.read(financeRevProvider.notifier).state++;
    setState(() {});
    _snackMsg('تم حذف السجل');
  }

  void _snackMsg(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// المعلومات الطبية — نفس محرر الرئيسية على config.patientMedical.
  Future<void> _openMedical() async {
    // م121 — حارس دفاعي: المعلومات الطبية بصلاحيتها.
    if (!gateStaff(context, 'patients.medical')) return;
    final cfg = ref.read(appConfigProvider);
    // م96 — عزل هوياتي كامل: عيادة + هاتف (لا قراءة عارية بالاسم).
    final saved = medicalScopedRead(
      cfg['patientMedical'],
      name,
      clinic,
      _medPhone(),
      rowPhone: _rowPhone(),
    );
    final result = await showMedicalInfoDialog(
      context,
      patientName: name,
      initial: saved is Map ? Map<String, Object?>.from(saved) : const {},
    );
    if (result == null || !mounted) return;
    final repos = ref.read(reposProvider);
    final cur = Map<String, Object?>.from(ref.read(appConfigProvider));
    // م96 — الكتابة لمفتاح الهوية (اسم|عيادة|هاتف) وحده.
    repos.settings.set('app.config', {
      ...cur,
      'patientMedical': medicalScopedWrite(
        cur['patientMedical'],
        name,
        clinic,
        _medPhone(),
        result,
        rowPhone: _rowPhone(),
      ),
    });
    ref.read(configRevProvider.notifier).state++;
    _snackMsg('تم حفظ المعلومات الطبية');
  }

  /// طباعة ملف المريض — قالب الأصل الكامل (الشعار + بيانات المريض +
  /// سجل الخدمات والمدفوعات + المجاميع + التواقيع + التذييل).
  Future<void> _printPatientSummary() async {
    final repos = ref.read(reposProvider);
    final cfg = ref.read(appConfigProvider);
    final cur = ref.read(currencyProvider);
    final agg =
        patientForClinic(
          name,
          clinic,
          records: repos.records.getAll(),
          prosthetics: repos.prosthetics.getAll(),
          debts: repos.debts.getAll(),
          // م-عزل الهوية — الطباعة تعزل التجميعة بهوية الملف المفتوح أيضاً.
          identity: _identityNow(),
        ) ??
        PatientAgg(name);
    final debts = _debts;
    final entries = [
      ..._records
          .where((r) => !jsTruthy(r['isDebtPayment']))
          .map((r) => ({...r, '_kind': 'r'})),
      ..._pros.map((p) => ({...p, '_kind': 'p'})),
    ]..sort(byDateNewestFirst); // م114 — الأحدث أعلى في الطباعة أيضاً.

    final phone = () {
      for (final e in agg.entries) {
        if (jsTruthy(e['phone'])) return '${e['phone']}';
      }
      return '';
    }();

    final rows = [
      for (final e in entries)
        () {
          final isP = e['_kind'] == 'p';
          JMap? debt;
          for (final d in debts) {
            if (isP ? d['prostheticId'] == e['id'] : d['recordId'] == e['id']) {
              debt = d;
              break;
            }
          }
          final amount = jsNumOr0(isP ? e['total'] : e['amount']);
          final paid = debt != null ? jsNumOr0(debt['paidAmount']) : amount;
          return (
            date: '${e['date'] ?? ''}',
            service: '${e['service'] ?? 'تركيبة'}',
            teeth: summarizeTeethRefs(
              // م104 — نفس تلخيص بطاقة الملف حرفياً في الورقة المطبوعة:
              // مجموعات ربعية بالمدى، بنظام العرض المُزامَن.
              [
                for (final t in _teethStructured(e))
                  (q: t.q, n: t.n, primary: t.p),
              ],
              system: ref.read(notationSystemProvider),
            ),
            // م105 — الشبكة الصليبية عند تعدد الأرباع (تتقدم على المجموعات).
            cross: toothCrossModel([
              for (final t in _teethStructured(e))
                (q: t.q, n: t.n, primary: t.p),
            ], system: ref.read(notationSystemProvider)),
            payment: '${e['payment'] ?? ''}',
            paid: paid,
            debt: debt != null ? jsNumOr0(debt['remaining']) : 0,
          );
        }(),
    ];

    final fonts = await loadPdfBrand(ref);
    // v50 — شعار أبيض/أسود في الورقة الرسمية (تحويل رمادية قبل البناء).
    pdfLogoBytes = await grayscalePngBytes(pdfLogoBytes);
    // v50 — المعلومات الطبية المحفوظة تُطبع فوق الجدول (م96: مفتاح الهوية).
    final med = medicalScopedRead(
      cfg['patientMedical'],
      name,
      clinic,
      _medPhone(),
      rowPhone: _rowPhone(),
    );
    final bytes = await patientFilePdf(
      fonts,
      centerName: '${jsOr(cfg['centerName'], 'عيادة الأسنان')}',
      patientName: name,
      // م127 — فحص المنظومة: الهاتف محجوب بالشاشة فيُحجب بالطباعة أيضاً.
      phone: staffAllowed('patients.phones') ? phone : '—',
      visitCount: agg.visitCount,
      currency: cur,
      reportDate: getCurrentDate(),
      rows: rows,
      totalServices: agg.grossTotal,
      totalPaid: agg.total,
      totalRemaining: agg.debtRemaining,
      medical: med is Map ? Map<String, Object?>.from(med) : null,
    );
    final msg = await printOrSharePdf(
      ref.read(dbDirProvider),
      bytes,
      'patient_$name.pdf',
      // م79 — تصدير ملف مريض كامل أثقل حدث إخراج بيانات في التطبيق.
      auditDb: ref.read(localDbProvider),
      auditEntity: 'patients',
      auditId: name,
    );
    if (mounted) _snackMsg(msg);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 5,
                  height: 17,
                  decoration: BoxDecoration(
                    color: BrandColors.gold,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: BrandColors.brand900,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            child,
          ],
        ),
      ),
    );
  }
}
