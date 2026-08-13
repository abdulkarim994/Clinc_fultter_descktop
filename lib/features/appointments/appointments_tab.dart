/// م164 — شاشة الحجوزات (النظام التقليدي) للهاتف — تصميم جديد كلياً للمس:
///   • رقائق العيادات أعلى الشاشة (عيادة واحدة ⇒ تُختار تلقائياً؛ التعدد ⇒
///     الاختيار إلزامي قبل أي حجز — لا استخدام لأول عيادة تلقائياً).
///   • شريط أيام أفقي (أسبوعان) بعدّادات المواعيد + زر «اليوم» + قفزة لأي
///     تاريخ — بدل التقويم الشهري الذي كان يستهلك معظم الشاشة.
///   • Timeline عمودي: الوقت يميناً وبطاقة (الاسم + الخدمة + شارة الحالة
///     اسماً ولوناً) وخط «الآن» في يوم اليوم والاستراحات ☕ بلون كهرماني.
///   • الضغط على بطاقة ⇒ ورقة إجراءات سريعة: اتصال/واتساب/SMS/دين بالمتبقي/
///     الحالة التالية بنقرة/تعديل/نسخ/إنهاء الزيارة/سجل المريض/إلغاء/لم
///     يحضر/حذف — بلا صفحات متتالية.
///   • معالج إضافة (موعد أو استراحة) بورقة سفلية واحدة: العيادة ← التاريخ ←
///     شبكة أوقات الدوام (المشغول والاستراحات معطلة) ← المريض ← الخدمة.
///   • دورة الحياة: إنهاء الزيارة يختم archivedOn وينقل الصف لقسم «أرشيف
///     اليوم» (لا ازدواج) ⇒ حذف تلقائي بعد يومين بشواهد قبور تمر بالمزامنة.
///   • القيم القديمة pending/scheduled تُقرأ «قادم»؛ الحفظ الجديد يبقى
///     'pending' للتوافق الخلفي الكامل مع الأجهزة القديمة.
/// الكتابة كلها عبر upsertLocal/delete ⇒ مختومة dirty وجاهزة للمزامنة.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../../core/utils/uid.dart';
import '../../core/widgets/double_confirm.dart';
import '../../data/repositories/patients_repository.dart'
    show patientKeyFor, clinicKeyFor;
import '../patients/patients_tab.dart'
    show patientSearchProvider, patientsRevProvider;
import '../shell/app_shell.dart' show activeTabProvider;
import 'appointments_logic.dart';
import 'appt_lifecycle.dart' hide JMap;

/// نبضة إعادة قراءة بعد كل كتابة موعد.
final apptRevProvider = StateProvider<int>((ref) => 0);

/// مسودة «موعد متابعة» القادمة من شاشة الإضافة (اسم/هاتف/خدمة/عيادة) —
/// توأم query {followup:'1', ...}. يستهلكها التبويب (أو شاشة الدور) مرة.
final followUpDraftProvider = StateProvider<JMap?>((ref) => null);

/// م171 — يوم الهبوط المطلوب عند فتح تبويب المواعيد (من مربع مواعيد
/// بطاقة المريض: «النقر يأخذني ليوم الحجز») — يُستهلك مرةً ثم يُصفَّر.
final apptGoDayProvider = StateProvider<String>((ref) => '');

/// م171 — مسودة «حجز موعد» من سجل المريض {name, phone, clinic}: يفتح بها
/// المعالج معبأً (توأم مسودة المتابعة بلا وسمها) — تُستهلك ثم تُصفَّر.
final apptBookDraftProvider = StateProvider<JMap?>((ref) => null);

/// م164 — العيادة المختارة في شاشة الحجوزات (تبقى عبر التنقل بين التبويبات).
final apptClinicProvider = StateProvider<String>((ref) => '');

/// م173 — التبويب المفتوح في شاشة الحجز (0 الجدول، 1 أرشيف اليوم،
/// 2 القادمة) — يبقى عبر مغادرة التبويب والعودة إليه خلال الجلسة.
final apptViewTabProvider = StateProvider<int>((ref) => 0);

class AppointmentsTab extends ConsumerStatefulWidget {
  const AppointmentsTab(
      {super.key, this.dayOnly = false, this.initialDay, this.bookPreset});

  /// م166 — وضع «يوم فقط»: جدول اليوم + زرا الإضافة والاستراحة فقط
  /// (بلا رأس ولا شريط أيام ولا أرشيف ولا قادمة) — لشاشة اليوم الكاملة.
  final bool dayOnly;

  /// اليوم الابتدائي (شاشة اليوم الكاملة تمرر يومها).
  final String? initialDay;

  /// م173 — مسودة حجزٍ تُفتح بها فوراً (شاشة الحجز الكاملة من بطاقة
  /// المريض): {name, phone, clinic} — تمريرٌ مباشر لا عبر المزوّد كي لا
  /// تخطفها نسخة التبويب الحية خلف البطاقة.
  final JMap? bookPreset;

  @override
  ConsumerState<AppointmentsTab> createState() => _AppointmentsTabState();
}

/// م173 — شاشة الحجز الكاملة (قرار المالك): «حجز موعد» من بطاقة المريض
/// أو ثلاث نقاطها يفتح نافذةً بملء الشاشة تستضيف واجهة الحجز نفسها
/// بمسودة معبأة — والرجوع/الإغلاق يعيد لبطاقة المريض حيث كانت.
class BookingFullScreen extends StatelessWidget {
  const BookingFullScreen({super.key, this.preset});

  /// مسودة {name, phone, clinic} — null يفتح الشاشة بلا معالج.
  final JMap? preset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BrandColors.paper,
      appBar: AppBar(
        title: const Text('الحجز',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        backgroundColor: BrandColors.brand,
        foregroundColor: BrandColors.goldLight,
      ),
      body: AppointmentsTab(bookPreset: preset),
    );
  }
}

/// م166 — شاشة اليوم الكاملة (هاتف): كل مواعيد يومٍ لعيادةٍ بشاشة مستقلة
/// بنفس البطاقات وورقة الإجراءات وزرّي الإضافة والاستراحة — بلا أرشيف
/// (قرار المالك). إعادة استعمال كاملة لمكوّن الحجوزات بوضع «يوم فقط».
class DayScheduleScreen extends ConsumerWidget {
  const DayScheduleScreen({super.key, required this.day});

  final String day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(appConfigProvider);
    final clinics = clinicsOf(cfg);
    final clinic = clinics.length == 1
        ? clinics.first
        : ref.watch(apptClinicProvider);
    final label = clinic.isEmpty
        ? ''
        : ' — ${clinic == kNoClinic ? 'غير محددة' : clinic}';
    return Scaffold(
      appBar: AppBar(
        title: Text('$day (${dayLabel(day)})$label',
            style: const TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w800)),
      ),
      body: AppointmentsTab(dayOnly: true, initialDay: day),
    );
  }
}

class _AppointmentsTabState extends ConsumerState<AppointmentsTab>
    with SingleTickerProviderStateMixin {
  String selectedDay = '';

  /// م173 — متحكم التبويبات الثلاثة (الجدول/أرشيف اليوم/القادمة) بمؤشر
  /// منزلق وسحبٍ أفقي — الفهرس يُحفظ في المزوّد ليبقى خلال الجلسة.
  late final TabController _tabCtl;

  /// م173 — فلتر أرشيف اليوم (all/completed/cancelled/no_show).
  String _archFilter = 'all';

  @override
  void initState() {
    super.initState();
    selectedDay = widget.initialDay ?? getCurrentDate();
    _tabCtl = TabController(
      length: 3,
      vsync: this,
      initialIndex:
          widget.dayOnly ? 0 : ref.read(apptViewTabProvider).clamp(0, 2),
    );
    _tabCtl.addListener(() {
      if (!widget.dayOnly && !_tabCtl.indexIsChanging) {
        ref.read(apptViewTabProvider.notifier).state = _tabCtl.index;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // م173 — مسودة شاشة الحجز الكاملة (من بطاقة المريض): فتح المعالج
      // معبأً مباشرةً — تمريرٌ مباشر بلا مزوّد.
      final bp = widget.bookPreset;
      if (bp != null) {
        final clinic = '${bp['clinic'] ?? ''}';
        if (clinic.isNotEmpty) {
          ref.read(apptClinicProvider.notifier).state = clinic;
        }
        if (jsTruthy(bp['name'])) {
          _openWizard(preset: {
            'name': bp['name'],
            'phone': bp['phone'],
            'clinic': clinic,
          });
        }
      }
      // م166 — شاشة اليوم لا تنظف الأرشيف ولا تخطف مسودة المتابعة.
      if (widget.dayOnly) return;
      _purgeOldArchive();
      _consumeFollowUpDraft();
      // م171 — الهبوط على يوم حجزٍ محدد ثم فتح معالجٍ معبأ إن وُجدت مسودة.
      _consumeGoDay();
      _consumeBookDraft();
    });
  }

  @override
  void dispose() {
    _tabCtl.dispose();
    super.dispose();
  }

  /// م171 — الهبوط على يوم الحجز القادم من مربع مواعيد بطاقة المريض.
  void _consumeGoDay() {
    final go = ref.read(apptGoDayProvider);
    if (go.isEmpty || !mounted) return;
    ref.read(apptGoDayProvider.notifier).state = '';
    // م173 — يوم الهبوط يخص الجدول: يُفتح تبويبه أياً كان المفتوح.
    _tabCtl.index = 0;
    setState(() => selectedDay = go);
  }

  /// م171 — فتح المعالج معبأً بمسودة حجزٍ من سجل المريض (الثلاث نقاط/
  /// بطاقة المريض) — اسمٌ وهاتفٌ وعيادةٌ جاهزة، بلا وسم متابعة.
  void _consumeBookDraft() {
    final draft = ref.read(apptBookDraftProvider);
    if (draft == null || !mounted) return;
    ref.read(apptBookDraftProvider.notifier).state = null;
    final clinic = '${draft['clinic'] ?? ''}';
    if (clinic.isNotEmpty) {
      ref.read(apptClinicProvider.notifier).state = clinic;
    }
    _openWizard(preset: {
      'name': draft['name'],
      'phone': draft['phone'],
      'clinic': clinic,
    });
  }

  /// م164 — تنظيف الأرشيف: حذف المؤرشف الأقدم من يومين (شواهد قبور تمر
  /// بالمزامنة — توأم purgeOldDays في نظام الدور).
  void _purgeOldArchive() {
    final repos = ref.read(reposProvider);
    final ids =
        archivedIdsToPurge(repos.appointments.getAll(), getCurrentDate());
    for (final id in ids) {
      repos.appointments.delete(id);
    }
    if (ids.isNotEmpty) _bump();
  }

  /// مسودة المتابعة (goFollowUpAppt) — تفتح المعالج مسبق التعبئة بعيادة
  /// السجل الذي جاءت منه (م164).
  void _consumeFollowUpDraft() {
    final draft = ref.read(followUpDraftProvider);
    if (draft == null || !mounted) return;
    ref.read(followUpDraftProvider.notifier).state = null;
    final clinic = '${draft['clinic'] ?? ''}';
    if (clinic.isNotEmpty) {
      ref.read(apptClinicProvider.notifier).state = clinic;
    }
    _openWizard(
      followUp: true,
      preset: {
        'name': draft['name'],
        'phone': draft['phone'],
        'service': draft['service'],
        'clinic': clinic,
        'notes': jsTruthy(draft['name'])
            ? 'متابعة — ${draft['service'] ?? ''}'
            : '',
      },
    );
  }

  void _bump() {
    ref.read(apptRevProvider.notifier).state++;
    if (mounted) setState(() {});
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _launch(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  // ── قراءة الحالة المشتركة ──

  String get _clinic {
    final cfg = ref.read(appConfigProvider);
    final clinics = clinicsOf(cfg);
    if (clinics.length == 1) return clinics.first;
    return ref.read(apptClinicProvider);
  }

  // ── كتابة الحالات (دورة الحياة) ──

  void _setStatus(String id, String status) {
    final repos = ref.read(reposProvider);
    final a = repos.appointments.getById(id);
    if (a == null) return;
    final terminal = kTerminalStatuses.contains(status);
    repos.appointments.upsertLocal({
      ...a,
      'status': status,
      // ختم يوم الأرشفة عند الانتقال لحالة نهائية — يمسحه التراجع.
      'archivedOn': terminal ? getCurrentDate() : '',
      '_mod': jsNow(),
    });
    _bump();
  }

  void _finishVisit(String id) {
    _setStatus(id, 'completed');
    _snack('تم إنهاء الزيارة — انتقل الموعد لأرشيف اليوم');
  }

  Future<void> _deleteAppt(JMap a) async {
    final ok = await confirmDelete(
      context,
      config: ref.read(appConfigProvider),
      type: 'appt',
      title: isBreakRow(a) ? 'حذف الاستراحة؟' : 'حذف الموعد نهائياً؟',
      msg: isBreakRow(a)
          ? '${jsOr(a['name'], 'استراحة')}'
          : 'المريض: ${a['name'] ?? '—'}',
    );
    if (!ok) return;
    ref.read(reposProvider).appointments.delete('${a['id']}');
    _snack('تم الحذف');
    _bump();
  }

  void _goPatient(String? name) {
    if (name == null || name.isEmpty) return;
    ref.read(patientSearchProvider.notifier).state = name;
    ref.read(activeTabProvider.notifier).state = 'clinics';
  }

  // ═════════════════════════ البناء ═════════════════════════

  @override
  Widget build(BuildContext context) {
    ref.watch(apptRevProvider);
    ref.watch(apptClinicProvider);
    final repos = ref.watch(reposProvider);
    final appointments = repos.appointments.getAll();
    final records = repos.records.getAll();
    final prosthetics = repos.prosthetics.getAll();
    final debts = repos.debts.getAll();
    final cfg = ref.watch(appConfigProvider);
    final centerName = '${jsOr(cfg['centerName'], 'المركز')}';
    final currency = ref.watch(currencyProvider);
    final clinics = clinicsOf(cfg);
    final clinic = _clinic;
    final today = getCurrentDate();

    // م172 — وصول مسودة حجزٍ/يوم هبوطٍ والتبويب مفتوحٌ أصلاً (الزر
    // العائم في الصدفة أو بطاقة مريضٍ فوق نفس التبويب): استهلاكٌ فوري.
    ref.listen(apptBookDraftProvider, (prev, next) {
      if (next != null) _consumeBookDraft();
    });
    ref.listen(apptGoDayProvider, (prev, next) {
      if (next.isNotEmpty) _consumeGoDay();
    });
    final apptMap = buildApptMap(
      appointments: appointments,
      records: records,
      prosthetics: prosthetics,
    );

    // صفوف اليوم المختار للعيادة الحالية — مرتبةً بالوقت (بلا وقتٍ آخراً).
    // م164 — بعيادة واحدة لا فلترة: الصفوف القديمة بلا عيادة تخص العيادة
    // الوحيدة بداهةً (توافق خلفي كامل — لا موعد يختفي بعد التحديث).
    final filterKey = clinics.length <= 1 ? '' : clinic;
    final dayAll = filterByClinic([...?apptMap[selectedDay]], filterKey)
      ..sort((a, b) {
        final ta = hhmmToMinutes(a['time']) ?? 24 * 60;
        final tb = hhmmToMinutes(b['time']) ?? 24 * 60;
        return ta.compareTo(tb);
      });
    final (active, archived) = splitDayRows(dayAll);
    final upcoming = upcomingForClinic(apptMap, filterKey, today: today);
    final needClinic = clinicRequired(cfg) && clinic.isEmpty;

    // ── م166: وضع «يوم فقط» — الجدول وزرا الإضافة فقط (شاشة اليوم) ──
    if (widget.dayOnly) {
      return ListView(
        key: const Key('appointments-day-only'),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
        children: [
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('appt-add-toggle'),
                style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.gold,
                    foregroundColor: BrandColors.brand900,
                    padding: const EdgeInsets.symmetric(vertical: 10)),
                onPressed: () => _openWizard(),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('إضافة موعد',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              key: const Key('appt-add-break'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB45309),
                side: const BorderSide(color: Color(0xFFD97706)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 10),
              ),
              onPressed: () => _openWizard(breakMode: true),
              icon: const Icon(Icons.free_breakfast_rounded, size: 15),
              label: const Text('استراحة',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${active.where((a) => !isBreakRow(a)).length} موعد',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.brand700),
                  ),
                  const SizedBox(height: 5),
                  if (active.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Center(
                        child: Text('لا مواعيد في هذا اليوم',
                            style: TextStyle(
                                fontSize: 11.5, color: BrandColors.mut2)),
                      ),
                    )
                  else
                    ..._timeline(
                        active, debts, centerName, currency, today),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // ── م173 — واجهة الحجز الجديدة (قرار المالك): رأسٌ بعنوان «الحجز»
    // يميناً ومحدد عيادةٍ كبير يساراً، وشريط ثلاثة تبويبات بمؤشر منزلق
    // (جدول المواعيد/أرشيف اليوم/المواعيد القادمة) بسحبٍ أفقي بينها —
    // كلُّ قسمٍ في تبويبه المستقل بدل قائمةٍ واحدة متراصة. ──
    return Column(
      key: const Key('appointments-tab'),
      children: [
        _headerBar(clinics, clinic, apptMap, today),
        _tabsBar(archived.length, upcoming.length),
        Expanded(
          child: TabBarView(
            controller: _tabCtl,
            children: [
              _scheduleTabView(needClinic, clinics, apptMap, filterKey,
                  active, debts, centerName, currency, today),
              _archiveTabView(needClinic, clinics, archived),
              _upcomingTabView(needClinic, clinics, upcoming, clinic),
            ],
          ),
        ),
      ],
    );
  }

  /// م173 — رأس شاشة الحجز: العنوان الكبير يميناً واختيار العيادة بخطٍّ
  /// كبير يساراً (بدل السطر الصغير) — ينقر فيفتح ورقة الاختيار.
  Widget _headerBar(List<String> clinics, String clinic,
      Map<String, List<JMap>> apptMap, String today) {
    final none = clinic.isEmpty;
    final label = none
        ? 'اختر العيادة'
        : clinic == kNoClinic
            ? 'غير محددة'
            : clinic;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(children: [
        const Icon(Icons.event_note_rounded,
            size: 19, color: BrandColors.goldDark),
        const SizedBox(width: 7),
        Expanded(
          child: Text('الحجز',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: BrandColors.brandText)),
        ),
        if (clinics.length == 1)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(clinics.first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: BrandColors.brand700)),
          )
        else
          // م174 — قائمة منسدلة تنبثق تحت السهم مباشرةً (قرار المالك —
          // كانت ورقةً سفلية): نفس العناصر حرفياً بعدّاد مواعيد اليوم.
          MenuAnchor(
            style: MenuStyle(
              backgroundColor:
                  WidgetStatePropertyAll(BrandColors.surface),
              elevation: const WidgetStatePropertyAll(6),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: BrandColors.line),
                ),
              ),
            ),
            menuChildren: [
              for (final c in clinics) _clinicMenuItem(c, c, apptMap, today),
              if (hasUnassignedClinic(
                  ref.read(reposProvider).appointments.getAll()))
                _clinicMenuItem(kNoClinic, 'غير محددة', apptMap, today),
            ],
            builder: (ctx, controller, _) => InkWell(
              key: const Key('appt-clinic-pill'),
              borderRadius: BorderRadius.circular(12),
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            color: none
                                ? BrandColors.goldDark
                                : BrandColors.brand700)),
                  ),
                  Icon(Icons.expand_more_rounded,
                      size: 19,
                      color: none
                          ? BrandColors.goldDark
                          : BrandColors.brand700),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  /// م174 — عنصر القائمة المنسدلة لعيادة: اختيارٌ بنقرة + عدّاد مواعيد
  /// اليوم (توأم صفوف الورقة السفلية السابقة بنفس المفاتيح حرفياً).
  Widget _clinicMenuItem(String value, String label,
      Map<String, List<JMap>> apptMap, String today) {
    final on = ref.read(apptClinicProvider) == value;
    final n = filterByClinic([...?apptMap[today]], value)
        .where((a) => !isBreakRow(a) && !isTerminalStatus(a['status']))
        .length;
    return MenuItemButton(
      key: Key('appt-clinic-$value'),
      onPressed: () =>
          ref.read(apptClinicProvider.notifier).state = value,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200),
        child: Row(children: [
          Icon(
            on
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            size: 17,
            color: on ? BrandColors.brand600 : BrandColors.mut2,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: on ? FontWeight.w900 : FontWeight.w700,
                    color:
                        on ? BrandColors.brand700 : BrandColors.ink)),
          ),
          Text(n > 0 ? '$n اليوم' : '—',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: n > 0 ? BrandColors.brand600 : BrandColors.mut2)),
        ]),
      ),
    );
  }

  /// م173 — شريط التبويبات الثلاثة بمؤشرٍ منزلق بهوية التطبيق (توأم
  /// تبويبات بطاقة المريض في الصورة المرجعية): النشط أخضر العلامة بخطٍّ
  /// سفلي منزلق، وغير النشط باهت — مع عدّادين للأرشيف والقادمة.
  Widget _tabsBar(int archCount, int upCount) {
    Widget tab(Key key, String label, int? count) => Tab(
          key: key,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (count != null && count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: BrandColors.gold.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: BrandColors.gold.withValues(alpha: .45)),
                ),
                child: Text('$count',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.goldDark)),
              ),
            ],
          ]),
        );
    return Container(
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border(
            bottom: BorderSide(color: BrandColors.line, width: .8)),
      ),
      child: TabBar(
        controller: _tabCtl,
        labelColor: BrandColors.brand700,
        unselectedLabelColor: BrandColors.mut,
        labelStyle:
            const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
        unselectedLabelStyle:
            const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        indicatorColor: BrandColors.brand600,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        tabs: [
          tab(const Key('appt-tab-schedule'), 'جدول المواعيد', null),
          tab(const Key('appt-tab-archive'), 'أرشيف اليوم', archCount),
          tab(const Key('appt-tab-upcoming'), 'المواعيد القادمة', upCount),
        ],
      ),
    );
  }

  /// م173 — تبويب «جدول المواعيد»: شريط الأيام وأزرار الإضافة وجدول
  /// اليوم فقط (الأرشيف والقادمة انتقلا لتبويبيهما).
  Widget _scheduleTabView(
      bool needClinic,
      List<String> clinics,
      Map<String, List<JMap>> apptMap,
      String filterKey,
      List<JMap> active,
      List<JMap> debts,
      String centerName,
      String currency,
      String today) {
    return ListView(
      key: const Key('appt-view-schedule'),
      // م165 — هوامش مشدودة: استغلال أفضل لعرض الهاتف.
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 84),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      '$selectedDay (${dayLabel(selectedDay)})',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.brand700),
                    ),
                  ),
                  IconButton(
                    key: const Key('appt-today'),
                    tooltip: 'اليوم',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                    onPressed: () => setState(() => selectedDay = today),
                    icon: Icon(Icons.today_rounded,
                        size: 18, color: BrandColors.brandIcon),
                  ),
                  IconButton(
                    key: const Key('appt-jump-date'),
                    tooltip: 'الانتقال لتاريخ',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                    onPressed: () async {
                      final init =
                          DateTime.tryParse(selectedDay) ?? DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: init,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setState(() => selectedDay = _ymd(picked));
                      }
                    },
                    icon: Icon(Icons.calendar_month_rounded,
                        size: 18, color: BrandColors.brandIcon),
                  ),
                ]),
                const SizedBox(height: 5),
                SizedBox(
                  height: 58,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < 14; i++)
                        _stripDay(
                          _ymd(DateTime.parse('${today}T00:00:00')
                              .add(Duration(days: i))),
                          apptMap,
                          filterKey,
                          today,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 7),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('appt-add-toggle'),
                      style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.gold,
                          foregroundColor: BrandColors.brand900,
                          padding:
                              const EdgeInsets.symmetric(vertical: 10)),
                      onPressed: () => _openWizard(),
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('إضافة موعد',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    key: const Key('appt-add-break'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB45309),
                      side: const BorderSide(color: Color(0xFFD97706)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 10),
                    ),
                    onPressed: () => _openWizard(breakMode: true),
                    icon:
                        const Icon(Icons.free_breakfast_rounded, size: 15),
                    label: const Text('استراحة',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ]),
              ],
            ),
          ),
        ),

        // ── جدول اليوم (Timeline) — م165: بلا تكرار التاريخ (في الرأس) ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: needClinic
                ? _clinicPrompt(clinics)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // م166 — الرأس ينقر: شاشة اليوم الكاملة (عرض/تعديل/
                      // حذف/إضافة لكل مواعيد هذا اليوم لهذه العيادة).
                      InkWell(
                        key: const Key('appt-day-open'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                DayScheduleScreen(day: selectedDay),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                'مواعيد ${dayLabel(selectedDay)} — '
                                '${active.where((a) => !isBreakRow(a)).length} موعد',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: BrandColors.brand700),
                              ),
                            ),
                            Icon(Icons.open_in_full_rounded,
                                size: 14, color: BrandColors.brandIcon),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (active.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Center(
                            child: Text('لا مواعيد في هذا اليوم',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: BrandColors.mut2)),
                          ),
                        )
                      else
                        ..._timeline(active, debts, centerName, currency,
                            today),
                    ],
                  ),
          ),
        ),

      ],
    );
  }

  /// م173 — تبويب «أرشيف اليوم»: القسم المنقول من القائمة المتراصة إلى
  /// تبويبه المستقل، مع شرائح تصفيةٍ بالحالة (الكل/مكتمل/ملغى/لم يحضر).
  Widget _archiveTabView(
      bool needClinic, List<String> clinics, List<JMap> archived) {
    if (needClinic) {
      return ListView(
        key: const Key('appt-view-archive'),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 84),
        children: [Card(child: _clinicPrompt(clinics))],
      );
    }
    final rows = [
      for (final a in archived)
        if (_archFilter == 'all' || normApptStatus(a['status']) == _archFilter)
          a,
    ];
    Widget filterChip(String value, String label) {
      final on = _archFilter == value;
      return InkWell(
        key: Key('appt-arch-f-$value'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _archFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on
                ? BrandColors.goldDark
                : BrandColors.gold.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: on
                    ? BrandColors.goldDark
                    : BrandColors.gold.withValues(alpha: .4)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : BrandColors.goldDark)),
        ),
      );
    }

    return ListView(
      key: const Key('appt-view-archive'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 84),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 14, color: BrandColors.goldDark),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('أرشيف اليوم (${archived.length})',
                        key: const Key('appt-archive-title'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.goldDark)),
                  ),
                  Flexible(
                    child: Text('يُحذف تلقائياً بعد يومين',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10, color: BrandColors.mut2)),
                  ),
                ]),
                if (archived.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      filterChip('all', 'الكل'),
                      const SizedBox(width: 5),
                      filterChip('completed', 'مكتمل'),
                      const SizedBox(width: 5),
                      filterChip('cancelled', 'ملغى'),
                      const SizedBox(width: 5),
                      filterChip('no_show', 'لم يحضر'),
                    ]),
                  ),
                ],
                const SizedBox(height: 6),
                if (archived.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Center(
                      child: Text('لا مواعيد مؤرشفة اليوم',
                          style: TextStyle(
                              fontSize: 11.5, color: BrandColors.mut2)),
                    ),
                  )
                else if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Center(
                      child: Text('لا صفوف بهذه الحالة',
                          style: TextStyle(
                              fontSize: 11.5, color: BrandColors.mut2)),
                    ),
                  )
                else
                  for (final a in rows) _archivedRow(a),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// م173 — تبويب «المواعيد القادمة»: القائمة منقولةً لتبويبها مجمعةً
  /// بالأيام برؤوس تواريخ — والنقر يقفز ليوم الحجز في تبويب الجدول.
  Widget _upcomingTabView(bool needClinic, List<String> clinics,
      List<JMap> upcoming, String clinic) {
    if (needClinic) {
      return ListView(
        key: const Key('appt-view-upcoming'),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 84),
        children: [Card(child: _clinicPrompt(clinics))],
      );
    }
    // تجميعٌ بالتاريخ (القائمة أصلاً مرتبة تصاعدياً بالتاريخ فالوقت).
    final days = <String, List<JMap>>{};
    for (final a in upcoming) {
      days.putIfAbsent('${a['date']}', () => []).add(a);
    }
    return ListView(
      key: const Key('appt-view-upcoming'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 84),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (upcoming.isEmpty)
                  Row(children: [
                    const Expanded(
                      child: Text('المواعيد القادمة',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800)),
                    ),
                    Flexible(
                      child: Text('لا توجد مواعيد قادمة',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: BrandColors.mut2)),
                    ),
                  ]),
                for (final e in days.entries) ...[
                  // ── رأس اليوم: التاريخ + اسم اليوم + عدّاد ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 7, 2, 4),
                    child: Row(children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 12,
                          color: dayDiff(e.key) == 0
                              ? const Color(0xFFF59E0B)
                              : BrandColors.brand600),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${e.key} (${dayLabel(e.key)})',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                            color: dayDiff(e.key) == 0
                                ? const Color(0xFFB45309)
                                : BrandColors.brand700,
                          ),
                        ),
                      ),
                      Text('${e.value.length}',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: BrandColors.mut)),
                    ]),
                  ),
                  for (final a in e.value)
                    InkWell(
                      key: Key('upcoming-${a['id']}'),
                      borderRadius: BorderRadius.circular(10),
                      // النقر يقفز ليوم الحجز في تبويب الجدول (م173).
                      onTap: () {
                        setState(() => selectedDay = '${a['date']}');
                        _tabCtl.animateTo(0);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${a['name'] ?? ''}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: BrandColors.brand700)),
                                // م165ب — أغمق للقراءة والتوقيت أبرز.
                                Text.rich(
                                  TextSpan(children: [
                                    if (jsTruthy(a['time']))
                                      TextSpan(
                                        text: to12h('${a['time']}'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: BrandColors.brand700),
                                      )
                                    else
                                      const TextSpan(text: 'بلا وقت'),
                                    TextSpan(
                                        text:
                                            ' — ${jsOr(a['service'], '—')}'
                                            '${clinic.isEmpty && apptClinicOf(a).isNotEmpty ? ' — ${apptClinicOf(a)}' : ''}'),
                                  ]),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: BrandColors.ink
                                          .withValues(alpha: .68)),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_back_ios_new_rounded,
                              size: 11, color: BrandColors.faint),
                        ]),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';



  /// مُطالبة اختيار العيادة — لا جدول قبل تحديدها (التعدد ⇒ إلزامي).
  Widget _clinicPrompt(List<String> clinics) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        // م165 — أيقونة طبية (كانت storefront تشبه الدكان).
        const Icon(Icons.medical_services_rounded,
            size: 28, color: BrandColors.brand600),
        const SizedBox(height: 6),
        const Text('اختر العيادة لعرض جدولها',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text('كل عيادة لها مواعيدها وجدولها واستراحاتها الخاصة',
            style: TextStyle(fontSize: 11, color: BrandColors.mut2)),
      ]),
    );
  }

  // ── خلية يوم في الشريط ──
  Widget _stripDay(String ds, Map<String, List<JMap>> apptMap,
      String clinic, String today) {
    final rows = filterByClinic([...?apptMap[ds]], clinic);
    final count = rows
        .where((a) => !isBreakRow(a) && !isTerminalStatus(a['status']))
        .length;
    final selected = ds == selectedDay;
    final isToday = ds == today;
    final d = DateTime.parse('${ds}T00:00:00');
    const wd = ['إث', 'ثل', 'أر', 'خم', 'جم', 'سب', 'أح'];
    return InkWell(
      key: Key('cal-day-$ds'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => selectedDay = ds),
      child: Container(
        width: 42,
        margin: const EdgeInsetsDirectional.only(end: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? BrandColors.brand600
              : isToday
                  ? BrandColors.gold.withValues(alpha: .18)
                  : BrandColors.surface2,
          border: Border.all(
            color: selected
                ? BrandColors.brand600
                : isToday
                    ? BrandColors.gold
                    : BrandColors.line,
            width: isToday && !selected ? 1.2 : .8,
          ),
        ),
        // م41/م164 — FittedBox: على مقاييس الخط الكبيرة تنكمش الخلية
        // بدل الفيضان (ارتفاع الشريط ثابت 62).
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(wd[d.weekday - 1],
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white70 : BrandColors.mut2)),
              Text('${d.day}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : BrandColors.ink)),
              SizedBox(
                height: 13,
                child: count > 0
                    ? Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white
                              : BrandColors.brand600,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text('$count',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: selected
                                    ? BrandColors.brand700
                                    : Colors.white)),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── الـ Timeline ──
  List<Widget> _timeline(List<JMap> active, List<JMap> debts,
      String centerName, String currency, String today) {
    final out = <Widget>[];
    final isToday = selectedDay == today;
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    var nowInserted = !isToday;

    for (final a in active) {
      final t = hhmmToMinutes(a['time']);
      if (!nowInserted && t != null && t > nowMin) {
        out.add(_nowLine(nowMin));
        nowInserted = true;
      }
      out.add(_timelineRow(a, debts, centerName, currency));
    }
    if (!nowInserted && isToday) out.add(_nowLine(nowMin));
    return out;
  }

  Widget _nowLine(int nowMin) {
    return Padding(
      key: const Key('appt-now-line'),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text('الآن ${to12h(minutesToHHMM(nowMin))}',
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xFFDC2626))),
        const SizedBox(width: 6),
        const Expanded(
            child: Divider(color: Color(0xFFDC2626), thickness: 1)),
      ]),
    );
  }

  Widget _timelineRow(
      JMap a, List<JMap> debts, String centerName, String currency) {
    final id = '${a['id']}';
    final time = '${a['time'] ?? ''}';
    final isRec = a['_src'] == 'rec';
    final isBreak = isBreakRow(a);

    final timeCol = SizedBox(
      width: 44,
      child: Column(children: [
        // م165 — FittedBox: «10:00 ص» بسطرٍ واحد في العمود الأنحف.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(time.isEmpty ? '—' : to12h(time),
              maxLines: 1,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isBreak
                      ? const Color(0xFFB45309)
                      : BrandColors.brand700)),
        ),
        Text('${apptDurationMin(a)} د',
            style: TextStyle(fontSize: 9.5, color: BrandColors.mut2)),
      ]),
    );

    if (isBreak) {
      // ── الاستراحة ☕ — لون كهرماني مميز، ليست مريضاً ──
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          timeCol,
          const SizedBox(width: 6),
          Expanded(
            child: Material(
              color: const Color(0xFFFEF3C7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFF59E0B), width: .8),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: Key('appt-row-$id'),
                onTap: () => _openBreakSheet(a),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  child: Row(children: [
                    const Text('☕', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${jsOr(a['name'], 'استراحة')} — ${apptDurationMin(a)} دقيقة',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF92400E)),
                      ),
                    ),
                    const Icon(Icons.edit_rounded,
                        size: 13, color: Color(0xFFB45309)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );
    }

    final status = normApptStatus(a['status']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        timeCol,
        const SizedBox(width: 6),
        Expanded(
          child: Material(
            color: BrandColors.surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: BrandColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: Key('appt-row-$id'),
              onTap: isRec
                  ? () => _goPatient('${a['name'] ?? ''}')
                  : () => _openQuickActions(a, debts, centerName, currency),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${a['name'] ?? '—'}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: BrandColors.brand700)),
                        const SizedBox(height: 1),
                        Text(
                          '${jsOr(a['service'], '—')}'
                          '${isRec ? ' · من السجل' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: BrandColors.mut),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _statusPill(status),
                  if (!isRec) ...[
                    const SizedBox(width: 2),
                    IconButton(
                      key: Key('appt-done-$id'),
                      tooltip: 'إنهاء الزيارة',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 30, minHeight: 30),
                      onPressed: () => _finishVisit(id),
                      icon: const Icon(Icons.check_rounded,
                          size: 17, color: Color(0xFF22C55E)),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _statusPill(String status) {
    final color = apptStatusColor(status);
    final prefix = switch (status) {
      'upcoming' => '⏱ ',
      'completed' => '✓ ',
      'cancelled' => '✕ ',
      'no_show' => '✕ ',
      _ => '',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: .3), width: .7),
      ),
      child: Text('$prefix${apptStatusLabel(status)}',
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
    );
  }

  // ── صف الأرشيف ──
  Widget _archivedRow(JMap a) {
    final id = '${a['id']}';
    final isBreak = isBreakRow(a);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.surface2.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BrandColors.line),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('${jsOr(a['name'], isBreak ? 'استراحة' : '—')}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: BrandColors.mut)),
            Text(
              '${jsTruthy(a['time']) ? '${to12h('${a['time']}')} · ' : ''}'
              '${jsOr(a['service'], '—')}',
              style: TextStyle(fontSize: 10.5, color: BrandColors.mut2),
            ),
          ]),
        ),
        _statusPill(normApptStatus(a['status'])),
        IconButton(
          key: Key('appt-undone-$id'),
          tooltip: 'تراجع — إعادة للجدول',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            _setStatus(id, 'upcoming');
            _snack('أُعيد الموعد للجدول الحالي');
          },
          icon: const Icon(Icons.replay_rounded,
              size: 16, color: Color(0xFFF59E0B)),
        ),
        IconButton(
          key: Key('appt-arch-del-$id'),
          tooltip: 'حذف',
          visualDensity: VisualDensity.compact,
          onPressed: () => _deleteAppt(a),
          icon: const Icon(Icons.delete_outline_rounded,
              size: 15, color: BrandColors.red),
        ),
      ]),
    );
  }

  // ═════════════════ ورقة الإجراءات السريعة ═════════════════

  void _openQuickActions(
      JMap a, List<JMap> debts, String centerName, String currency) {
    final id = '${a['id']}';
    final phone = cleanPhone(a['phone']);
    final debt =
        getPatientDebt(debts, '${a['name'] ?? ''}', phone: a['phone']);
    final status = normApptStatus(a['status']);
    final next = nextApptStatus(status);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrandColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── رأس: المريض + الحالة + العيادة ──
              Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${a['name'] ?? '—'}',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: BrandColors.brand900)),
                        const SizedBox(height: 2),
                        Text(
                          '${a['date']}'
                          '${jsTruthy(a['time']) ? ' · ${to12h('${a['time']}')}' : ''}'
                          ' · ${jsOr(a['service'], '—')}'
                          '${apptClinicOf(a).isNotEmpty ? '\n🏥 ${apptClinicOf(a)}' : ''}',
                          style: TextStyle(
                              fontSize: 11.5, color: BrandColors.mut),
                        ),
                      ]),
                ),
                _statusPill(status),
              ]),
              const SizedBox(height: 12),

              // ── تواصل ──
              if (phone.isNotEmpty)
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _chip('اتصال', const Color(0xFF15604A),
                      key: Key('appt-call-$id'),
                      onTap: () => _launch('tel:$phone')),
                  _chip('تذكير واتساب', const Color(0xFF25D366),
                      key: Key('appt-wa-$id'),
                      onTap: () => _launch(
                          'https://wa.me/$phone?text=${Uri.encodeComponent(waReminderText(a, centerName))}')),
                  _chip('SMS', BrandColors.goldDark,
                      key: Key('appt-sms-$id'),
                      onTap: () => _launch(
                          'sms:$phone?body=${Uri.encodeComponent(smsReminderText(a, centerName))}')),
                  if (debt > 0) ...[
                    _chip('دين $debt $currency', const Color(0xFFEF4444),
                        key: Key('appt-debtwa-$id'),
                        onTap: () => _launch(
                            'https://wa.me/$phone?text=${Uri.encodeComponent(debtWaText(a, debt, currency, centerName))}')),
                    _chip('SMS دين', const Color(0xFFEF4444),
                        key: Key('appt-debtsms-$id'),
                        onTap: () => _launch(
                            'sms:$phone?body=${Uri.encodeComponent(debtSmsText(a, debt, currency, centerName))}')),
                  ],
                ]),
              if (phone.isNotEmpty) const SizedBox(height: 10),

              // ── دورة الحياة ──
              if (next != null)
                _sheetAction(
                  key: Key('appt-next-$id'),
                  icon: Icons.fast_forward_rounded,
                  color: apptStatusColor(next),
                  label: 'الحالة التالية: ${apptStatusLabel(next)}',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _setStatus(id, next);
                    if (next == 'completed') {
                      _snack('تم إنهاء الزيارة — انتقل الموعد لأرشيف اليوم');
                    }
                  },
                ),
              _sheetAction(
                key: Key('appt-finish-$id'),
                icon: Icons.task_alt_rounded,
                color: const Color(0xFF15803D),
                label: 'إنهاء الزيارة (أرشيف اليوم)',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _finishVisit(id);
                },
              ),
              Row(children: [
                Expanded(
                  child: _sheetAction(
                    key: Key('appt-cancel-appt-$id'),
                    icon: Icons.cancel_outlined,
                    color: const Color(0xFFB91C1C),
                    label: 'إلغاء',
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _setStatus(id, 'cancelled');
                      _snack('أُلغي الموعد — انتقل لأرشيف اليوم');
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _sheetAction(
                    key: Key('appt-noshow-$id'),
                    icon: Icons.person_off_outlined,
                    color: const Color(0xFF9F1239),
                    label: 'لم يحضر',
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _setStatus(id, 'no_show');
                      _snack('سُجّل «لم يحضر» — انتقل لأرشيف اليوم');
                    },
                  ),
                ),
              ]),
              const Divider(height: 18),

              // ── إدارة ──
              Row(children: [
                Expanded(
                  child: _sheetAction(
                    key: Key('appt-edit-$id'),
                    icon: Icons.edit_rounded,
                    color: BrandColors.brand700,
                    label: 'تعديل',
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _openWizard(edit: a);
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _sheetAction(
                    key: Key('appt-copy-$id'),
                    icon: Icons.copy_rounded,
                    color: BrandColors.brand700,
                    label: 'نسخ الموعد',
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _openWizard(preset: {
                        'name': a['name'],
                        'phone': a['phone'],
                        'service': a['service'],
                        'notes': a['notes'],
                        'clinic': apptClinicOf(a),
                        'durationMin': a['durationMin'],
                      });
                    },
                  ),
                ),
              ]),
              _sheetAction(
                key: Key('appt-patient-$id'),
                icon: Icons.folder_shared_rounded,
                color: BrandColors.goldDark,
                label: 'فتح سجل المريض',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _goPatient('${a['name'] ?? ''}');
                },
              ),
              _sheetAction(
                key: Key('appt-del-$id'),
                icon: Icons.delete_outline_rounded,
                color: BrandColors.red,
                label: 'حذف الموعد',
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  await _deleteAppt(a);
                },
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _sheetAction({
    required Key key,
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: color.withValues(alpha: .06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: color.withValues(alpha: .22), width: .8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color,
      {required Key key, required VoidCallback onTap}) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .3)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }

  // ═════════════════ ورقة الاستراحة (تعديل/حذف) ═════════════════

  void _openBreakSheet(JMap a) {
    _openWizard(edit: a, breakMode: true);
  }

  // ═════════════════ معالج الإضافة/التعديل ═════════════════

  /// ورقة سفلية واحدة: العيادة ← التاريخ ← الوقت ← المريض ← الخدمة —
  /// أو وضع الاستراحة ☕ (اسم اختياري + مدة). [edit] صفٌّ قائم للتعديل،
  /// [preset] تعبئة مسبقة (متابعة/نسخ)، [followUp] وضع موعد المتابعة.
  void _openWizard({
    JMap? edit,
    JMap? preset,
    bool followUp = false,
    bool breakMode = false,
  }) {
    final cfg = ref.read(appConfigProvider);
    final clinics = clinicsOf(cfg);
    final src = edit ?? preset ?? const <String, Object?>{};
    final isBreak = breakMode || (edit != null && isBreakRow(edit));

    var wClinic = '${src['clinic'] ?? ''}';
    if (wClinic.isEmpty) wClinic = _clinic;
    var wDate = '${src['date'] ?? ''}';
    if (wDate.isEmpty) wDate = selectedDay;
    var wTime = '${src['time'] ?? ''}';
    final nameCtl =
        TextEditingController(text: '${src['name'] ?? ''}');
    final phoneCtl =
        TextEditingController(text: '${src['phone'] ?? ''}');
    final serviceCtl =
        TextEditingController(text: '${src['service'] ?? ''}');
    final notesCtl =
        TextEditingController(text: '${src['notes'] ?? ''}');
    final dur = jsNumOr0(src['durationMin']).toInt();
    final durationCtl =
        TextEditingController(text: dur > 0 ? '$dur' : (isBreak ? '30' : ''));
    // م167/ب — اقتراحات صفّية (اسم + هاتف) بنمط «زيارة جديدة».
    var suggestions = <JMap>[];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrandColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetCtx) {
        // م164 — نفس نمط م163 الناعم لحقول الإدخال (اتساق كامل).
        final inputTheme = Theme.of(sheetCtx).copyWith(
          inputDecorationTheme: InputDecorationTheme(
            isDense: true,
            filled: true,
            fillColor: BrandColors.ink.withValues(alpha: .045),
            hintStyle: TextStyle(fontSize: 12, color: BrandColors.mut2),
            labelStyle: TextStyle(fontSize: 12, color: BrandColors.mut),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: BrandColors.line, width: .7)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: BrandColors.brand600, width: 1.3)),
          ),
        );
        return StatefulBuilder(builder: (sheetCtx, setSheet) {
          final repos = ref.read(reposProvider);
          final records = repos.records.getAll();
          final prosthetics = repos.prosthetics.getAll();
          final debts = repos.debts.getAll();
          final appointments = repos.appointments.getAll();

          // م167/ب — اقتراحات مرضى العيادة المختارة فقط (قرار المالك):
          // عند تعدد العيادات واختيار عيادةٍ تُفلتر المصادر الثلاثة بها؛
          // عيادة واحدة ⇒ كل المرضى (توافق خلفي مع الصفوف القديمة).
          List<JMap> clinicSuggest(String q) {
            final qt = q.trim();
            if (qt.length < 2) return const [];
            final strict = clinics.length > 1 &&
                wClinic.isNotEmpty &&
                wClinic != kNoClinic;
            bool inClinic(JMap r) =>
                !strict ||
                '${jsOr(r['clinic'], jsOr(r['clinic_id'], ''))}' == wClinic;
            final seen = <String>{};
            final out = <JMap>[];
            for (final r in [...records, ...prosthetics, ...appointments]) {
              final nm = '${r['name'] ?? ''}';
              if (nm.isEmpty || !inClinic(r) || !fuzzyMatch(qt, nm)) {
                continue;
              }
              if (!seen.add(nm)) continue;
              out.add({'name': nm, 'phone': '${r['phone'] ?? ''}'});
              if (out.length >= 5) break;
            }
            return out;
          }

          // صفوف يوم/عيادة الهدف — لتعطيل الأوقات المشغولة في الشبكة.
          // بعيادة واحدة لا فلترة (القديم بلا عيادة يحجب وقته أيضاً).
          final targetDay = filterByClinic(
            [
              for (final x in appointments)
                if ('${x['date']}' == wDate) x,
            ],
            clinics.length <= 1 ? '' : wClinic,
          );
          final slotMin = () {
            final n = jsNumOr0(durationCtl.text).toInt();
            return n > 0 ? n : 30;
          }();

          void save() {
            final name = nameCtl.text.trim();
            if (clinicRequired(cfg) && wClinic.isEmpty) {
              _snack('⚠ اختر العيادة أولاً — لا حجز بدون عيادة');
              return;
            }
            if (!isBreak && name.isEmpty) {
              _snack('⚠ أدخل اسم المريض');
              return;
            }
            if (wDate.isEmpty) {
              _snack('⚠ أدخل التاريخ');
              return;
            }
            if (isBreak && wTime.isEmpty) {
              _snack('⚠ حدد وقت الاستراحة');
              return;
            }

            // كشف التعارض — الاستراحة منعٌ قاطع والموعد تحذيرٌ قابل للتجاوز.
            Future<bool> conflictOk() async {
              if (wTime.isEmpty) return true;
              final exceptId = edit == null ? null : '${edit['id']}';
              // أولاً: أي استراحةٍ متداخلة ⇒ منعٌ قاطع (تُفحص كلها لا
              // أولها — موعدٌ متداخلٌ قبلها لا يحجبها عن الفحص).
              if (!isBreak) {
                final bHit = overlappingRow(
                    [for (final x in targetDay) if (isBreakRow(x)) x],
                    wTime,
                    slotMin,
                    exceptId: exceptId);
                if (bHit != null) {
                  _snack('⛔ لا يمكن الحجز فوق استراحة '
                      '(${jsOr(bHit['name'], 'استراحة')} ${to12h('${bHit['time']}')})');
                  return false;
                }
              }
              final hit = overlappingRow(targetDay, wTime, slotMin,
                  exceptId: exceptId);
              if (hit == null) return true;
              if (isBreakRow(hit)) {
                _snack('⛔ لا يمكن الحجز فوق استراحة '
                    '(${jsOr(hit['name'], 'استراحة')} ${to12h('${hit['time']}')})');
                return false;
              }
              final go = await showDialog<bool>(
                context: sheetCtx,
                builder: (dCtx) => AlertDialog(
                  title: const Text('تعارض بالوقت',
                      style: TextStyle(fontSize: 14)),
                  content: Text(
                    'يتداخل هذا الوقت مع موعد «${hit['name']}» '
                    '(${to12h('${hit['time']}')} · ${apptDurationMin(hit)} د).\n'
                    'حفظ رغم التعارض؟',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  actions: [
                    TextButton(
                      key: const Key('appt-conflict-cancel'),
                      onPressed: () => Navigator.pop(dCtx, false),
                      child: const Text('تغيير الوقت'),
                    ),
                    FilledButton(
                      key: const Key('appt-conflict-save'),
                      onPressed: () => Navigator.pop(dCtx, true),
                      child: const Text('حفظ رغم التعارض'),
                    ),
                  ],
                ),
              );
              return go == true;
            }

            conflictOk().then((ok) {
              if (!ok) return;
              final durTxt = durationCtl.text.trim();
              final durMin = durTxt.isEmpty ? 0 : jsNumOr0(durTxt).toInt();
              if (edit != null) {
                final prev = repos.appointments.getById('${edit['id']}');
                if (prev != null) {
                  final patientId = jsTruthy(prev['patient_id'])
                      ? prev['patient_id']
                      : (patientKeyFor(name: name, phone: phoneCtl.text) ??
                          '');
                  repos.appointments.upsertLocal({
                    ...prev,
                    'name': isBreak
                        ? (name.isEmpty ? 'استراحة' : name)
                        : name,
                    'phone': phoneCtl.text,
                    'date': wDate,
                    'time': wTime,
                    'service': isBreak ? '' : serviceCtl.text,
                    'notes': notesCtl.text,
                    'clinic': wClinic == kNoClinic ? '' : wClinic,
                    'clinic_id': wClinic == kNoClinic
                        ? ''
                        : clinicKeyFor(wClinic),
                    'patient_id': isBreak ? '' : patientId,
                    if (durMin > 0) 'durationMin': durMin,
                    '_mod': jsNow(),
                  });
                }
                _snack(isBreak ? 'تم تعديل الاستراحة' : 'تم تعديل الموعد');
              } else {
                final auth = ref.read(authProvider);
                repos.appointments.upsertLocal({
                  'id': genId(),
                  'uid': auth is SignedIn ? auth.user.uid : '',
                  'name':
                      isBreak ? (name.isEmpty ? 'استراحة' : name) : name,
                  'phone': isBreak ? '' : phoneCtl.text,
                  'date': wDate,
                  'time': wTime,
                  'service': isBreak ? '' : serviceCtl.text,
                  'notes': notesCtl.text,
                  // التوافق الخلفي: 'pending' تُقرأ «قادم» في الكتالوج.
                  'status': 'pending',
                  if (isBreak) 'isBreak': 1,
                  'patient_id': isBreak
                      ? ''
                      : (patientKeyFor(name: name, phone: phoneCtl.text) ??
                          ''),
                  'clinic': wClinic == kNoClinic ? '' : wClinic,
                  'clinic_id': wClinic == kNoClinic
                      ? ''
                      : clinicKeyFor(wClinic),
                  if (durMin > 0) 'durationMin': durMin,
                  '_mod': jsNow(),
                  '_t': 'a',
                });
                _snack(isBreak
                    ? 'تمت إضافة الاستراحة ☕'
                    : (followUp ? 'تم حفظ موعد المتابعة' : 'تم إضافة الموعد'));
              }
              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
              // الهبوط مباشرة على العيادة + التاريخ المحفوظين.
              if (wClinic.isNotEmpty && wClinic != kNoClinic) {
                ref.read(apptClinicProvider.notifier).state = wClinic;
              }
              setState(() => selectedDay = wDate);
              _bump();
              ref.read(patientsRevProvider.notifier).state++;
              // العودة التلقائية لتبويب الإضافة بعد موعد المتابعة.
              if (followUp && cfg['followUpAuto'] != false) {
                ref.read(activeTabProvider.notifier).state = 'home';
              }
            });
          }

          final slots = buildTimeSlots(cfg);
          return Theme(
              data: inputTheme,
              child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBreak
                          ? (edit != null ? 'تعديل الاستراحة ☕' : 'استراحة جديدة ☕')
                          : edit != null
                              ? 'تعديل الموعد'
                              : (followUp ? 'موعد متابعة' : 'موعد جديد'),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.brand900),
                    ),
                    const SizedBox(height: 10),

                    // ── 1) العيادة — إلزامية عند التعدد ──
                    _wizH('العيادة *'),
                    if (clinics.length <= 1)
                      Text(
                        clinics.isEmpty ? '—' : clinics.first,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.brand700),
                      )
                    else
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final c in clinics)
                          InkWell(
                            key: Key('appt-w-clinic-$c'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setSheet(() => wClinic = c),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 6),
                              decoration: BoxDecoration(
                                color: wClinic == c
                                    ? BrandColors.brand600
                                    : BrandColors.brand600
                                        .withValues(alpha: .07),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: wClinic == c
                                        ? BrandColors.brand600
                                        : BrandColors.brand600
                                            .withValues(alpha: .25)),
                              ),
                              child: Text(c,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: wClinic == c
                                          ? Colors.white
                                          : BrandColors.brand700)),
                            ),
                          ),
                      ]),
                    const SizedBox(height: 10),

                    // ── 2) التاريخ ──
                    _wizH('التاريخ *'),
                    OutlinedButton.icon(
                      key: const Key('appt-date'),
                      style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      onPressed: () async {
                        final init = wDate.isNotEmpty
                            ? DateTime.tryParse(wDate) ?? DateTime.now()
                            : DateTime.now();
                        final picked = await showDatePicker(
                          context: sheetCtx,
                          initialDate: init,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setSheet(() => wDate = _ymd(picked));
                        }
                      },
                      icon: const Icon(Icons.event_rounded, size: 14),
                      label: Text(
                          wDate.isEmpty
                              ? 'اختر التاريخ'
                              : '$wDate (${dayLabel(wDate)})',
                          style: const TextStyle(fontSize: 11.5)),
                    ),
                    const SizedBox(height: 10),

                    // ── 3) الوقت — شبكة أوقات الدوام ──
                    _wizH(isBreak ? 'وقت الاستراحة *' : 'الوقت'),
                    Wrap(spacing: 5, runSpacing: 5, children: [
                      if (!isBreak)
                        _slotChip(
                          key: const Key('appt-time-none'),
                          label: 'بلا وقت',
                          selected: wTime.isEmpty,
                          disabled: false,
                          onTap: () => setSheet(() => wTime = ''),
                        ),
                      for (final s in slots)
                        Builder(builder: (_) {
                          final hit = overlappingRow(
                              targetDay, s, slotMin,
                              exceptId:
                                  edit == null ? null : '${edit['id']}');
                          final blocked =
                              hit != null && isBreakRow(hit);
                          final busy = hit != null && !isBreakRow(hit);
                          return _slotChip(
                            key: Key('appt-slot-$s'),
                            label:
                                '${to12h(s)}${blocked ? ' ☕' : busy ? ' •' : ''}',
                            selected: wTime == s,
                            disabled: blocked,
                            busy: busy,
                            onTap: () => setSheet(() => wTime = s),
                          );
                        }),
                    ]),
                    // إدخال وقتٍ دقيق (منتقي الساعة) — نفس مفتاح الأصل.
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const Key('appt-time'),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: sheetCtx,
                            initialTime: TimeOfDay.now(),
                          );
                          if (picked != null) {
                            setSheet(() => wTime =
                                '${picked.hour.toString().padLeft(2, '0')}:'
                                '${picked.minute.toString().padLeft(2, '0')}');
                          }
                        },
                        icon: const Icon(Icons.schedule_rounded, size: 13),
                        label: Text(
                            wTime.isEmpty
                                ? 'وقت مخصص…'
                                : 'الوقت: ${to12h(wTime)}',
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ── 4) المريض / اسم الاستراحة ──
                    if (isBreak) ...[
                      _wizH('اسم الاستراحة (اختياري)'),
                      TextField(
                        key: const Key('appt-break-name'),
                        controller: nameCtl,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'استراحة، غداء، اجتماع، وقت شخصي…'),
                      ),
                    ] else ...[
                      _wizH('المريض *'),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            key: const Key('appt-name'),
                            controller: nameCtl,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                                isDense: true, labelText: 'اسم المريض *'),
                            onChanged: (v) => setSheet(() {
                              suggestions = clinicSuggest(v);
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            key: const Key('appt-phone'),
                            controller: phoneCtl,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                                isDense: true, labelText: 'رقم الهاتف'),
                          ),
                        ),
                      ]),
                      if (suggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: BrandColors.gold.withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: BrandColors.gold
                                    .withValues(alpha: .25)),
                          ),
                          child: Column(children: [
                            for (final sg in suggestions)
                              InkWell(
                                key: Key('appt-suggest-${sg['name']}'),
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => setSheet(() {
                                  final s = '${sg['name']}';
                                  nameCtl.text = s;
                                  // م167/ب — الاختيار يغلق اللوحة فوراً
                                  // (مصدر اقتراح واحد نشط).
                                  suggestions = [];
                                  var phone = '${sg['phone'] ?? ''}';
                                  if (phone.isEmpty) {
                                    phone = phoneForName(s,
                                        records: records,
                                        prosthetics: prosthetics,
                                        debts: debts,
                                        appointments: appointments);
                                  }
                                  if (phone.isNotEmpty) {
                                    phoneCtl.text = phone;
                                  }
                                  // تعبئة الخدمة من آخر سجل للمريض.
                                  if (serviceCtl.text.trim().isEmpty) {
                                    final recs = [
                                      for (final r in records)
                                        if (r['name'] == s &&
                                            jsTruthy(r['service']))
                                          r,
                                    ]..sort((a, b) =>
                                        '${b['date'] ?? ''}'.compareTo(
                                            '${a['date'] ?? ''}'));
                                    if (recs.isNotEmpty) {
                                      serviceCtl.text =
                                          '${recs.first['service']}';
                                    }
                                  }
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  child: Row(children: [
                                    Expanded(
                                      child: Text('${sg['name']}',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                    if ('${sg['phone'] ?? ''}'.isNotEmpty)
                                      Text('${sg['phone']}',
                                          textDirection: TextDirection.ltr,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: BrandColors.mut2)),
                                  ]),
                                ),
                              ),
                          ]),
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('appt-service'),
                        controller: serviceCtl,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'الخدمة / سبب الزيارة',
                            hintText: 'مثال: كشف، تنظيف، حشو...'),
                      ),
                    ],
                    const SizedBox(height: 8),

                    // ── 5) المدة + ملاحظات ──
                    TextField(
                      key: const Key('appt-duration'),
                      controller: durationCtl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                          isDense: true,
                          labelText: 'المدة (دقائق)',
                          hintText: 'افتراضي 30'),
                      onChanged: (_) => setSheet(() {}),
                    ),
                    if (!isBreak) ...[
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('appt-notes'),
                        controller: notesCtl,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'ملاحظات',
                            hintText: 'ملاحظات إضافية...'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: FilledButton(
                          key: const Key('appt-save'),
                          style: FilledButton.styleFrom(
                              backgroundColor: BrandColors.gold,
                              foregroundColor: BrandColors.brand900),
                          onPressed: save,
                          child: Text(
                              edit != null
                                  ? 'تحديث'
                                  : isBreak
                                      ? 'إضافة الاستراحة'
                                      : 'حفظ الموعد',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (edit != null && isBreak)
                        OutlinedButton(
                          key: Key('appt-break-del-${edit['id']}'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: BrandColors.red),
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            _deleteAppt(edit);
                          },
                          child: const Text('حذف',
                              style: TextStyle(fontSize: 12)),
                        ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        key: const Key('appt-cancel'),
                        onPressed: () => Navigator.pop(sheetCtx),
                        child: const Text('إلغاء',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ));
        });
      },
    ).whenComplete(() {
      // تحرير المتحكمات بعد إغلاق الورقة بإطار (لا استخدام بعد التحرير).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtl.dispose();
        phoneCtl.dispose();
        serviceCtl.dispose();
        notesCtl.dispose();
        durationCtl.dispose();
      });
    });
  }

  Widget _wizH(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: BrandColors.mut)),
      );

  Widget _slotChip({
    required Key key,
    required String label,
    required bool selected,
    required bool disabled,
    bool busy = false,
    required VoidCallback onTap,
  }) {
    final color = disabled
        ? const Color(0xFFB45309)
        : busy
            ? BrandColors.mut2
            : BrandColors.brand700;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(9),
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? BrandColors.brand600
              : disabled
                  ? const Color(0xFFFEF3C7)
                  : busy
                      ? BrandColors.line.withValues(alpha: .4)
                      : BrandColors.surface2,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: selected
                  ? BrandColors.brand600
                  : disabled
                      ? const Color(0xFFF59E0B)
                      : BrandColors.line,
              width: .8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                decoration: busy && !selected
                    ? TextDecoration.lineThrough
                    : null,
                color: selected ? Colors.white : color)),
      ),
    );
  }
}
