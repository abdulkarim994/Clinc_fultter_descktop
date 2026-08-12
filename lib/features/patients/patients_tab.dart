/// تبويب السجلات — نقل بنيوي كامل لثلاثية الأصل (م10-أ/ب):
///   • **بوابة العيادات** (ClinicsLanding): بطاقات العيادات بإحصاءات
///     الشهر المختار (مرضى فريدون، زيارات، الدخل الحرفي، شارة الديون
///     المعلقة) + البحث الشامل عبر العيادات (اسم ضبابي مرتب أو وضع هاتف)
///     ونتائجه تفتح ملف المريض مباشرة.
///   • **مرضى العيادة** (ClinicPatients): تجميع patientMap الحرفي، بحث
///     وفرز الأصل الخمسة، صف المريض بشاراته (دين/تركيبات/تقرير)، زر
///     «المزيد» بلوحة الإجراءات (زيارة جديدة تنتقل للرئيسية مربوطة،
///     السجل الكامل، تعديل البيانات باكتساح الجداول الأربعة، خطة
///     العلاج، طباعة PDF).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../print/treatment_tables.dart' show formatNumber;
import 'archive_store.dart' show PatientArchiveStore;
import 'clinic_scope.dart' show clinicScopedKey;
import 'patient_profile_screen.dart' hide JMap;
import 'patients_logic.dart';
import '../finance/analyses_registry.dart'
    show AnalysesRegistryEntry, AnalysesRegistryScreen;
// م168 — مدخل السجل يظهر بالتفعيل أو بوجود تاريخٍ ظاهر (قبل الإيقاف).
import '../settings/analyses3.dart' show triHasVisibleHistory;
import 'quick_visit_sheet.dart' show showQuickVisitSheet;
import '../staff/staff_gate.dart' show gateStaff, staffAllowed;

/// نبضة إعادة قراءة بعد كتابات المرضى/السجلات.
final patientsRevProvider = StateProvider<int>((ref) => 0);

/// نص البحث الشامل في البوابة — يبذره goPatient من المواعيد وغيرها.
final patientSearchProvider = StateProvider<String>((ref) => '');

/// العيادة المفتوحة داخل التبويب (null = البوابة).
final openClinicProvider = StateProvider<String?>((ref) => null);

/// مسودة «زيارة جديدة» من لوحة إجراءات المريض — تستهلكها الرئيسية
/// (توأم query {patient, clinic} في الأصل).
final addVisitDraftProvider = StateProvider<JMap?>((ref) => null);

/// خريطة المرضى المجمعة — المصدر الواحد للبوابة والقوائم.
final patientMapProvider = Provider<Map<String, PatientAgg>>((ref) {
  ref.watch(patientsRevProvider);
  // كل كتابة بحث تعيد القراءة من القاعدة (سلوك القائمة القديم — يلتقط
  // كتابات خارجية حدثت بلا نبضة).
  ref.watch(patientSearchProvider);
  final repos = ref.watch(reposProvider);
  return buildPatientMap(
    repos.records.getAll(),
    repos.prosthetics.getAll(),
    repos.debts.getAll(),
  );
});

class PatientsTab extends ConsumerWidget {
  const PatientsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openClinicProvider);
    return open == null
        ? const _ClinicsLanding()
        : ClinicPatientsScreen(clinicName: open);
  }
}

// ═══════════════ البوابة: بطاقات العيادات + البحث الشامل ═══════════════

class _ClinicsLanding extends ConsumerStatefulWidget {
  const _ClinicsLanding();

  @override
  ConsumerState<_ClinicsLanding> createState() =>
      _ClinicsLandingState();
}

class _ClinicsLandingState extends ConsumerState<_ClinicsLanding> {
  bool phoneMode = false;
  late final TextEditingController searchCtl;

  @override
  void initState() {
    super.initState();
    searchCtl =
        TextEditingController(text: ref.read(patientSearchProvider));
  }

  @override
  void dispose() {
    searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(patientsRevProvider);
    final repos = ref.watch(reposProvider);
    final clinics = ref.watch(clinicsProvider);
    final month = ref.watch(selectedMonthProvider);
    final cur = ref.watch(currencyProvider);
    final n = formatNumber;
    final query = ref.watch(patientSearchProvider);
    // مزامنة الحقل عند بذر البحث خارجياً (goPatient من المواعيد).
    if (searchCtl.text != query) {
      searchCtl.text = query;
    }

    final cards = clinicCards(
      clinics: clinics,
      month: month,
      records: repos.records.getAll(),
      prosthetics: repos.prosthetics.getAll(),
      debts: repos.debts.getAll(),
    );
    final results = landingSearchResults(
      query,
      patientMap: ref.watch(patientMapProvider),
      phoneMode: phoneMode,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
      children: [
        // ── v56 — البحث الشامل **فوق** الشبكة بهوية بحث الديون
        // الموحدة (طلب المالك): حقل 36 بخط 12 وحد رمادي رفيع + مربع
        // نمط البحث الذهبي 38×36 — بلا بطاقة زجاجية حاضنة. ──
        Row(key: const Key('landing-search-card'), children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                key: const Key('patient-search'),
                controller: searchCtl,
                keyboardType: phoneMode
                    ? TextInputType.phone
                    : TextInputType.text,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: phoneMode
                      ? 'بحث برقم الهاتف...'
                      : 'بحث في كل العيادات...',
                  hintStyle:
                      TextStyle(fontSize: 12, color: BrandColors.mut2),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 16, color: BrandColors.mut2),
                  filled: true,
                  fillColor: BrandColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: BrandColors.line, width: .8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: BrandColors.line, width: .8),
                  ),
                ),
                onChanged: (v) =>
                    ref.read(patientSearchProvider.notifier).state = v,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // زر نمط البحث — مربع ذهبي 38×36 (عائلة قمع الديون).
          Material(
            color: BrandColors.gold.withValues(alpha: .08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                  color: BrandColors.gold.withValues(alpha: .3)),
            ),
            child: PopupMenuButton<bool>(
              key: const Key('search-phone-mode'),
              tooltip: 'نمط البحث',
              onSelected: (v) => setState(() => phoneMode = v),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: false,
                  child: Row(children: [
                    Icon(Icons.search_rounded,
                        size: 15,
                        color: !phoneMode
                            ? BrandColors.brand600
                            : BrandColors.mut2),
                    const SizedBox(width: 8),
                    Text('الاسم',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: !phoneMode
                                ? FontWeight.w800
                                : FontWeight.w500)),
                  ]),
                ),
                PopupMenuItem(
                  value: true,
                  child: Row(children: [
                    Icon(Icons.dialpad_rounded,
                        size: 15,
                        color: phoneMode
                            ? BrandColors.brand600
                            : BrandColors.mut2),
                    const SizedBox(width: 8),
                    Text('رقم الهاتف',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: phoneMode
                                ? FontWeight.w800
                                : FontWeight.w500)),
                  ]),
                ),
              ],
              child: const SizedBox(
                width: 38,
                height: 36,
                child: Icon(Icons.filter_alt_outlined,
                    size: 16, color: BrandColors.goldDark),
              ),
            ),
          ),
        ]),
        // ── نتائج البحث الشامل — مباشرة تحت الشريط (v56). ──
        if (query.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: Text('لا توجد نتائج',
                    style: TextStyle(
                        fontSize: 12.5, color: BrandColors.mut2)),
              ),
            )
          else
            for (final r in results)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  // م35 — نفس الاسم بعيادتين = بطاقتان: المفتاح يضم
                  // العيادة عند التكرار (والاسم وحده وإلا — ثبات المفاتيح).
                  key: Key(results
                              .where((x) => x.agg.name == r.agg.name)
                              .length >
                          1
                      // م90 — سميّان في نفس العيادة: الهوية تدخل المفتاح.
                      ? 'patient-card-${r.agg.name}|${r.clinic}'
                          '${r.agg.identity.isEmpty ? '' : '|${r.agg.identity}'}'
                      : 'patient-card-${r.agg.name}'),
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        BrandColors.brand600.withValues(alpha: .12),
                    child: const Icon(Icons.person_rounded,
                        size: 17, color: BrandColors.brand600),
                  ),
                  title: Row(children: [
                    Flexible(
                      child: Text(r.agg.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (r.clinic.isNotEmpty)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(r.clinic,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: BrandColors.brandText)),
                        ),
                      ),
                  ]),
                  subtitle: Text(
                      // م90 — سطر الهاتف الصغير يفرّق السميّين بصرياً.
                      '${r.agg.identity.isEmpty ? '' : '${r.agg.phone.isEmpty ? 'بلا رقم' : r.agg.phone} • '}'
                      '${r.agg.visitCount} زيارة • آخر: ${r.agg.lastDate.isEmpty ? '—' : r.agg.lastDate}',
                      style: TextStyle(
                          fontSize: 11.5, color: BrandColors.mut2)),
                  trailing: Text('${n(r.agg.total)} $cur',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.goldDark)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => PatientProfileScreen(
                            patientName: r.agg.name,
                            clinic: r.clinic,
                            // م90 — فتحُ هوية البطاقة نفسها لا السميّ.
                            identity: r.agg.identity)),
                  ),
                ),
              ),
        ],
        const SizedBox(height: 12),
        // م154 — مدخل «إيراد التحاليل الثلاثية»: السجل الدائم انتقل من
        // الخزينة إلى السجلات (قرار المالك) — يظهر حين الميزة مفعّلة.
        // م168 — أو حين يوجد تاريخُ تحاليلَ سابقٌ لتاريخ الإيقاف (عرضٌ
        // تاريخي فقط — البيانات القديمة تبقى وصولة ولا مدخل بلا تاريخ).
        if (triHasVisibleHistory(
          ref.watch(appConfigProvider),
          ref.watch(reposProvider).records.getAll().cast<Map<String, Object?>>(),
        )) ...[
          AnalysesRegistryEntry(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const AnalysesRegistryScreen()),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // ── شبكة بطاقات العيادات — تبقى ظاهرة حتى أثناء البحث. ──
        if (cards.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                  'لا توجد عيادات — أضِفها من الإعدادات ← العيادات والمعالجات',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5, color: BrandColors.mut2)),
            ),
          )
        else ...[
          // م155 — بطاقات صفّية صغيرة بهوية الخزينة الجديدة (م154):
          // صفٌّ أنيق لكل عيادة بدل الشبكة الكبيرة (قرار المالك).
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _clinicRow(cards[i], cur, n),
          ],
        ],

      ],
    );
  }

  /// م155 — بطاقة العيادة الصفّية: توأم TreasuryMasterRow بروحها —
  /// قرص أيقونة صغير + الاسم يميناً وسطرُ الإحصاء (مرضى · زيارات)
  /// خفيفاً تحته، والدخل الشهري يساراً خلف صلاحيته (clinics.sums م125)
  /// مع سهم الدخول. الضغط يفتح مرضى العيادة كما كان حرفياً.
  Widget _clinicRow(
      ClinicCard c, String cur, String Function(Object?) n) {
    return Material(
      color: BrandColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: BrandColors.line, width: .8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('clinic-card-${c.name}'),
        onTap: () =>
            ref.read(openClinicProvider.notifier).state = c.name,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            // ① قرص الأيقونة — مصغّر من 40 إلى 30 (هوية البطاقة الكبيرة).
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(27, 94, 71, .1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.home_work_outlined,
                  size: 16, color: BrandColors.brand),
            ),
            const SizedBox(width: 9),
            // ② الاسم + سطر الإحصاء الخفيف (مرضى · زيارات الشهر).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .3,
                          color: BrandColors.brandText)),
                  const SizedBox(height: 2),
                  Text(
                      '${c.patientCount} مريض · '
                      '${c.visitCount} زيارة هذا الشهر',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.1,
                          color:
                              BrandColors.ink.withValues(alpha: .65))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // ③ الدخل الشهري — خلف صلاحيته المستقلة (م125 كما كان).
            if (staffAllowed('clinics.sums'))
              Text('${n(c.income)} $cur',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: BrandColors.goldDark,
                      fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(width: 4),
            Icon(Icons.chevron_left_rounded,
                size: 17, color: BrandColors.mut),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════ مرضى العيادة ═══════════════

class ClinicPatientsScreen extends ConsumerStatefulWidget {
  const ClinicPatientsScreen({super.key, required this.clinicName});

  final String clinicName;

  @override
  ConsumerState<ClinicPatientsScreen> createState() =>
      _ClinicPatientsScreenState();
}

class _ClinicPatientsScreenState
    extends ConsumerState<ClinicPatientsScreen> {
  final searchCtl = TextEditingController();
  bool phoneMode = false;
  String sortBy = 'activity';
  bool debtOnly = false; // م64 — فلتر «عليه دين/متبقٍ»

  // م75 — أرشفة المرضى
  bool showArchived = false; // إظهار المؤرشفين في القائمة والبحث
  bool selectMode = false; // وضع التحديد المتعدد
  final Set<String> selected = {}; // مفاتيح (اسم|عيادة) المحدَّدين

  @override
  void dispose() {
    searchCtl.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  PatientArchiveStore get _archive =>
      PatientArchiveStore(ref.read(reposProvider).settings);

  String _pkey(ClinicPatientRow p) =>
      clinicScopedKey(p.agg.name, p.agg.clinic);

  void _exitSelect() => setState(() {
        selectMode = false;
        selected.clear();
      });

  void _toggleSelect(ClinicPatientRow p) => setState(() {
        final k = _pkey(p);
        if (!selected.remove(k)) selected.add(k);
        if (selected.isEmpty) selectMode = false;
      });

  void _enterSelect(ClinicPatientRow p) => setState(() {
        selectMode = true;
        selected
          ..clear()
          ..add(_pkey(p));
      });

  @override
  Widget build(BuildContext context) {
    ref.watch(patientsRevProvider);
    final repos = ref.watch(reposProvider);
    final cur = ref.watch(currencyProvider);
    final n = formatNumber;

    final rows = clinicPatients(
      widget.clinicName,
      patientMap: ref.watch(patientMapProvider),
      records: repos.records.getAll(),
      prosthetics: repos.prosthetics.getAll(),
      debts: repos.debts.getAll(),
      archivedKeys: _archive.archivedKeys(), // م75
    );
    final filtered = filterClinicPatients(
      rows,
      query: searchCtl.text,
      phoneMode: phoneMode,
      sortBy: sortBy,
      debtOnly: debtOnly,
      showArchived: showArchived, // م75
    );

    return Column(children: [
      // ── v59 — صف واحد مدمج على خلفية الصفحة (توأم صف الديون):
      // [رجوع | الاسم+العدد | الحقل الممتد | قمع أدوات واحد]. ──
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Row(children: [
            // زر رجوع مدوّر بصبغة العلامة.
            Material(
              color: BrandColors.brand600.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: const Key('clinic-back'),
                borderRadius: BorderRadius.circular(10),
                onTap: () =>
                    ref.read(openClinicProvider.notifier).state = null,
                child: SizedBox(
                  width: 38,
                  height: 36,
                  child: Icon(Icons.arrow_back_rounded,
                      size: 18, color: BrandColors.brandIcon),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // الاسم + العدد — عمود مضغوط يتقلص رشيقاً عند الضيق.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.clinicName,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.brandText)),
                    Text('${filtered.length} مريض',
                        style: TextStyle(
                            fontSize: 10.5, color: BrandColors.mut2)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // v56 — الحقل بهوية بحث الديون الموحدة (36/خط 12/حد line).
            Expanded(
              child: SizedBox(
                height: 36,
                child: TextField(
                  key: const Key('cp-search'),
                  controller: searchCtl,
                  keyboardType: phoneMode
                      ? TextInputType.phone
                      : TextInputType.text,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: phoneMode
                        ? 'بحث برقم الهاتف...'
                        : 'بحث عن مريض...',
                    hintStyle: TextStyle(
                        fontSize: 12, color: BrandColors.mut2),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 16, color: BrandColors.mut2),
                    filled: true,
                    fillColor: BrandColors.surface,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: BrandColors.line, width: .8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: BrandColors.line, width: .8),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // ── v59 — قمع الأدوات الواحد (توأم قمع الديون): يجمع نمط
            // البحث والفرز وفلتر الدين في قائمة مؤشَّرة واحدة، ويتلون
            // بالأحمر حين يكون فلتر الدين فعالاً. ──
            Material(
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
                key: const Key('cp-tools'),
                tooltip: 'أدوات البحث والفرز',
                onSelected: (v) => setState(() {
                  if (v == 'mode:name') phoneMode = false;
                  if (v == 'mode:phone') phoneMode = true;
                  if (v.startsWith('sort:')) sortBy = v.substring(5);
                  if (v == 'debt') debtOnly = !debtOnly;
                  if (v == 'archived') showArchived = !showArchived; // م75
                }),
                itemBuilder: (context) => [
                  CheckedPopupMenuItem(
                    key: const Key('cp-mode-name'),
                    value: 'mode:name',
                    checked: !phoneMode,
                    child: const Text('بحث بالاسم',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  CheckedPopupMenuItem(
                    key: const Key('cp-mode-phone'),
                    value: 'mode:phone',
                    checked: phoneMode,
                    child: const Text('بحث برقم الهاتف',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  const PopupMenuDivider(height: 6),
                  for (final e in clinicSortLabels.entries)
                    CheckedPopupMenuItem(
                      key: Key('cp-sort-${e.key}'),
                      value: 'sort:${e.key}',
                      checked: sortBy == e.key,
                      child: Text(e.value,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                  const PopupMenuDivider(height: 6),
                  CheckedPopupMenuItem(
                    key: const Key('cp-filter-debt'),
                    value: 'debt',
                    checked: debtOnly,
                    child: const Text('عليه دين/متبقٍ فقط',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  // م75 — إظهار المؤرشفين (مخفيون افتراضياً).
                  CheckedPopupMenuItem(
                    key: const Key('cp-filter-archived'),
                    value: 'archived',
                    checked: showArchived,
                    child: const Text('إظهار المؤرشفين',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ],
                child: SizedBox(
                  width: 38,
                  height: 36,
                  child: Icon(
                      debtOnly
                          ? Icons.filter_alt_rounded
                          : Icons.filter_alt_outlined,
                      size: 16,
                      color: debtOnly
                          ? BrandColors.red
                          : BrandColors.goldDark),
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),

      // ── م75 — شريط التحديد المتعدد (يظهر في وضع التحديد فقط) ──
      if (selectMode) _selectionBar(filtered),

      // ── القائمة ──
      Expanded(
        child: filtered.isEmpty
            ? Center(
                child: Text(
                  searchCtl.text.trim().isNotEmpty
                      ? 'لا توجد نتائج'
                      : 'لا يوجد مرضى في هذه العيادة',
                  style: TextStyle(
                      fontSize: 13, color: BrandColors.mut2),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
                itemCount: filtered.length,
                itemBuilder: (context, i) =>
                    _patientRow(filtered[i], cur, n),
              ),
      ),
    ]);
  }

  Widget _patientRow(
      ClinicPatientRow p, String cur, String Function(Object?) n) {
    final name = p.agg.name;
    final isSel = selected.contains(_pkey(p));
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      // م75 — تمييز الصف المحدَّد بخلفية خفيفة.
      color: isSel ? BrandColors.brand600.withValues(alpha: .08) : null,
      child: InkWell(
        // م90 — الهوية تدخل المفتاح عند انقسام السميّين (وإلا كما كان).
        key: Key('patient-card-$name'
            '${p.agg.identity.isEmpty ? '' : '|${p.agg.identity}'}'),
        borderRadius: BorderRadius.circular(14),
        // م75 — الضغط المطوّل يدخل وضع التحديد؛ وفي وضع التحديد النقر
        // يبدّل الاختيار بدل فتح الملف.
        onLongPress: selectMode ? null : () => _enterSelect(p),
        onTap: selectMode
            ? () => _toggleSelect(p)
            : () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => PatientProfileScreen(
                          patientName: name,
                          clinic: widget.clinicName,
                          // م90 — فتحُ هوية البطاقة نفسها لا السميّ.
                          identity: p.agg.identity)),
                ),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(children: [
            if (selectMode)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Icon(
                  isSel
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: isSel ? BrandColors.brand600 : BrandColors.mut2,
                ),
              ),
            CircleAvatar(
              radius: 17,
              backgroundColor:
                  BrandColors.brand600.withValues(alpha: .1),
              child: const Icon(Icons.person_rounded,
                  size: 17, color: BrandColors.brand600),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // م64 — لا شارات بجانب الاسم في قائمة السجلات (أُزيلت
                  // دين/تركيبات/تقرير بطلب المالك؛ فلتر الدين يعوّضها).
                  // م75 — شارة «مؤرشف» الرمادية عند إظهار المؤرشفين.
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (p.archived) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: BrandColors.mut2.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('مؤرشف',
                            style: TextStyle(
                                fontSize: 9.5,
                                color: BrandColors.mut2,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                  Text(
                    // م90 — سطر الهاتف الصغير يفرّق السميّين بصرياً.
                    '${p.agg.identity.isEmpty ? '' : '${p.agg.phone.isEmpty ? 'بلا رقم' : p.agg.phone} • '}'
                    '${p.agg.visitCount} زيارة • آخر: ${p.agg.lastDate.isEmpty ? '—' : p.agg.lastDate}',
                    style: TextStyle(
                        fontSize: 11, color: BrandColors.mut2),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(n(p.agg.total),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.goldDark)),
                Text(cur,
                    style: TextStyle(
                        fontSize: 11.5, color: BrandColors.mut2)),
              ],
            ),
            // م75 — في وضع التحديد نُخفي ⋮ (الأفعال تصير جماعية من الشريط).
            if (!selectMode)
              IconButton(
                key: Key('patient-more-$name'),
                visualDensity: VisualDensity.compact,
                onPressed: () => _openMore(p),
                icon: Icon(Icons.more_vert_rounded,
                    size: 17, color: BrandColors.mut2),
              ),
          ]),
        ),
      ),
    );
  }

  /// م75 — شريط التحديد: العدد + أرشفة/إلغاء + خروج. يعرض «إلغاء الأرشفة»
  /// حين يكون كل المحدَّدين مؤرشفين، و«أرشفة» فيما عدا ذلك.
  Widget _selectionBar(List<ClinicPatientRow> visible) {
    final sel = [for (final p in visible) if (selected.contains(_pkey(p))) p];
    final allArchived = sel.isNotEmpty && sel.every((p) => p.archived);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.brand600.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        IconButton(
          key: const Key('sel-exit'),
          visualDensity: VisualDensity.compact,
          onPressed: _exitSelect,
          icon: const Icon(Icons.close_rounded, size: 20),
        ),
        Expanded(
          child: Text('محدَّد: ${sel.length}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        if (allArchived)
          FilledButton.icon(
            key: const Key('sel-unarchive'),
            style: FilledButton.styleFrom(
                backgroundColor: BrandColors.brand600,
                visualDensity: VisualDensity.compact),
            onPressed:
                sel.isEmpty ? null : () => _unarchiveSelected(visible),
            icon: const Icon(Icons.unarchive_rounded, size: 16),
            label: const Text('إلغاء الأرشفة',
                style: TextStyle(fontSize: 12.5)),
          )
        else
          FilledButton.icon(
            key: const Key('sel-archive'),
            style: FilledButton.styleFrom(
                backgroundColor: BrandColors.red,
                visualDensity: VisualDensity.compact),
            onPressed: sel.isEmpty ? null : () => _archiveSelected(visible),
            icon: const Icon(Icons.archive_rounded, size: 16),
            label: const Text('أرشفة', style: TextStyle(fontSize: 12.5)),
          ),
      ]),
    );
  }

  // ── لوحة الإجراءات السريعة ──
  void _openMore(ClinicPatientRow p) {
    final name = p.agg.name;
    Widget action(Key key, IconData icon, String label,
            VoidCallback onTap) =>
        ListTile(
          key: key,
          dense: true,
          leading:
              Icon(icon, size: 18, color: BrandColors.brandIcon),
          title: Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: BrandColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      // م75 — قابلة للتمرير: بعد إضافة فعل الأرشفة صارت العناصر قد تتجاوز
      // ارتفاع النوافذ الصغيرة. SingleChildScrollView يمنع أي تجاوز مهما
      // زادت الأفعال مستقبلاً بدل كسر التخطيط.
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.goldDark)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 18)),
              ]),
            ),
            action(Key('act-visit-$name'), Icons.add_rounded,
                'زيارة جديدة', () => _addVisit(p)),
            action(Key('act-profile-$name'),
                Icons.description_rounded, 'السجل الكامل',
                () => _openProfile(name, identity: p.agg.identity)),
            action(Key('act-edit-$name'), Icons.edit_rounded,
                'تعديل البيانات', () => _editPatient(p)),
            action(Key('act-plan-$name'),
                Icons.checklist_rounded, 'خطة العلاج',
                () => _openProfile(name, identity: p.agg.identity)),
            action(Key('act-print-$name'), Icons.print_rounded,
                'طباعة PDF',
                () => _openProfile(name,
                    print: true, identity: p.agg.identity)),
            // م75 — أرشفة/إلغاء أرشفة المريض الواحد.
            if (p.archived)
              action(Key('act-unarchive-$name'), Icons.unarchive_rounded,
                  'إلغاء الأرشفة', () => _unarchiveOne(p))
            else
              action(Key('act-archive-$name'), Icons.archive_rounded,
                  'أرشفة المريض', () => _confirmArchive([p])),
            const SizedBox(height: 8),
          ],
        ),
        ),
      ),
    );
  }

  void _openProfile(String name, {bool print = false, String identity = ''}) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PatientProfileScreen(
            patientName: name,
            clinic: widget.clinicName,
            // م90 — هوية السميّ المقصود من الإجراءات السريعة أيضاً.
            identity: identity,
            autoPrint: print)));
  }

  // ── م75 — أرشفة المرضى ──────────────────────────────────────────────────

  /// حوار تأكيد يوضّح صراحةً أن المال والمعالجات لا تتأثر — أهم سطر للطبيب.
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
            key: const Key('archive-confirm'),
            style: FilledButton.styleFrom(backgroundColor: BrandColors.red),
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
        content: Text(count == 1 ? 'أُرشف مريض' : 'أُرشف $count مرضى'),
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
    final pts = [for (final p in visible) if (selected.contains(_pkey(p))) p];
    _confirmArchive([for (final p in pts) if (!p.archived) p]);
  }

  void _unarchiveSelected(List<ClinicPatientRow> visible) {
    final pts = [
      for (final p in visible)
        if (selected.contains(_pkey(p)) && p.archived) p,
    ];
    _archive.unarchiveAll(
        [for (final p in pts) (name: p.agg.name, clinic: p.agg.clinic)]);
    final c = pts.length;
    _exitSelect();
    ref.read(patientsRevProvider.notifier).state++;
    _snack(c == 1 ? 'أُلغيت أرشفة مريض' : 'أُلغيت أرشفة $c مرضى');
  }

  /// م58 — زيارة جديدة من قائمة المرضى: ورقة الزيارة السريعة نفسها
  /// (بلا مغادرة القائمة)، و«الخيارات الكاملة» تسلك المسار القديم.
  void _addVisit(ClinicPatientRow p) {
    // م119 — إضافة الزيارات صلاحية مستقلة.
    if (!gateStaff(context, 'records.add')) return;
    final phones = p.phones.split(' ');
    final phone = phones.isNotEmpty ? phones.first : '';
    showQuickVisitSheet(
      context,
      name: p.agg.name,
      clinic: widget.clinicName,
      phone: phone,
      onFullOptions: () => _addVisitFull(p),
    );
  }

  /// المسار القديم — توأم router.push home {patient, clinic}.
  void _addVisitFull(ClinicPatientRow p) {
    final phones = p.phones.split(' ');
    ref.read(addVisitDraftProvider.notifier).state = {
      'name': p.agg.name,
      'clinic': widget.clinicName,
      'phone': phones.isNotEmpty ? phones.first : '',
    };
    // القفز لتبويب الرئيسية عبر مزود الصدفة (استيراد دائري ممنوع —
    // القيمة النصية مطابقة لمعرف التبويب).
    ref.read(homeJumpProvider.notifier).state++;
  }

  /// تعديل بيانات المريض — الاسم والهاتفان باكتساح الجداول الأربعة.
  Future<void> _editPatient(ClinicPatientRow p) async {
    final repos = ref.read(reposProvider);
    // م-عزل الهوية — قصر مصادر التعبئة على صفوف هذه الهوية: هاتفُ السميّ
    // لا يُعبَّأ في حوار تعديل سميّه.
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
        if (jsTruthy(r[key])) return '${r[key]}';
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
              key: const Key('edit-pat-name'),
              controller: nameCtl,
              decoration: const InputDecoration(
                  isDense: true, labelText: 'الاسم'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('edit-pat-phone'),
              controller: phoneCtl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  isDense: true, labelText: 'رقم الهاتف'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('edit-pat-phone2'),
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
              key: const Key('edit-pat-save'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    final touched = editPatientCascade(
      repos,
      origName: p.agg.name,
      newName: nameCtl.text,
      phone: phoneCtl.text.trim(),
      phone2: phone2Ctl.text.trim(),
      clinic: widget.clinicName, // م35 — محصور بعيادة الشاشة.
      identity: p.agg.identity, // م-عزل الهوية — لا يمسّ السميّ.
    );
    ref.read(patientsRevProvider.notifier).state++;
    // ترحيل treatmentPlans مع الاسم يكتب app.config — نبضة الإعدادات
    // تعيد بناء سطر «خطة علاج: س/ص» على البطاقات فوراً.
    ref.read(configRevProvider.notifier).state++;
    _snack('تم تحديث بيانات المريض ($touched صفاً)');
  }
}

/// نبضة القفز للرئيسية — تلتقطها الصدفة (كسر الاستيراد الدائري).
final homeJumpProvider = StateProvider<int>((ref) => 0);
