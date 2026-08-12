/// ============================================================================
///  شاشة السجلات — نسخة سطح المكتب: Master/Detail
/// ============================================================================
///
///  (قرار المالك): تخطيط منقسم دائم — القائمة على اليمين (RTL) دائمة
///  الظهور مع بحث وفلتر عيادة، والتفاصيل على اليسار تعرض ملف المريض
///  الكامل عند الاختيار دون فتح صفحة جديدة. يستهلك DesktopSplitView
///  وDetailHost من split_view.dart لتوحيد النمط مع بقية الشاشات.
///
///  م(تكافؤ الهاتف): هذه الشاشة توأمُ ثلاثية الهاتف (بوابة العيادات +
///  مرضى العيادة في patients_tab.dart): بطاقات عيادات مكتبية أنيقة
///  بإحصاءات الشهر المختار، ومسار البحث/الفرز/الفلاتر الموحد عبر دوال
///  patients_logic.dart حرفياً (filterClinicPatients + clinicPatients)،
///  وشارات الصف (دين/تركيبات/تقرير/مؤرشف)، وقائمة سياق كاملة بصلاحيات
///  الهاتف نفسها، وتحديد جماعي بشريط أرشفة. لا منطق جديد — إعادة استخدام.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../patients/archive_store.dart' show PatientArchiveStore;
import '../../patients/clinic_scope.dart' show clinicScopedKey;
import '../../patients/patient_profile_screen.dart'
    show PatientProfileScreen;
import '../../patients/patients_logic.dart'
    show
        ClinicCard,
        ClinicPatientRow,
        PatientAgg,
        clinicCards,
        clinicPatients,
        clinicSortLabels,
        editPatientCascade,
        filterClinicPatients,
        rowMatchesIdentity;
import '../../patients/patients_tab.dart'
    show
        addVisitDraftProvider,
        homeJumpProvider,
        patientMapProvider,
        patientsRevProvider;
import '../../patients/quick_visit_sheet.dart' show showQuickVisitSheet;
import '../../finance/analyses_registry.dart' show AnalysesRegistryCard;
import '../../print/treatment_tables.dart' show formatNumber;
// م168 — مدخل السجل يظهر بالتفعيل أو بوجود تاريخٍ ظاهر (قبل الإيقاف).
import '../../settings/analyses3.dart' show triHasVisibleHistory;
import '../../staff/staff_gate.dart' show gateStaff, staffAllowed;
import '../desktop_prefs.dart'
    show desktopPrefsProvider, saveDesktopPref;
import '../widgets/context_menu.dart'
    show CtxItem, ContextMenuRegion;
import '../widgets/split_view.dart'
    show DesktopSplitView, DetailHost;

// ── ثوابت الحجم ─────────────────────────────────────────────────────────────

/// ارتفاع بند المريض المضغوط — ثابت للأداء مع ListView.builder.
/// (نُزّل 64→44: صفٌّ نحيل بأفاتار 28 وشارات 16 وسطر ثانوي نحيف بلا فراغ
/// مهدور، فيبين ضِعفُ عددِ المرضى في نفس ارتفاع اللوح.)
const _kItemHeight = 44.0;

/// مفتاح حفظ حالة طيّ شريط العيادات (توأم `split.<id>` — محلي للجهاز).
const _kClinicStripExpandedKey = 'records.clinicStrip.expanded';

// ============================================================================
//  الشاشة الرئيسية
// ============================================================================

class DesktopRecordsScreen extends ConsumerStatefulWidget {
  const DesktopRecordsScreen({super.key});

  @override
  ConsumerState<DesktopRecordsScreen> createState() =>
      _DesktopRecordsScreenState();
}

class _DesktopRecordsScreenState
    extends ConsumerState<DesktopRecordsScreen> {
  // ── حالة البحث والفلاتر ──────────────────────────────────────────────────

  /// نص البحث الفوري (اسم أو هاتف).
  final _searchCtl = TextEditingController();
  final _searchFocus = FocusNode();

  /// العيادة المختارة للفلترة — null = كل العيادات.
  String? _clinicFilter;

  /// وضع بحث الهاتف بالأرقام (مبدّل — توأم phoneMode في الهاتف).
  bool _phoneMode = false;

  /// نمط الفرز — أحد مفاتيح clinicSortLabels (الافتراضي الأحدث نشاطاً).
  String _sortBy = 'activity';

  /// م64 — فلتر «عليه دين/متبقٍ فقط».
  bool _debtOnly = false;

  /// م75 — إظهار المؤرشفين في القائمة والبحث (مخفيون افتراضياً).
  bool _showArchived = false;

  // ── حالة التحديد الجماعي (م75) ────────────────────────────────────────────

  /// وضع التحديد المتعدد.
  bool _selectMode = false;

  /// مفاتيح (اسم|عيادة) المحدَّدين.
  final Set<String> _selected = {};

  // ── حالة الاختيار (Master/Detail) ────────────────────────────────────────

  /// المريض المختار حالياً (null = لم يختر بعد).
  PatientAgg? _selectedAgg;

  /// م155 — سجل التحاليل الثلاثية مفتوحاً في اللوح التفصيلي (يستبعد
  /// اختيار مريض والعكس — لوحٌ واحد لعرضٍ واحد).
  bool _analysesOpen = false;

  /// م(طباعة) — عند فتح الملف من فعل «طباعة ملف المريض» نُمرر autoPrint.
  bool _selectedAutoPrint = false;

  // ── حالة لوحة المفاتيح لأسهم التنقل ─────────────────────────────────────

  /// فهرس البند المحدد لوحياً (عبر أسهم ↑/↓) — null = لا تحديد لوحي.
  int? _keyboardIndex;

  /// تجاوزٌ محليٌّ لحالة طيّ شريط العيادات — null = اتبع المحفوظ (توأم نمط
  /// split_view: التجاوز المحلي يتقدّم على القرص كي يبين الأثر فوراً بلا
  /// وميض، والافتراضي المطويّ حين لا محفوظ ولا تجاوز).
  bool? _clinicStripExpanded;

  @override
  void dispose() {
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── مخزن الأرشفة ──────────────────────────────────────────────────────────

  PatientArchiveStore get _archive =>
      PatientArchiveStore(ref.read(reposProvider).settings);

  /// مفتاح المريض المعزول بالعيادة (م35) — نفس مفتاح بقية بياناته.
  String _pkey(ClinicPatientRow p) =>
      clinicScopedKey(p.agg.name, p.agg.clinic);

  // ── بناء قائمة المرضى المفلترة ───────────────────────────────────────────

  /// يبني صفوف المرضى بعد تطبيق فلتر العيادة والبحث والفرز والفلاتر —
  /// عبر مسار الهاتف نفسه (clinicPatients + filterClinicPatients) حرفياً،
  /// موحّداً فرعَ العيادة الواحدة وفرعَ «كل العيادات» بالدالة ذاتها.
  List<ClinicPatientRow> _buildRows(WidgetRef ref) {
    final repos = ref.read(reposProvider);
    final patientMap = ref.watch(patientMapProvider);
    final clinics = ref.watch(clinicsProvider);
    final records = repos.records.getAll().cast<Map<String, Object?>>();
    final prosthetics =
        repos.prosthetics.getAll().cast<Map<String, Object?>>();
    final debts = repos.debts.getAll().cast<Map<String, Object?>>();
    final archivedKeys = _archive.archivedKeys(); // م75

    // م35 — العيادات المشمولة: المختارة وحدها أو كلها عند «كل العيادات».
    final scope = _clinicFilter != null ? [_clinicFilter!] : clinics;
    final rows = <ClinicPatientRow>[
      for (final c in scope)
        ...clinicPatients(
          c,
          patientMap: patientMap,
          records: records,
          prosthetics: prosthetics,
          debts: debts,
          archivedKeys: archivedKeys, // م75 — كالهاتف patients_tab:555
        ),
    ];

    // نفس دالة الهاتف: بحث ضبابي/هاتف أولاً، وإلا الفرز المختار، مع
    // فلتري الدين والمؤرشفين. عند «كل العيادات» نحافظ على ترتيب الدمج
    // ثم نُعيد الفرز الموحد فوق المجموع (فالنتيجة مرتبة كصفٍّ واحد).
    return filterClinicPatients(
      rows,
      query: _searchCtl.text,
      phoneMode: _phoneMode,
      sortBy: _sortBy,
      debtOnly: _debtOnly, // م64
      showArchived: _showArchived, // م75
    );
  }

  // ── الاختيار ─────────────────────────────────────────────────────────────

  /// يختار مريضاً ويعرض ملفه في القسم الأيسر دون فتح صفحة.
  /// [autoPrint] — يفتح الطباعة مباشرة في اللوح التفصيلي (فعل «طباعة الملف»).
  void _select(PatientAgg agg, {bool autoPrint = false}) {
    setState(() {
      _selectedAgg = agg;
      _selectedAutoPrint = autoPrint;
      _analysesOpen = false; // م155 — اختيار مريض يغلق سجل التحاليل.
      _keyboardIndex = null; // إعادة تعيين التحديد اللوحي
    });
  }

  /// م155 — فتح سجل التحاليل الثلاثية في اللوح التفصيلي.
  void _openAnalyses() {
    setState(() {
      _analysesOpen = true;
      _selectedAgg = null;
      _keyboardIndex = null;
    });
  }

  // ── التحديد الجماعي (م75) ────────────────────────────────────────────────

  void _exitSelect() => setState(() {
        _selectMode = false;
        _selected.clear();
      });

  void _toggleSelect(ClinicPatientRow p) => setState(() {
        final k = _pkey(p);
        if (!_selected.remove(k)) _selected.add(k);
        if (_selected.isEmpty) _selectMode = false;
      });

  void _enterSelect(ClinicPatientRow p) => setState(() {
        _selectMode = true;
        _selected
          ..clear()
          ..add(_pkey(p));
      });

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  // ── أفعال الصف (توأم لوحة إجراءات الهاتف) ─────────────────────────────────

  /// زيارة سريعة جديدة — ورقة الزيارة السريعة نفسها (م58 حرفياً).
  void _addVisit(ClinicPatientRow p) {
    // م119 — إضافة الزيارات صلاحية مستقلة.
    if (!gateStaff(context, 'records.add')) return;
    final phones = p.phones.split(' ');
    final phone = phones.isNotEmpty ? phones.first : '';
    showQuickVisitSheet(
      context,
      name: p.agg.name,
      clinic: p.agg.clinic,
      phone: phone,
      onFullOptions: () => _addVisitFull(p),
    );
  }

  /// المسار القديم — توأم router.push home {patient, clinic}.
  void _addVisitFull(ClinicPatientRow p) {
    final phones = p.phones.split(' ');
    ref.read(addVisitDraftProvider.notifier).state = {
      'name': p.agg.name,
      'clinic': p.agg.clinic,
      'phone': phones.isNotEmpty ? phones.first : '',
    };
    ref.read(homeJumpProvider.notifier).state++;
  }

  /// تعديل بيانات المريض — الاسم والهاتفان باكتساح الجداول الأربعة عبر
  /// editPatientCascade نفسها (منطق الهاتف حرفياً؛ الحوار المكتبي غلاف).
  Future<void> _editPatient(ClinicPatientRow p) async {
    final repos = ref.read(reposProvider);
    // م-عزل الهوية — التعبئة من صفوف هذه الهوية وحدها (لا هاتف السميّ).
    final all = [
      ...repos.records.getAll(),
      ...repos.prosthetics.getAll(),
      ...repos.debts.getAll(),
    ]
        .where((r) =>
            r['name'] == p.agg.name && rowMatchesIdentity(r, p.agg.identity))
        .toList()
      ..sort((a, b) =>
          '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'));
    String firstWith(String key) {
      for (final r in all) {
        final v = r[key];
        if (v != null && '$v'.trim().isNotEmpty) return '$v';
      }
      return '';
    }

    final nameCtl = TextEditingController(text: p.agg.name);
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
              key: const Key('dr-edit-pat-name'),
              controller: nameCtl,
              decoration: const InputDecoration(
                  isDense: true, labelText: 'الاسم'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('dr-edit-pat-phone'),
              controller: phoneCtl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  isDense: true, labelText: 'رقم الهاتف'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('dr-edit-pat-phone2'),
              controller: phone2Ctl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  isDense: true, labelText: 'رقم ثانٍ'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              key: const Key('dr-edit-pat-save'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final touched = editPatientCascade(
      repos,
      origName: p.agg.name,
      newName: nameCtl.text,
      phone: phoneCtl.text.trim(),
      phone2: phone2Ctl.text.trim(),
      clinic: p.agg.clinic, // م35 — محصور بعيادة الصف.
      identity: p.agg.identity, // م-عزل الهوية — لا يمسّ السميّ.
    );
    ref.read(patientsRevProvider.notifier).state++;
    ref.read(configRevProvider.notifier).state++;
    _snack('تم تحديث بيانات المريض ($touched صفاً)');
  }

  /// حوار تأكيد الأرشفة — يوضّح صراحةً أن المال والمعالجات لا تتأثر
  /// (توأم _confirmArchive في الهاتف حرفياً في النص والسلوك).
  Future<void> _confirmArchive(List<ClinicPatientRow> pts) async {
    if (pts.isEmpty) return;
    final count = pts.length;
    final title = count == 1
        ? 'أرشفة «${pts.first.agg.name}»؟'
        : 'أرشفة $count مرضى؟';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800)),
        content: const Text(
          'سيختفون من القائمة والبحث، ويمكن إظهارهم في أي وقت من '
          '«إظهار المؤرشفين». معالجاتهم وأموالهم لا تتأثر إطلاقاً، '
          'ويعودون تلقائياً عند أول زيارة جديدة.',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
            key: const Key('dr-archive-confirm'),
            style:
                FilledButton.styleFrom(backgroundColor: BrandColors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final targets = [
      for (final p in pts) (name: p.agg.name, clinic: p.agg.clinic),
    ];
    _archive.archiveAll(targets);
    _exitSelect();
    ref.read(patientsRevProvider.notifier).state++;

    // تراجع فوري — الأرشفة قرار سريع، ورجعتها يجب أن تكون أسرع.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content:
            Text(count == 1 ? 'أُرشف مريض' : 'أُرشف $count مرضى'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () {
            _archive.unarchiveAll(targets);
            ref.read(patientsRevProvider.notifier).state++;
          },
        ),
      ));
  }

  void _unarchiveOne(ClinicPatientRow p) {
    _archive.unarchive(p.agg.name, p.agg.clinic);
    ref.read(patientsRevProvider.notifier).state++;
    _snack('أُلغيت أرشفة «${p.agg.name}»');
  }

  /// أفعال الشريط الجماعي على المحدَّدين حسب حالتهم.
  void _archiveSelected(List<ClinicPatientRow> visible) {
    final pts =
        [for (final p in visible) if (_selected.contains(_pkey(p))) p];
    _confirmArchive([for (final p in pts) if (!p.archived) p]);
  }

  void _unarchiveSelected(List<ClinicPatientRow> visible) {
    final pts = [
      for (final p in visible)
        if (_selected.contains(_pkey(p)) && p.archived) p,
    ];
    _archive.unarchiveAll(
        [for (final p in pts) (name: p.agg.name, clinic: p.agg.clinic)]);
    final c = pts.length;
    _exitSelect();
    ref.read(patientsRevProvider.notifier).state++;
    _snack(c == 1 ? 'أُلغيت أرشفة مريض' : 'أُلغيت أرشفة $c مرضى');
  }

  // ── قائمة سياق البند ─────────────────────────────────────────────────────

  /// يبني عناصر قائمة السياق للبند المختار — بصلاحيات الهاتف نفسها.
  List<CtxItem> _itemMenu(ClinicPatientRow p) {
    final agg = p.agg;
    return [
      CtxItem(
        'فتح الملف',
        icon: Icons.person_rounded,
        keyId: 'records-open-profile',
        onTap: () => _select(agg),
      ),
      // زيارة سريعة جديدة — بصلاحية records.add كالهاتف.
      if (staffAllowed('records.add'))
        CtxItem(
          'زيارة سريعة جديدة',
          icon: Icons.add_circle_rounded,
          keyId: 'records-quick-visit',
          onTap: () => _addVisit(p),
        ),
      // تعديل البيانات — اكتساح الاسم/الهاتفين (editPatientCascade).
      if (staffAllowed('records.edit'))
        CtxItem(
          'تعديل البيانات',
          icon: Icons.edit_rounded,
          keyId: 'records-edit-patient',
          onTap: () => _editPatient(p),
        ),
      // طباعة ملف المريض — يفتح الملف في اللوح مع autoPrint=true (توأم
      // الهاتف: PatientProfileScreen(autoPrint: true)).
      CtxItem(
        'طباعة ملف المريض',
        icon: Icons.print_rounded,
        keyId: 'records-print-profile',
        onTap: () => _select(agg, autoPrint: true),
      ),
      CtxItem(
        'نسخ الاسم',
        icon: Icons.copy_rounded,
        keyId: 'records-copy-name',
        onTap: () {
          Clipboard.setData(ClipboardData(text: agg.name));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('نُسخ الاسم: ${agg.name}'),
              duration: const Duration(milliseconds: 1400),
            ),
          );
        },
      ),
      CtxItem.divider,
      // أرشفة/إلغاء أرشفة المريض الواحد (بتأكيد) — توأم الهاتف.
      if (p.archived)
        CtxItem(
          'إلغاء الأرشفة',
          icon: Icons.unarchive_rounded,
          keyId: 'records-unarchive',
          onTap: () => _unarchiveOne(p),
        )
      else
        CtxItem(
          'أرشفة المريض',
          icon: Icons.archive_rounded,
          destructive: true,
          keyId: 'records-archive',
          onTap: () => _confirmArchive([p]),
        ),
    ];
  }

  // ── البناء ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // الاستماع لنبضات تحديث المرضى لإعادة البناء تلقائياً.
    ref.watch(patientsRevProvider);

    final repos = ref.watch(reposProvider);
    final clinics = ref.watch(clinicsProvider);
    final month = ref.watch(selectedMonthProvider);
    final cur = ref.watch(currencyProvider);
    final rows = _buildRows(ref);

    // بطاقات العيادات — تُبنى من الدالة الجاهزة clinicCards (تتفاعل مع
    // selectedMonthProvider تلقائياً بحكم ref.watch أعلاه).
    final cards = clinicCards(
      clinics: clinics,
      month: month,
      records: repos.records.getAll(),
      prosthetics: repos.prosthetics.getAll(),
      debts: repos.debts.getAll(),
    );

    // حالة طيّ شريط العيادات: التجاوز المحلي أولاً، ثم المحفوظ، ثم المطويّ
    // افتراضاً (الوضع المضغوط هو السلوك المطلوب عند أول فتح).
    final savedExpanded =
        ref.watch(desktopPrefsProvider)[_kClinicStripExpandedKey];
    final clinicStripExpanded = _clinicStripExpanded ??
        (savedExpanded is bool ? savedExpanded : false);

    // منطقة الاختصارات اللوحية: Ctrl+F للبحث وأسهم التنقل.
    return CallbackShortcuts(
      bindings: {
        // Ctrl+F — تركيز حقل البحث.
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocus.requestFocus();
        },
        // السهم للأعلى — تنقل لأعلى في القائمة.
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (rows.isEmpty) return;
          final cur = _keyboardIndex ?? 0;
          final next = (cur - 1).clamp(0, rows.length - 1);
          setState(() => _keyboardIndex = next);
        },
        // السهم للأسفل — تنقل لأسفل في القائمة.
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (rows.isEmpty) return;
          final cur = _keyboardIndex ?? -1;
          final next = (cur + 1).clamp(0, rows.length - 1);
          setState(() => _keyboardIndex = next);
        },
        // Enter — فتح المريض المحدد لوحياً.
        const SingleActivator(LogicalKeyboardKey.enter): () {
          final idx = _keyboardIndex;
          if (idx != null && idx < rows.length) {
            _select(rows[idx].agg);
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: DesktopSplitView(
          id: 'patients',
          masterWidth: 400,
          minMasterWidth: 320,
          maxMasterWidth: 520,
          emptyIcon: Icons.person_search_rounded,
          emptyTitle: 'اختر مريضاً لعرض التفاصيل',
          emptyHint: 'انقر على مريض من القائمة على اليمين',
          master: _MasterPanel(
            searchCtl: _searchCtl,
            searchFocus: _searchFocus,
            clinics: clinics,
            clinicCards: cards,
            currency: cur,
            clinicFilter: _clinicFilter,
            // م155 — مدخل التحاليل الثلاثية الثابت (خلف علم الميزة).
            // م168 — أو بوجود تاريخٍ ظاهر قبل الإيقاف (عرضٌ تاريخي فقط).
            showAnalysesEntry: triHasVisibleHistory(
              ref.watch(appConfigProvider),
              repos.records.getAll().cast<Map<String, Object?>>(),
            ),
            analysesSelected: _analysesOpen,
            onOpenAnalyses: _openAnalyses,
            clinicStripExpanded: clinicStripExpanded,
            phoneMode: _phoneMode,
            sortBy: _sortBy,
            debtOnly: _debtOnly,
            showArchived: _showArchived,
            rows: rows,
            selectedAgg: _selectedAgg,
            keyboardIndex: _keyboardIndex,
            selectMode: _selectMode,
            selectedKeys: _selected,
            onClinicChanged: (c) => setState(() {
              _clinicFilter = c;
              _keyboardIndex = null;
            }),
            onToggleClinicStrip: () {
              final next = !clinicStripExpanded;
              setState(() => _clinicStripExpanded = next);
              saveDesktopPref(ref, _kClinicStripExpandedKey, next);
            },
            onSearch: () => setState(() => _keyboardIndex = null),
            onPhoneMode: (v) => setState(() => _phoneMode = v),
            onSortBy: (v) => setState(() => _sortBy = v),
            onDebtOnly: (v) => setState(() => _debtOnly = v),
            onShowArchived: (v) => setState(() => _showArchived = v),
            onSelect: (p) => _select(p.agg),
            onToggleSelect: _toggleSelect,
            onEnterSelect: _enterSelect,
            onExitSelect: _exitSelect,
            onArchiveSelected: () => _archiveSelected(rows),
            onUnarchiveSelected: () => _unarchiveSelected(rows),
            pkeyOf: _pkey,
            itemMenuBuilder: _itemMenu,
          ),
          detail: _analysesOpen
              // م155 — سجل التحاليل الثلاثية جدولاً منظماً في اللوح
              // التفصيلي: رقم/تاريخ/اسم/طريقة/قيمة + تعديل وحذف + إجمالي.
              ? DetailHost(
                  hostKey: 'analyses-registry',
                  child: ListView(
                    key: const Key('dr-analyses-pane'),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                    children: const [
                      AnalysesRegistryCard(
                          showIndex: true,
                          showDate: true,
                          inlineTotal: true),
                    ],
                  ),
                )
              : _selectedAgg == null
              ? null
              : DetailHost(
                  // مفتاح فريد لكل مريض/حالة طباعة كي يُعاد بناء الملاح
                  // عند التبديل أو عند طلب طباعة نفس المريض من جديد.
                  hostKey:
                      '${_selectedAgg!.name}|${_selectedAgg!.clinic}|${_selectedAgg!.identity}|$_selectedAutoPrint',
                  child: PatientProfileScreen(
                    patientName: _selectedAgg!.name,
                    clinic: _selectedAgg!.clinic,
                    identity: _selectedAgg!.identity,
                    // م(طباعة) — فتح الطباعة تلقائياً عند فعل «طباعة الملف».
                    autoPrint: _selectedAutoPrint,
                  ),
                ),
        ),
      ),
    );
  }
}

// ============================================================================
//  القسم الأيمن — قائمة المرضى (Master Panel)
// ============================================================================

class _MasterPanel extends StatelessWidget {
  const _MasterPanel({
    required this.searchCtl,
    required this.searchFocus,
    required this.clinics,
    required this.clinicCards,
    required this.currency,
    required this.clinicFilter,
    required this.showAnalysesEntry,
    required this.analysesSelected,
    required this.onOpenAnalyses,
    required this.clinicStripExpanded,
    required this.phoneMode,
    required this.sortBy,
    required this.debtOnly,
    required this.showArchived,
    required this.rows,
    required this.selectedAgg,
    required this.keyboardIndex,
    required this.selectMode,
    required this.selectedKeys,
    required this.onClinicChanged,
    required this.onToggleClinicStrip,
    required this.onSearch,
    required this.onPhoneMode,
    required this.onSortBy,
    required this.onDebtOnly,
    required this.onShowArchived,
    required this.onSelect,
    required this.onToggleSelect,
    required this.onEnterSelect,
    required this.onExitSelect,
    required this.onArchiveSelected,
    required this.onUnarchiveSelected,
    required this.pkeyOf,
    required this.itemMenuBuilder,
  });

  final TextEditingController searchCtl;
  final FocusNode searchFocus;
  final List<String> clinics;
  final List<ClinicCard> clinicCards;
  final String currency;
  final String? clinicFilter;
  final bool showAnalysesEntry;
  final bool analysesSelected;
  final VoidCallback onOpenAnalyses;
  final bool clinicStripExpanded;
  final bool phoneMode;
  final String sortBy;
  final bool debtOnly;
  final bool showArchived;
  final List<ClinicPatientRow> rows;
  final PatientAgg? selectedAgg;
  final int? keyboardIndex;
  final bool selectMode;
  final Set<String> selectedKeys;
  final ValueChanged<String?> onClinicChanged;
  final VoidCallback onToggleClinicStrip;
  final VoidCallback onSearch;
  final ValueChanged<bool> onPhoneMode;
  final ValueChanged<String> onSortBy;
  final ValueChanged<bool> onDebtOnly;
  final ValueChanged<bool> onShowArchived;
  final ValueChanged<ClinicPatientRow> onSelect;
  final ValueChanged<ClinicPatientRow> onToggleSelect;
  final ValueChanged<ClinicPatientRow> onEnterSelect;
  final VoidCallback onExitSelect;
  final VoidCallback onArchiveSelected;
  final VoidCallback onUnarchiveSelected;
  final String Function(ClinicPatientRow) pkeyOf;
  final List<CtxItem> Function(ClinicPatientRow) itemMenuBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border(
          // فاصل بصري خفي بين القسمين (الفاصل الرئيسي في split_view).
          left: BorderSide(color: BrandColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── رأس القسم: عنوان + عداد (يُخفى حين عيادةٌ مفتوحة — م155/ب:
          // اسم الدكتور يحل محله تحت البحث كسلوك الهاتف). ──
          if (clinicFilter == null) ...[
            _PanelHeader(count: rows.length),
            const Divider(height: 1),
          ],
          // ── حقل البحث الفوري + قمع الأدوات ──────────────────────────────
          _SearchField(
            controller: searchCtl,
            focusNode: searchFocus,
            phoneMode: phoneMode,
            sortBy: sortBy,
            debtOnly: debtOnly,
            showArchived: showArchived,
            onChanged: onSearch,
            onPhoneMode: onPhoneMode,
            onSortBy: onSortBy,
            onDebtOnly: onDebtOnly,
            onShowArchived: onShowArchived,
          ),
          // ── م155/ب: عيادة مفتوحة — رأس باسم الدكتور وعدّاد مرضاه
          // (كفتح العيادة في الهاتف)، مع زر عودة لكل العيادات؛ وتُخفى
          // بوابة العيادات والتحاليل كلياً فتملأ الأسماء اللوح. ──
          if (clinicFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Material(
                color: BrandColors.brand600.withValues(alpha: .06),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: BrandColors.brand600.withValues(alpha: .45),
                      width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  child: Row(children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(27, 94, 71, .1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.home_work_outlined,
                          size: 14, color: BrandColors.brand),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(clinicFilter!,
                              key: const Key('dr-clinic-open-name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: BrandColors.brandText)),
                          const SizedBox(height: 1),
                          Text('${rows.length} مريض',
                              style: TextStyle(
                                  fontSize: 10,
                                  height: 1.1,
                                  color: BrandColors.ink
                                      .withValues(alpha: .65))),
                        ],
                      ),
                    ),
                    // زر العودة — يعيد الفلتر إلى «كل العيادات».
                    TextButton.icon(
                      key: const Key('dr-clinic-open-back'),
                      onPressed: () => onClinicChanged(null),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: BrandColors.brand600,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                      icon: const Icon(Icons.grid_view_rounded, size: 13),
                      label: const Text('كل العيادات',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
              ),
            ),
          // ── م155: مدخل التحاليل الثلاثية — ثابت أولاً (توأم بوابة
          // الهاتف)، يفتح السجل جدولاً في اللوح التفصيلي — يظهر في
          // البوابة فقط (لا عيادة مفتوحة). ──
          if (clinicFilter == null && showAnalysesEntry)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Material(
                color: analysesSelected
                    ? BrandColors.green.withValues(alpha: .08)
                    : BrandColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: BrandColors.green
                          .withValues(alpha: analysesSelected ? .55 : .35),
                      width: analysesSelected ? 1.2 : .8),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const Key('dr-anal-registry-entry'),
                  onTap: onOpenAnalyses,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    child: Row(children: [
                      Icon(Icons.biotech_rounded,
                          size: 17, color: BrandColors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('إيراد التحاليل الثلاثية',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: BrandColors.brandText)),
                      ),
                      Text('السجل الكامل',
                          style: TextStyle(
                              fontSize: 10.5, color: BrandColors.mut2)),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_left_rounded,
                          size: 17, color: BrandColors.mut),
                    ]),
                  ),
                ),
              ),
            ),
          // ── شريط العيادات القابل للطي (رقائق أفقية مطويّة / بطاقات
          // موسّعة) — في البوابة فقط؛ يختفي كلياً حين عيادةٌ مفتوحة. ──
          if (clinicFilter == null && clinicCards.isNotEmpty)
            _ClinicStrip(
              cards: clinicCards,
              currency: currency,
              selected: clinicFilter,
              expanded: clinicStripExpanded,
              onChanged: onClinicChanged,
              onToggleExpand: onToggleClinicStrip,
            ),
          const Divider(height: 1),
          // ── شريط التحديد الجماعي (م75 — في وضع التحديد فقط) ─────────────
          if (selectMode)
            _SelectionBar(
              rows: rows,
              selectedKeys: selectedKeys,
              pkeyOf: pkeyOf,
              onExit: onExitSelect,
              onArchive: onArchiveSelected,
              onUnarchive: onUnarchiveSelected,
            ),
          // ── قائمة المرضى ────────────────────────────────────────────────
          Expanded(
            child: rows.isEmpty
                ? _EmptyList(hasQuery: searchCtl.text.isNotEmpty)
                : ListView.builder(
                    // أداء مضمون: الارتفاع ثابت لكل بند.
                    itemExtent: _kItemHeight,
                    itemCount: rows.length,
                    itemBuilder: (ctx, i) {
                      final p = rows[i];
                      final agg = p.agg;
                      final isSelected =
                          selectedAgg?.name == agg.name &&
                          selectedAgg?.clinic == agg.clinic &&
                          selectedAgg?.identity == agg.identity;
                      final isKeyboard = keyboardIndex == i;
                      final isChecked =
                          selectedKeys.contains(pkeyOf(p));
                      return ContextMenuRegion(
                        // في وضع التحديد نُعطّل قائمة السياق (الأفعال جماعية).
                        enabled: !selectMode,
                        itemsBuilder: () => itemMenuBuilder(p),
                        child: _PatientTile(
                          row: p,
                          currency: currency,
                          isSelected: isSelected,
                          isKeyboardFocused: isKeyboard,
                          selectMode: selectMode,
                          isChecked: isChecked,
                          onTap: () => selectMode
                              ? onToggleSelect(p)
                              : onSelect(p),
                          onLongPress:
                              selectMode ? null : () => onEnterSelect(p),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── رأس القسم ────────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          Icon(Icons.folder_shared_rounded,
              size: 18, color: BrandColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'المرضى',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: BrandColors.brandText,
              ),
            ),
          ),
          // عداد نتائج: يميز بين «كل المرضى» والنتائج المفلترة.
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: BrandColors.brand.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: BrandColors.brand600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── حقل البحث الفوري + قمع الأدوات ────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.phoneMode,
    required this.sortBy,
    required this.debtOnly,
    required this.showArchived,
    required this.onChanged,
    required this.onPhoneMode,
    required this.onSortBy,
    required this.onDebtOnly,
    required this.onShowArchived,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool phoneMode;
  final String sortBy;
  final bool debtOnly;
  final bool showArchived;
  final VoidCallback onChanged;
  final ValueChanged<bool> onPhoneMode;
  final ValueChanged<String> onSortBy;
  final ValueChanged<bool> onDebtOnly;
  final ValueChanged<bool> onShowArchived;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: (_) => onChanged(),
            keyboardType:
                phoneMode ? TextInputType.phone : TextInputType.text,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText: phoneMode
                  ? 'بحث برقم الهاتف…'
                  : 'بحث بالاسم أو الهاتف…',
              hintStyle:
                  TextStyle(fontSize: 12.5, color: BrandColors.faint),
              prefixIcon: Icon(Icons.search_rounded,
                  size: 18, color: BrandColors.mut),
              suffixIcon: controller.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded,
                          size: 16, color: BrandColors.mut),
                      onPressed: () {
                        controller.clear();
                        onChanged();
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 9),
              filled: true,
              fillColor: BrandColors.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: BrandColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: BrandColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: BrandColors.brand, width: 1.5),
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        // ── قمع الأدوات الواحد (توأم قمع الهاتف cp-tools): نمط البحث +
        // الفرز الخمسة + فلتر الدين + إظهار المؤرشفين. يتلوّن بالأحمر عند
        // تفعيل فلتر الدين كالهاتف. ──
        _ToolsMenu(
          phoneMode: phoneMode,
          sortBy: sortBy,
          debtOnly: debtOnly,
          showArchived: showArchived,
          onPhoneMode: onPhoneMode,
          onSortBy: onSortBy,
          onDebtOnly: onDebtOnly,
          onShowArchived: onShowArchived,
        ),
      ]),
    );
  }
}

// ── قمع أدوات البحث والفرز والفلاتر ───────────────────────────────────────────

class _ToolsMenu extends StatelessWidget {
  const _ToolsMenu({
    required this.phoneMode,
    required this.sortBy,
    required this.debtOnly,
    required this.showArchived,
    required this.onPhoneMode,
    required this.onSortBy,
    required this.onDebtOnly,
    required this.onShowArchived,
  });

  final bool phoneMode;
  final String sortBy;
  final bool debtOnly;
  final bool showArchived;
  final ValueChanged<bool> onPhoneMode;
  final ValueChanged<String> onSortBy;
  final ValueChanged<bool> onDebtOnly;
  final ValueChanged<bool> onShowArchived;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: debtOnly
          ? BrandColors.red.withValues(alpha: .12)
          : BrandColors.gold.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: debtOnly
                ? BrandColors.red.withValues(alpha: .4)
                : BrandColors.gold.withValues(alpha: .3)),
      ),
      child: PopupMenuButton<String>(
        key: const Key('dr-tools'),
        tooltip: 'أدوات البحث والفرز',
        onSelected: (v) {
          if (v == 'mode:name') onPhoneMode(false);
          if (v == 'mode:phone') onPhoneMode(true);
          if (v.startsWith('sort:')) onSortBy(v.substring(5));
          if (v == 'debt') onDebtOnly(!debtOnly);
          if (v == 'archived') onShowArchived(!showArchived);
        },
        itemBuilder: (context) => [
          CheckedPopupMenuItem(
            key: const Key('dr-mode-name'),
            value: 'mode:name',
            checked: !phoneMode,
            child: const Text('بحث بالاسم',
                style: TextStyle(fontSize: 12.5)),
          ),
          CheckedPopupMenuItem(
            key: const Key('dr-mode-phone'),
            value: 'mode:phone',
            checked: phoneMode,
            child: const Text('بحث برقم الهاتف',
                style: TextStyle(fontSize: 12.5)),
          ),
          const PopupMenuDivider(height: 6),
          // الأنماط الخمسة من clinicSortLabels حرفياً.
          for (final e in clinicSortLabels.entries)
            CheckedPopupMenuItem(
              key: Key('dr-sort-${e.key}'),
              value: 'sort:${e.key}',
              checked: sortBy == e.key,
              child:
                  Text(e.value, style: const TextStyle(fontSize: 12.5)),
            ),
          const PopupMenuDivider(height: 6),
          CheckedPopupMenuItem(
            key: const Key('dr-filter-debt'),
            value: 'debt',
            checked: debtOnly,
            child: const Text('عليه دين/متبقٍ فقط',
                style: TextStyle(fontSize: 12.5)),
          ),
          CheckedPopupMenuItem(
            key: const Key('dr-filter-archived'),
            value: 'archived',
            checked: showArchived,
            child: const Text('إظهار المؤرشفين',
                style: TextStyle(fontSize: 12.5)),
          ),
        ],
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
              debtOnly
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_outlined,
              size: 17,
              color:
                  debtOnly ? BrandColors.red : BrandColors.goldDark),
        ),
      ),
    );
  }
}

// ── شريط العيادات القابل للطي ────────────────────────────────────────────────
//
//  المشكلة القديمة: بطاقات عمودية بارتفاع 132px تبتلع ثلث اللوح. الحل: وضعان
//  يبدّلهما زرٌّ صغير مع حفظ الحالة محلياً:
//    • مطويّ (افتراضي، ~40px): شريط رقائق أفقي [كل العيادات][اسم · ن مريض]…
//      النقر يبدّل الفلتر بنفس منطق onChanged حرفياً؛ الرقاقة المختارة brand600.
//    • موسّع (~120px): بطاقات العيادات الحالية بالدخل (خلف clinics.sums)
//      والزيارات — سلوكها في التصفية كما هو.
//  البيانات في الوضعين من clinicCards() نفسها.

class _ClinicStrip extends StatelessWidget {
  const _ClinicStrip({
    required this.cards,
    required this.currency,
    required this.selected,
    required this.expanded,
    required this.onChanged,
    required this.onToggleExpand,
  });

  final List<ClinicCard> cards;
  final String currency;
  final String? selected;
  final bool expanded;
  final ValueChanged<String?> onChanged;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── الجسم: رقائق مطويّة أو بطاقات موسّعة (مبدّل سلس) ──
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? _ExpandedCards(
                  cards: cards,
                  currency: currency,
                  selected: selected,
                  onChanged: onChanged,
                )
              : _CollapsedChips(
                  cards: cards,
                  selected: selected,
                  onChanged: onChanged,
                ),
        ),
        // ── زرّ التوسيع/الطي الصغير ──
        InkWell(
          key: const Key('dr-clinic-strip-toggle'),
          onTap: onToggleExpand,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 15,
                  color: BrandColors.mut2,
                ),
                const SizedBox(width: 4),
                Text(
                  expanded ? 'طيّ العيادات' : 'تفاصيل العيادات',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: BrandColors.mut2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// الوضع المطويّ — شريط رقائق أفقي مضغوط (~40px): رقاقة «كل العيادات» ثم
/// رقاقة لكل عيادة باسمها وعدد مرضاها. النقر يبدّل الفلتر بنفس منطق onChanged.
class _CollapsedChips extends StatelessWidget {
  const _CollapsedChips({
    required this.cards,
    required this.selected,
    required this.onChanged,
  });

  final List<ClinicCard> cards;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // م156 — Wrap ملتف بدل السكرول الأفقي (كان متوقفاً بلا وسيلة وصول
    // لبقية العيادات بالفأرة): كل الرقائق ظاهرة دفعةً واحدة، وتلتف
    // لأسطرٍ إضافية عند الكثرة بلا أي تمرير.
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Wrap(
        spacing: 0,
        runSpacing: 4,
        children: [
          // رقاقة «كل العيادات» — تعيد الفلتر إلى null.
          _ClinicChip(
            keyId: 'dr-clinic-chip-all',
            icon: Icons.grid_view_rounded,
            label: 'كل العيادات',
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final c in cards)
            _ClinicChip(
              keyId: 'dr-clinic-chip-${c.name}',
              label: c.name,
              // العدّاد المدمج «· ن» = عدد مرضى العيادة (بلا مبالغ فمرئي للكل).
              count: c.patientCount,
              selected: selected == c.name,
              onTap: () =>
                  onChanged(selected == c.name ? null : c.name),
            ),
        ],
      ),
    );
  }
}

/// رقاقة عيادة واحدة في الوضع المطويّ — المختارة brand600 كما هو مطلوب.
class _ClinicChip extends StatelessWidget {
  const _ClinicChip({
    required this.keyId,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  final String keyId;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? Colors.white : BrandColors.brandText;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: Material(
        color: selected ? BrandColors.brand600 : BrandColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: selected ? BrandColors.brand600 : BrandColors.line,
              width: selected ? 1.2 : .8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key(keyId),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: fg)),
              if (count != null) ...[
                const SizedBox(width: 5),
                Text('· $count',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white.withValues(alpha: .85)
                            : BrandColors.mut)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// الوضع الموسّع — بطاقات العيادات الحالية (~120px) بالدخل خلف clinics.sums
/// والزيارات. النقر على البطاقة يبدّل الفلتر تماماً كالوضع القديم.
class _ExpandedCards extends StatelessWidget {
  const _ExpandedCards({
    required this.cards,
    required this.currency,
    required this.selected,
    required this.onChanged,
  });

  final List<ClinicCard> cards;
  final String currency;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // م155 — بطاقات صفّية عمودية بهوية الخزينة (م154) بدل الشريط الأفقي:
    // صفٌّ لكل عيادة بمعلوماتها، وسقفُ ارتفاعٍ يمرّر القائمة عند الكثرة.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 236),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        children: [
          // بطاقة «كل العيادات» تبقى خياراً (تعيد الفلتر إلى null).
          _AllClinicsCard(
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final c in cards) ...[
            const SizedBox(height: 6),
            _ClinicCard(
              card: c,
              currency: currency,
              selected: selected == c.name,
              onTap: () =>
                  onChanged(selected == c.name ? null : c.name),
            ),
          ],
        ],
      ),
    );
  }
}

/// بطاقة «كل العيادات» — خيار العودة لعرض كل المرضى.
class _AllClinicsCard extends StatelessWidget {
  const _AllClinicsCard({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // م155 — صفٌّ بهوية الخزينة بدل البطاقة العمودية الصغيرة.
    final Color border =
        selected ? BrandColors.brand600 : BrandColors.line;
    return Material(
      color: selected
          ? BrandColors.brand600.withValues(alpha: .08)
          : BrandColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border, width: selected ? 1.2 : .8),
      ),
      child: InkWell(
        key: const Key('dr-clinic-card-all'),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(Icons.grid_view_rounded,
                size: 16,
                color: selected
                    ? BrandColors.brand600
                    : BrandColors.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text('كل العيادات',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brandText)),
            ),
            Text('عرض كل المرضى',
                style: TextStyle(
                    fontSize: 10.5, color: BrandColors.mut2)),
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle_rounded,
                  size: 15, color: BrandColors.brand600),
            ],
          ]),
        ),
      ),
    );
  }
}

/// بطاقة عيادة مكتبية مضغوطة — توأم إحصاءات بطاقة الهاتف: عدد المرضى،
/// «X زيارة هذا الشهر»، والدخل خلف صلاحية clinics.sums (كالهاتف تماماً).
class _ClinicCard extends StatelessWidget {
  const _ClinicCard({
    required this.card,
    required this.currency,
    required this.selected,
    required this.onTap,
  });

  final ClinicCard card;
  final String currency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = formatNumber;
    // م155 — صفٌّ بهوية الخزينة (توأم بوابة الهاتف الجديدة): قرص أيقونة
    // + الاسم وسطر الإحصاء يميناً، والدخل بصلاحيته يساراً؛ يبرز بلون
    // العلامة عند الاختيار كفلترٍ قائم.
    final Color border =
        selected ? BrandColors.brand600 : BrandColors.line;
    return Material(
      color: selected
          ? BrandColors.brand600.withValues(alpha: .06)
          : BrandColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border, width: selected ? 1.2 : .8),
      ),
      child: InkWell(
        key: Key('dr-clinic-card-${card.name}'),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(children: [
            // ① قرص الأيقونة.
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(27, 94, 71, .1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.home_work_outlined,
                  size: 14, color: BrandColors.brand),
            ),
            const SizedBox(width: 8),
            // ② الاسم + سطر الإحصاء الخفيف.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.brandText)),
                  const SizedBox(height: 1),
                  Text(
                      '${card.patientCount} مريض · '
                      '${card.visitCount} زيارة هذا الشهر',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10,
                          height: 1.1,
                          color:
                              BrandColors.ink.withValues(alpha: .65))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ③ الدخل الشهري — خلف صلاحيته المستقلة (م125 كما كان).
            if (staffAllowed('clinics.sums'))
              Text('${n(card.income)} $currency',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.goldDark,
                      fontFeatures: [FontFeature.tabularFigures()])),
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle_rounded,
                  size: 15, color: BrandColors.brand600),
            ],
          ]),
        ),
      ),
    );
  }
}

// ── شريط التحديد الجماعي (م75) ────────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.rows,
    required this.selectedKeys,
    required this.pkeyOf,
    required this.onExit,
    required this.onArchive,
    required this.onUnarchive,
  });

  final List<ClinicPatientRow> rows;
  final Set<String> selectedKeys;
  final String Function(ClinicPatientRow) pkeyOf;
  final VoidCallback onExit;
  final VoidCallback onArchive;
  final VoidCallback onUnarchive;

  @override
  Widget build(BuildContext context) {
    final sel =
        [for (final p in rows) if (selectedKeys.contains(pkeyOf(p))) p];
    // يعرض «إلغاء الأرشفة» حين يكون كل المحدَّدين مؤرشفين، و«أرشفة» عداه.
    final allArchived = sel.isNotEmpty && sel.every((p) => p.archived);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: BrandColors.brand600.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        IconButton(
          key: const Key('dr-sel-exit'),
          visualDensity: VisualDensity.compact,
          onPressed: onExit,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
        Expanded(
          child: Text('محدَّد: ${sel.length}',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
        if (allArchived)
          FilledButton.icon(
            key: const Key('dr-sel-unarchive'),
            style: FilledButton.styleFrom(
                backgroundColor: BrandColors.brand600,
                visualDensity: VisualDensity.compact),
            onPressed: sel.isEmpty ? null : onUnarchive,
            icon: const Icon(Icons.unarchive_rounded, size: 15),
            label: const Text('إلغاء الأرشفة',
                style: TextStyle(fontSize: 12)),
          )
        else
          FilledButton.icon(
            key: const Key('dr-sel-archive'),
            style: FilledButton.styleFrom(
                backgroundColor: BrandColors.red,
                visualDensity: VisualDensity.compact),
            onPressed: sel.isEmpty ? null : onArchive,
            icon: const Icon(Icons.archive_rounded, size: 15),
            label:
                const Text('أرشفة', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }
}

// ── حالة القائمة الفارغة ──────────────────────────────────────────────────────

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.hasQuery});
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasQuery ? Icons.search_off_rounded : Icons.people_outline_rounded,
            size: 40,
            color: BrandColors.faint,
          ),
          const SizedBox(height: 10),
          Text(
            hasQuery ? 'لا نتائج مطابقة' : 'لا مرضى مسجلين',
            style: TextStyle(
                fontSize: 13, color: BrandColors.mut),
          ),
          if (hasQuery) ...[
            const SizedBox(height: 4),
            Text(
              'جرّب تعديل البحث أو الفلتر',
              style: TextStyle(
                  fontSize: 11.5, color: BrandColors.faint),
            ),
          ],
        ],
      ),
    );
  }
}

// ── بند مريض في القائمة ──────────────────────────────────────────────────────

class _PatientTile extends StatefulWidget {
  const _PatientTile({
    required this.row,
    required this.currency,
    required this.isSelected,
    required this.isKeyboardFocused,
    required this.selectMode,
    required this.isChecked,
    required this.onTap,
    required this.onLongPress,
  });

  final ClinicPatientRow row;
  final String currency;
  final bool isSelected;
  final bool isKeyboardFocused;
  final bool selectMode;
  final bool isChecked;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_PatientTile> createState() => _PatientTileState();
}

class _PatientTileState extends State<_PatientTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // لون الخلفية: محدَّد جماعياً > مختار > hover > عادي.
    final Color bg;
    if (widget.isChecked) {
      bg = BrandColors.brand600.withValues(alpha: .1);
    } else if (widget.isSelected) {
      bg = BrandColors.brand.withValues(alpha: .12);
    } else if (widget.isKeyboardFocused) {
      bg = BrandColors.gold.withValues(alpha: .08);
    } else if (_hovered) {
      // م155 — تظليل المرور: صبغة علامة فاتحة شفافة بدل surface2 الداكنة
      // (كانت تظهر شريطاً غامقاً ثقيلاً — ملاحظة المالك بالصورة).
      bg = BrandColors.brand.withValues(alpha: .05);
    } else {
      bg = Colors.transparent;
    }

    // حد الاختيار الجانبي: أخضر/ذهبي واضح كما مطلوب.
    final bool showBorder = widget.isSelected || widget.isKeyboardFocused;
    final Color borderColor = widget.isSelected
        ? BrandColors.green
        : BrandColors.goldDark;

    final p = widget.row;
    final agg = p.agg;
    // نص ثانوي: العيادة + هاتف (سطر مختصر كالهاتف).
    final parts = <String>[
      if (agg.clinic.isNotEmpty) agg.clinic,
      if (agg.phone.isNotEmpty) agg.phone,
    ];
    final subtitle = parts.isEmpty ? '' : parts.join(' · ');
    final visits = agg.visitCount;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        // م155 — Container فوري بدل AnimatedContainer (كان تأخير 100مل
        // يجعل التظليل يبدو متثاقلاً عند المرور السريع فوق الصفوف).
        child: Container(
          height: _kItemHeight,
          decoration: BoxDecoration(
            color: bg,
            // حد جانبي بديره = بداية RTL (اليمين فيزيائياً).
            border: showBorder
                ? BorderDirectional(
                    start: BorderSide(
                      color: borderColor,
                      width: 3,
                    ),
                  )
                : null,
          ),
          // صفٌّ نحيل: حشوٌ عموديّ ضئيل (3) يفسح لأفاتار 28 وسطرين متراصّين
          // دون فراغ ميت؛ يُبقى حدُّ الاختيار الجانبي بديره حرفياً.
          padding: EdgeInsetsDirectional.only(
            start: showBorder ? 9 : 12,
            end: 8,
            top: 3,
            bottom: 3,
          ),
          child: Row(
            children: [
              // في وضع التحديد: دائرة اختيار بدل الأفاتار (مصغّرة 22→20).
              if (widget.selectMode)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Icon(
                    widget.isChecked
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: widget.isChecked
                        ? BrandColors.brand600
                        : BrandColors.mut2,
                  ),
                )
              else ...[
                // أيقونة المريض بخلفية ملونة (مصغّرة 36→28).
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isSelected
                        ? BrandColors.green.withValues(alpha: .15)
                        : BrandColors.brand.withValues(alpha: .08),
                  ),
                  child: Center(
                    child: Text(
                      agg.name.isNotEmpty ? agg.name[0] : '؟',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: widget.isSelected
                            ? BrandColors.green
                            : BrandColors.brand,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
              ],
              // النص الرئيسي (اسم + شارات مدمجة) والثانوي (عيادة·هاتف نحيف).
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            agg.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                              color: widget.isSelected
                                  ? BrandColors.green
                                  : BrandColors.brandText,
                            ),
                          ),
                        ),
                        // ── الشارات المدمجة بجانب الاسم: دين/تركيبات/تقرير
                        // (مصغّرة 20→16) + عدد الزيارات + «مؤرشف». المكتب
                        // يرحّب بها بينما أخفاها الهاتف بصرياً بقرار المالك.
                        if (p.hasDebt)
                          const _StatusBadge(
                            keyId: 'dr-badge-debt',
                            icon: Icons.account_balance_wallet_rounded,
                            color: BrandColors.red,
                            tooltip: 'عليه دين',
                          ),
                        if (p.hasPros)
                          const _StatusBadge(
                            keyId: 'dr-badge-pros',
                            icon: Icons.medical_services_rounded,
                            color: BrandColors.goldDark,
                            tooltip: 'تركيبات',
                          ),
                        if (p.hasReport)
                          const _StatusBadge(
                            keyId: 'dr-badge-report',
                            icon: Icons.description_rounded,
                            color: BrandColors.brand,
                            tooltip: 'تقرير أسنان',
                          ),
                        // عدد الزيارات — شارة رقمية مضغوطة.
                        if (visits > 0)
                          Padding(
                            padding:
                                const EdgeInsetsDirectional.only(start: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: widget.isSelected
                                    ? BrandColors.green
                                        .withValues(alpha: .12)
                                    : BrandColors.gold
                                        .withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                '$visits',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: widget.isSelected
                                      ? BrandColors.green
                                      : BrandColors.goldDark,
                                ),
                              ),
                            ),
                          ),
                        // م75 — شارة «مؤرشف» الرمادية (توأم الهاتف :824-839).
                        if (p.archived)
                          Padding(
                            padding:
                                const EdgeInsetsDirectional.only(start: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: BrandColors.mut2
                                    .withValues(alpha: .15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('مؤرشف',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: BrandColors.mut2,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ],
                    ),
                    // سطر ثانوي نحيف (عيادة·هاتف) height:1.1 مع Tooltip كي
                    // يظهر كاملاً عند اقتطاعه في اللوح الضيق.
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Tooltip(
                          message: subtitle,
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.1,
                              color: BrandColors.mut,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── شارة حالة صغيرة (أيقونة بتلميح) ────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.keyId,
    required this.icon,
    required this.color,
    required this.tooltip,
  });

  final String keyId;
  final IconData icon;
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key(keyId),
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icon, size: 11, color: color),
        ),
      ),
    );
  }
}
