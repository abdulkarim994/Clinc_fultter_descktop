/// ============================================================================
///  المواعيد — نسخة سطح المكتب: Split Layout (قائمة يمين / تفاصيل يسار)
/// ============================================================================
///
///  (قرار المالك): «المواعيد: تطبيق Split Layout. يمين: قائمة المواعيد.
///  يسار: تفاصيل الموعد. يدعم: موعد دوري، موعد عادي.»
///
///  - المنطق والبيانات من appointments_logic.dart والمستودع نفسه بلا أي
///    تعديل — إضافة/تعديل/إلغاء/حذف الموعد توائم حرفية لمسارات الهاتف في
///    appointments_tab.dart (نفس دوال المستودع والمفاتيح وتوليد id
///    والنبضات apptRevProvider/patientsRevProvider).
///  - «الموعد الدوري» ميزة **إضافية غير كاسرة**: حقول إضافية على صف الموعد
///    (repeat / repeatGroup / repeatIndex / repeatCount) تُخزَّن في كتلة
///    `data` عبر prepareForStorage وتعود عبر parseRowData — تتجاهلها نسخة
///    الهاتف بأمان تام. كل موعد مولّد هو موعد عادي 100% بنفس مسار الإضافة.
///  - القسم الأيمن: شريط أدوات (بحث فوري + فلتر حالة + تنقّل نطاق) وقائمة
///    مجمّعة بالتاريخ (الأقرب أولاً). القسم الأيسر: تفاصيل الموعد المختار
///    + قسم السلسلة للموعد الدوري. النموذج يفتح في showDesktopDialog.
///  - مفتاح DesktopSplitView: 'appointments'.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/js_compat.dart';
import '../../../core/utils/uid.dart';
import '../../../core/widgets/double_confirm.dart' show confirmDelete;
import '../../../data/repositories/patients_repository.dart'
    show patientKeyFor, clinicKeyFor;
import '../../appointments/appointments_logic.dart';
import '../../appointments/appt_lifecycle.dart'
    show
        apptStatusColor,
        apptStatusLabel,
        archivedIdsToPurge,
        clinicRequired,
        clinicsOf,
        filterByClinic,
        hasUnassignedClinic,
        kNoClinic,
        normApptStatus;
import '../../appointments/appointments_tab.dart'
    show apptRevProvider;
import '../../patients/patients_tab.dart' show patientsRevProvider;
import '../desktop_prefs.dart'
    show desktopPrefsProvider, saveDesktopPref;
import '../widgets/desktop_dialogs.dart' show showDesktopDialog;
import '../widgets/split_view.dart' show DesktopSplitView, DetailHost;
import 'appointments_week_view.dart' show WeeklyScheduler, ApptActions;

/// ملصقات أنماط التكرار (المعتمدة في الخطة).
const _repeatLabels = <String, String>{
  'weekly': 'أسبوعي',
  'biweekly': 'كل أسبوعين',
  'monthly': 'شهري',
};

/// مفتاح تفضيل العرض المحلي (الجدولة الأسبوعية مقابل القائمة). محفوظ عبر
/// [saveDesktopPref] في قناة تفضيلات سطح المكتب المحلية — شكل الشاشة خاصية
/// الجهاز نفسه فلا يُزامَن. الافتراضي 'week' (الجدولة المكتبية).
const _kViewKey = 'appt.view';

/// م164 — مفتاح تفضيل تبويب العيادة المختار (محلي للجهاز مثل العرض).
const _kClinicKey = 'appt.clinic';

/// وضع العرض: الجدولة الأسبوعية المكتبية أو قائمة master/detail.
enum _ApptView { week, list }

/// فلاتر الحالة في شريط الأدوات.
enum _StatusFilter { upcoming, today, cancelled, all }

/// نطاق التاريخ السريع (توأم منطق «القادمة» في الهاتف — كلّها من اليوم
/// فصاعداً؛ يضاف تضييق اليوم/الغد/الأسبوع بصرياً).
enum _RangeFilter { day, tomorrow, week, all }

class DesktopAppointmentsScreen extends ConsumerStatefulWidget {
  const DesktopAppointmentsScreen({super.key});

  @override
  ConsumerState<DesktopAppointmentsScreen> createState() =>
      _DesktopAppointmentsScreenState();
}

class _DesktopAppointmentsScreenState
    extends ConsumerState<DesktopAppointmentsScreen> {
  /// معرّف الموعد المختار (id الصف الحقيقي في المستودع).
  String? _selectedId;

  _StatusFilter _statusFilter = _StatusFilter.upcoming;
  _RangeFilter _rangeFilter = _RangeFilter.all;
  final _searchCtl = TextEditingController();

  /// م164 — تبويب العيادة المختار ('' = الكل، kNoClinic = غير المحددة).
  String get _clinicFilter =>
      '${ref.read(desktopPrefsProvider)[_kClinicKey] ?? ''}';

  @override
  void initState() {
    super.initState();
    // م164 — تنظيف أرشيف المواعيد (المؤرشف الأقدم من يومين) عند الفتح —
    // توأم التنظيف في نسخة الهاتف ونمط purgeOldDays في الدور.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final repos = ref.read(reposProvider);
      final ids = archivedIdsToPurge(
          repos.appointments.getAll(), getCurrentDate());
      for (final id in ids) {
        repos.appointments.delete(id);
      }
      if (ids.isNotEmpty) _bump();
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(msg),
            duration: const Duration(milliseconds: 1500)),
      );

  /// نبضة إعادة القراءة بعد كل كتابة — توأم _bump في تبويب الهاتف
  /// (apptRevProvider) مع نبضة المرضى (patientsRevProvider) كما يفعل
  /// saveAppt حرفياً.
  void _bump() {
    ref.read(apptRevProvider.notifier).state++;
    ref.read(patientsRevProvider.notifier).state++;
    setState(() {});
  }

  Future<void> _launch(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  // ── الجلب (نفس مسار الهاتف: getAll على المستودعات الثلاثة) ──

  /// كل مواعيد المستودع الحقيقية (المصدر 'appt' فقط — لا صفوف السجلات/
  /// التركيبات المقروءة). تُستعمل لاستعلام السلسلة والقوائم القابلة للتحرير.
  List<JMap> _realAppts() {
    final appts = ref.watch(reposProvider).appointments.getAll();
    return [for (final a in appts) {...a}];
  }

  /// خريطة المواعيد الكاملة (توأم build في الهاتف) — لعرض القائمة اليمنى:
  /// تدمج مصادر القراءة الثلاثة عبر buildApptMap حرفياً.
  Map<String, List<JMap>> _apptMap() {
    final repos = ref.watch(reposProvider);
    return buildApptMap(
      appointments: repos.appointments.getAll(),
      records: repos.records.getAll(),
      prosthetics: repos.prosthetics.getAll(),
    );
  }

  /// صفوف سلسلة موعد دوري (بالاستعلام على repeatGroup من نفس getAll)،
  /// مرتّبة بترتيب السلسلة ثم بالتاريخ.
  List<JMap> _seriesRows(String group) {
    final list = [
      for (final a in _realAppts())
        if ('${a['repeatGroup'] ?? ''}' == group && group.isNotEmpty) a,
    ]..sort((a, b) {
        final ia = jsNumOr0(a['repeatIndex']);
        final ib = jsNumOr0(b['repeatIndex']);
        if (ia != ib) return ia.compareTo(ib);
        return '${a['date'] ?? ''}'.compareTo('${b['date'] ?? ''}');
      });
    return list;
  }

  /// الموعد المختار من صفوف المستودع الحقيقية (أو null إن حُذف/أُلغي مصدره).
  JMap? _selectedRow() {
    final id = _selectedId;
    if (id == null) return null;
    for (final a in _realAppts()) {
      if ('${a['id']}' == id) return a;
    }
    return null;
  }

  // ── تصفية وترتيب القائمة اليمنى ──

  /// المواعيد المعروضة بعد تطبيق الفلاتر — مجمّعة لاحقاً بالتاريخ.
  /// نعتمد المصدر الكامل (appt + rec) لإظهار كل الحجوزات كما القائمة
  /// «القادمة» في الهاتف؛ التحرير متاح فقط لصفوف المستودع الحقيقية.
  List<JMap> _filteredAppts() {
    final map = _apptMap();
    // م164 — تبويب العيادة يفلتر القائمة قبل بقية الفلاتر.
    final all = filterByClinic(
        <JMap>[for (final l in map.values) ...l], _clinicFilter);
    final today = getCurrentDate();
    final q = _searchCtl.text.trim();

    bool matchesStatus(JMap a) {
      final st = '${a['status'] ?? 'pending'}';
      switch (_statusFilter) {
        case _StatusFilter.cancelled:
          return st == 'cancelled';
        case _StatusFilter.today:
          return '${a['date']}' == today && st != 'cancelled';
        case _StatusFilter.upcoming:
          // القادمة: من اليوم فصاعداً وغير ملغاة ولا مكتملة (توأم upcoming).
          return '${a['date']}'.compareTo(today) >= 0 &&
              st != 'cancelled' &&
              st != 'completed';
        case _StatusFilter.all:
          return true;
      }
    }

    bool matchesRange(JMap a) {
      if (_statusFilter == _StatusFilter.cancelled ||
          _statusFilter == _StatusFilter.all) {
        return true; // النطاق لا يقيّد قوائم الملغاة/الكل.
      }
      final d = '${a['date']}';
      switch (_rangeFilter) {
        case _RangeFilter.day:
          return d == today;
        case _RangeFilter.tomorrow:
          return d == _tomorrow();
        case _RangeFilter.week:
          return d.compareTo(today) >= 0 &&
              d.compareTo(_inDays(7)) <= 0;
        case _RangeFilter.all:
          return true;
      }
    }

    bool matchesQuery(JMap a) {
      if (q.isEmpty) return true;
      final name = '${a['name'] ?? ''}';
      final phone = '${a['phone'] ?? ''}';
      return name.contains(q) || phone.contains(q);
    }

    final list = [
      for (final a in all)
        if ('${a['date'] ?? ''}'.isNotEmpty &&
            matchesStatus(a) &&
            matchesRange(a) &&
            matchesQuery(a))
          a,
    ];
    // الأقرب أولاً: ترتيب تصاعدي بالتاريخ ثم بالوقت.
    list.sort((a, b) {
      final byDate = '${a['date']}'.compareTo('${b['date']}');
      if (byDate != 0) return byDate;
      return '${a['time'] ?? ''}'.compareTo('${b['time'] ?? ''}');
    });
    return list;
  }

  /// تجميع المواعيد بعناوين أقسام بالتاريخ (بترتيب الأقرب أولاً).
  List<(String, List<JMap>)> _grouped(List<JMap> appts) {
    final byDate = <String, List<JMap>>{};
    for (final a in appts) {
      (byDate['${a['date']}'] ??= []).add(a);
    }
    final keys = byDate.keys.toList()..sort();
    return [for (final k in keys) (k, byDate[k]!)];
  }

  String _tomorrow() => _inDays(1);

  String _inDays(int days) {
    final d = DateTime.now().add(Duration(days: days));
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  // ══════════════════════════════════════════════════════════════════
  //  الكتابة — توائم حرفية لمسارات الهاتف (appointments_tab.dart)
  // ══════════════════════════════════════════════════════════════════

  /// إضافة موعد واحد (توأم فرع الإضافة في saveAppt حرفياً) مع حقول
  /// التكرار الإضافية الاختيارية. [extra] يحمل حقول الدورية أو يكون فارغاً.
  void _addOne({
    required String name,
    required String phone,
    required String date,
    required String time,
    required String service,
    required String notes,
    String clinic = '',
    int? durationMin,
    Map<String, Object?> extra = const {},
  }) {
    final repos = ref.read(reposProvider);
    final auth = ref.read(authProvider);
    repos.appointments.upsertLocal({
      'id': genId(),
      'uid': auth is SignedIn ? auth.user.uid : '',
      'name': name,
      'phone': phone,
      'date': date,
      'time': time,
      'service': service,
      'notes': notes,
      'status': 'pending',
      'patient_id': patientKeyFor(name: name, phone: phone) ?? '',
      // م164 — العيادة جزء أساسي من كل صف موعد.
      'clinic': clinic,
      'clinic_id': clinic.isEmpty ? '' : clinicKeyFor(clinic),
      // م: durationMin حقل مرن في كتلة data (لا عمود) — يُكتب فقط عند
      // تحديده صراحةً؛ الغياب يعني الافتراضي 30 عند العرض/القراءة.
      if (durationMin != null && durationMin > 0) 'durationMin': durationMin,
      '_mod': jsNow(),
      '_t': 'a',
      ...extra,
    });
  }

  /// تقديم التاريخ حسب النمط: أسبوع/أسبوعان/شهر تقويمي — توليد سلسلة الدوري.
  String _advance(String date, String repeat, int step) {
    final base = DateTime.tryParse(date) ?? DateTime.now();
    late DateTime next;
    switch (repeat) {
      case 'weekly':
        next = base.add(Duration(days: 7 * step));
      case 'biweekly':
        next = base.add(Duration(days: 14 * step));
      case 'monthly':
      default:
        // شهر تقويمي: نفس اليوم من الشهر بعد step أشهر (مع تصحيح آخر الشهر).
        final y = base.year + ((base.month - 1 + step) ~/ 12);
        final m = ((base.month - 1 + step) % 12) + 1;
        final lastDay = DateTime(y, m + 1, 0).day;
        final day = base.day <= lastDay ? base.day : lastDay;
        next = DateTime(y, m, day);
    }
    return '${next.year.toString().padLeft(4, '0')}-'
        '${next.month.toString().padLeft(2, '0')}-'
        '${next.day.toString().padLeft(2, '0')}';
  }

  /// حفظ من النموذج: إنشاء عادي/دوري أو تعديل موعد واحد.
  void _save(_FormResult r) {
    final name = r.name.trim();
    if (name.isEmpty) {
      _snack('⚠ أدخل اسم المريض');
      return;
    }
    if (r.date.isEmpty) {
      _snack('⚠ أدخل التاريخ');
      return;
    }
    // م164 — العيادة إلزامية عند تعدد العيادات (لا افتراض بأول عيادة).
    if (clinicRequired(ref.read(appConfigProvider)) && r.clinic.isEmpty) {
      _snack('⚠ اختر العيادة أولاً — لا حجز بدون عيادة');
      return;
    }

    if (r.editingId != null) {
      // تعديل موعد واحد فقط (توأم فرع التعديل في saveAppt) — لا يمسّ
      // السلسلة، والحقول الإضافية للدورية تبقى عبر نشر ...prev.
      final repos = ref.read(reposProvider);
      final prev = repos.appointments.getById(r.editingId!);
      if (prev != null) {
        final patientId = jsTruthy(prev['patient_id'])
            ? prev['patient_id']
            : (patientKeyFor(name: name, phone: r.phone) ?? '');
        repos.appointments.upsertLocal({
          ...prev,
          'name': name,
          'phone': r.phone,
          'date': r.date,
          'time': r.time,
          'service': r.service,
          'notes': r.notes,
          // م164 — تعديل العيادة (يُستعمل أيضاً للتعيين السريع للقديم).
          'clinic': r.clinic,
          'clinic_id': r.clinic.isEmpty ? '' : clinicKeyFor(r.clinic),
          'patient_id': patientId,
          // م: المدة حقلٌ مرن — تُكتب عند تحديدها، وتبقى قيمة سابقة عبر
          // نشر ...prev إن تُركت فارغة.
          if (r.durationMin != null && r.durationMin! > 0)
            'durationMin': r.durationMin,
          '_mod': jsNow(),
        });
      }
      _snack('تم تعديل الموعد');
      _bump();
      return;
    }

    if (r.repeat == null) {
      // موعد عادي — إضافة واحدة.
      _addOne(
        name: name,
        phone: r.phone,
        date: r.date,
        time: r.time,
        service: r.service,
        notes: r.notes,
        clinic: r.clinic,
        durationMin: r.durationMin,
      );
      _snack('تم إضافة الموعد');
      _bump();
      return;
    }

    // موعد دوري — توليد N مواعيد فعلية فوراً بنفس مسار الإضافة، تحمل
    // معرّف سلسلة مشتركاً وترتيباً وطولاً. التواريخ متقدمة حسب النمط.
    final group = genId();
    final count = r.count.clamp(2, 24);
    for (var i = 0; i < count; i++) {
      _addOne(
        name: name,
        phone: r.phone,
        date: i == 0 ? r.date : _advance(r.date, r.repeat!, i),
        time: r.time,
        service: r.service,
        notes: r.notes,
        clinic: r.clinic,
        durationMin: r.durationMin,
        extra: {
          'repeat': r.repeat,
          'repeatGroup': group,
          'repeatIndex': i + 1,
          'repeatCount': count,
        },
      );
    }
    _snack('تم إنشاء $count مواعيد (${_repeatLabels[r.repeat]})');
    _bump();
  }

  /// إلغاء موعد واحد (توأم تحديث الحالة إلى cancelled عبر upsertLocal —
  /// نفس المسار الذي تعرفه نسخة الهاتف: الحالة cancelled تُعرض «✕ ملغي»).
  void _cancelOne(String id) {
    final repos = ref.read(reposProvider);
    final a = repos.appointments.getById(id);
    if (a == null) return;
    repos.appointments.upsertLocal({
      ...a,
      'status': 'cancelled',
      '_mod': jsNow(),
    });
    _snack('تم إلغاء الموعد');
    _bump();
  }

  /// إلغاء بقية السلسلة (تصميمنا الموثّق): تُلغى كل مواعيد المجموعة التي
  /// **لم تنقضِ** (تاريخها اليوم فصاعداً) وليست مكتملة ولا ملغاة سلفاً —
  /// عبر نفس مسار الإلغاء (status=cancelled). المواعيد المنقضية تبقى
  /// كما هي (سجلّ لا يُطمس)، والموعد المختار يُلغى ضمنها إن كان قادماً.
  void _cancelRestOfSeries(String group) {
    final repos = ref.read(reposProvider);
    final today = getCurrentDate();
    var n = 0;
    for (final a in _seriesRows(group)) {
      final st = '${a['status'] ?? 'pending'}';
      final future = '${a['date']}'.compareTo(today) >= 0;
      if (future && st != 'cancelled' && st != 'completed') {
        repos.appointments.upsertLocal({
          ...a,
          'status': 'cancelled',
          '_mod': jsNow(),
        });
        n++;
      }
    }
    _snack(n == 0 ? 'لا مواعيد قادمة لإلغائها' : 'أُلغيت $n مواعيد من السلسلة');
    _bump();
  }

  /// تحديد الاكتمال/التراجع (توأم _markDone في الهاتف حرفياً): الحالة
  /// completed عند التم، upcoming عند التراجع — عبر upsertLocal.
  void _markDone(String id, {bool done = true}) {
    final repos = ref.read(reposProvider);
    final a = repos.appointments.getById(id);
    if (a == null) return;
    repos.appointments.upsertLocal({
      ...a,
      'status': done ? 'completed' : 'upcoming',
      '_mod': jsNow(),
    });
    _snack(done ? 'تم تحديد الموعد كمكتمل' : 'تم إلغاء اكتمال الموعد');
    _bump();
  }

  /// نسخ موعد قائم إلى تاريخ/وقت جديدين (المكافئ المكتبي لـ«نسخ الموعد»
  /// في الهاتف). التصميم المعتمد (قيد مطلق #5):
  ///   • معرّف جديد genId() — صفٌّ مستقلّ تماماً.
  ///   • تُنسخ الحقول الميدانية فقط: name/phone/service/notes/patient_id/
  ///     clinic_id/uid + durationMin + date/time الجديدين.
  ///   • status:'pending' دائماً، بلا base (فلا دمج ثلاثي — إنشاء صريح).
  ///   • **لا تُنسخ** حقول التخزين/المزامنة (_hlc/_dirty/_origin/_mod/
  ///     created_at/updated_at/server_seq/_deleted/data) ولا حقول التكرار
  ///     (repeat*) — النسخة موعدٌ مفردٌ لا حلقةٌ في سلسلة.
  void _copyOne(JMap src, {required String date, required String time}) {
    final repos = ref.read(reposProvider);
    final auth = ref.read(authProvider);
    final durationMin = jsNumOr0(src['durationMin']).toInt();
    repos.appointments.upsertLocal({
      'id': genId(),
      'uid': auth is SignedIn ? auth.user.uid : '${src['uid'] ?? ''}',
      'name': '${src['name'] ?? ''}',
      'phone': '${src['phone'] ?? ''}',
      'date': date,
      'time': time,
      'service': '${src['service'] ?? ''}',
      'notes': '${src['notes'] ?? ''}',
      'status': 'pending',
      'patient_id': '${src['patient_id'] ?? ''}',
      'clinic': '${src['clinic'] ?? ''}',
      'clinic_id': '${src['clinic_id'] ?? ''}',
      if (durationMin > 0) 'durationMin': durationMin,
      '_mod': jsNow(),
      '_t': 'a',
    });
    _snack('تم نسخ الموعد');
    _bump();
  }

  /// نقل موعد إلى تاريخ/وقت جديدين (توأم السحب في الجدولة). تمرير [base]
  /// = الصف السابق يفعّل الدمج الثلاثي (قيد مطلق #4) فلا يمسح تعديل جهاز
  /// آخر وصل بين القراءة والحفظ — يحرسه m52_rows_two_device_test.
  void _moveOne(JMap prev, {required String date, required String time}) {
    final repos = ref.read(reposProvider);
    repos.appointments.upsertLocal(
      {...prev, 'date': date, 'time': time, '_mod': jsNow()},
      base: prev,
    );
    _bump();
  }

  /// ضبط مدة موعد (durationMin) — من سحب الحافة السفلية في الجدولة. حقلٌ
  /// مرنٌ في كتلة data (قيد مطلق #6)، عبر upsertLocal بدمجٍ ثلاثي.
  void _setDuration(JMap prev, int durationMin) {
    final repos = ref.read(reposProvider);
    repos.appointments.upsertLocal(
      {...prev, 'durationMin': durationMin, '_mod': jsNow()},
      base: prev,
    );
    _bump();
  }

  /// حذف موعد نهائياً (توأم _deleteAppt: confirmDelete نوع 'appt' ثم delete).
  Future<void> _deleteOne(JMap a) async {
    final ok = await confirmDelete(
      context,
      config: ref.read(appConfigProvider),
      type: 'appt',
      title: 'حذف الموعد نهائياً؟',
      msg: 'المريض: ${a['name'] ?? '—'}',
    );
    if (!ok) return;
    ref.read(reposProvider).appointments.delete('${a['id']}');
    _snack('تم حذف الموعد');
    if (_selectedId == '${a['id']}') _selectedId = null;
    _bump();
  }

  // ── النموذج (showDesktopDialog) ──

  /// يفتح نموذج الموعد. [editing] للتعديل؛ [defaultDate]/[defaultTime]
  /// لتعبئة تاريخ/وقتٍ مسبقين (نقر خانةٍ فارغة في الجدولة) — بارامترات
  /// اختيارية غير كاسرة.
  Future<void> _openForm({
    JMap? editing,
    String? defaultDate,
    String? defaultTime,
    JMap? prefill,
  }) async {
    final result = await showDesktopDialog<_FormResult>(
      context,
      title: editing == null
          ? (prefill == null ? 'موعد جديد' : 'نسخ الموعد')
          : 'تعديل الموعد',
      subtitle: editing == null
          ? (prefill == null
              ? 'أضف موعداً عادياً أو دورياً'
              : 'نسخةٌ جديدة — اختر التاريخ والوقت')
          : 'تعديل هذا الموعد فقط',
      width: 560,
      builder: (_) => _AppointmentForm(
        editing: editing,
        // اقتراحات الأسماء وتعبئة الهاتف من نفس مصادر الهاتف.
        records: ref.read(reposProvider).records.getAll(),
        prosthetics: ref.read(reposProvider).prosthetics.getAll(),
        debts: ref.read(reposProvider).debts.getAll(),
        appointments: ref.read(reposProvider).appointments.getAll(),
        clinics: clinicsOf(ref.read(appConfigProvider)),
        defaultDate: defaultDate ?? getCurrentDate(),
        defaultTime: defaultTime,
        prefill: prefill,
      ),
    );
    if (result != null) _save(result);
  }

  // ── مجموعة الإجراءات المشتركة — تُمرَّر للجدولة الأسبوعية كي تستدعي نفس
  //    مسارات الكتابة الحرفية (لا تكرار منطقٍ). ──
  ApptActions _actions(String centerName, String currency) => ApptActions(
        openForm: ({editing, defaultDate, defaultTime, prefill}) => _openForm(
              editing: editing,
              defaultDate: defaultDate,
              defaultTime: defaultTime,
              prefill: prefill,
            ),
        move: (prev, {required date, required time}) =>
            _moveOne(prev, date: date, time: time),
        copy: (src, {required date, required time}) =>
            _copyOne(src, date: date, time: time),
        setDuration: (prev, min) => _setDuration(prev, min),
        cancelOne: _cancelOne,
        markDone: (id, {done = true}) => _markDone(id, done: done),
        deleteOne: _deleteOne,
        launch: _launch,
        openSeriesList: (group) {
          // «عرض السلسلة»: نبدّل لعرض القائمة بفلتر الكل ونحدّد الموعد
          // الأول من المجموعة كي يُظهر التفاصيل قسم السلسلة كاملاً.
          final rows = _seriesRows(group);
          setState(() {
            _statusFilter = _StatusFilter.all;
            if (rows.isNotEmpty) _selectedId = '${rows.first['id']}';
          });
          saveDesktopPref(ref, _kViewKey, 'list', immediate: true);
        },
        centerName: centerName,
        currency: currency,
      );

  /// العرض الحالي — يُقرأ من التفضيل المحلي، افتراضياً الجدولة الأسبوعية.
  _ApptView get _view {
    final v = '${ref.read(desktopPrefsProvider)[_kViewKey] ?? ''}';
    return v == 'list' ? _ApptView.list : _ApptView.week;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(apptRevProvider);
    ref.watch(patientsRevProvider);
    ref.watch(desktopPrefsProvider);
    final cfg = ref.watch(appConfigProvider);
    final centerName = '${jsOr(cfg['centerName'], 'المركز')}';
    final currency = ref.watch(currencyProvider);

    final view = _view;

    final switcher = _ViewSwitcher(
      view: view,
      onChanged: (v) {
        // كتابةٌ فورية (لا حاجة للتخميد هنا — التبديل نادرٌ لا مستمرٌّ
        // كسحب المقابض) فلا يبقى مؤقّتٌ معلّق بعد التبديل.
        saveDesktopPref(ref, _kViewKey, v == _ApptView.week ? 'week' : 'list',
            immediate: true);
        setState(() {});
      },
    );

    // م164 — تبويبات العيادات أعلى الجدول: تفلتر القائمة والجدولة معاً،
    // والاختيار محفوظ في تفضيلات الجهاز.
    final clinicTabs = _ClinicTabs(
      clinics: clinicsOf(cfg),
      selected: _clinicFilter,
      hasUnassigned:
          hasUnassignedClinic(ref.watch(reposProvider).appointments.getAll()),
      onChanged: (v) {
        saveDesktopPref(ref, _kClinicKey, v, immediate: true);
        setState(() {});
      },
    );

    if (view == _ApptView.week) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SwitcherBar(switcher: switcher, center: clinicTabs),
          Expanded(
            child: WeeklyScheduler(
              key: const Key('appt-week-view'),
              actions: _actions(centerName, currency),
              clinicFilter: _clinicFilter,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SwitcherBar(switcher: switcher, center: clinicTabs),
        Expanded(child: _buildListView(centerName, currency)),
      ],
    );
  }

  /// جسم عرض القائمة (master/detail) — محفوظٌ حرفياً كما كان (يحفظ ميزة
  /// الدورية وكل اختبارات القائمة).
  Widget _buildListView(String centerName, String currency) {
    final appts = _filteredAppts();
    final groups = _grouped(appts);

    final master = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          searchCtl: _searchCtl,
          statusFilter: _statusFilter,
          rangeFilter: _rangeFilter,
          onSearch: () => setState(() {}),
          onStatus: (v) => setState(() => _statusFilter = v),
          onRange: (v) => setState(() => _rangeFilter = v),
          onAdd: () => _openForm(),
        ),
        Expanded(
          child: appts.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'لا مواعيد مطابقة',
                      key: const Key('appt-desk-empty-list'),
                      style: TextStyle(
                          fontSize: 13, color: BrandColors.mut),
                    ),
                  ),
                )
              : ListView.builder(
                  key: const Key('appt-desk-list'),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  itemCount: groups.length,
                  itemBuilder: (ctx, gi) {
                    final (date, rows) = groups[gi];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DateHeader(date: date),
                        for (final a in rows)
                          _ApptTile(
                            row: a,
                            selected: _selectedId == '${a['id']}',
                            onTap: () => setState(
                                () => _selectedId = '${a['id']}'),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );

    final selected = _selectedRow();
    final detailWidget = selected == null
        ? null
        : DetailHost(
            hostKey: 'appt-${selected['id']}',
            child: _ApptDetail(
              row: selected,
              centerName: centerName,
              currency: currency,
              series: '${selected['repeatGroup'] ?? ''}'.isEmpty
                  ? const []
                  : _seriesRows('${selected['repeatGroup']}'),
              onClose: () => setState(() => _selectedId = null),
              onEdit: () => _openForm(editing: selected),
              onCancel: () => _cancelOne('${selected['id']}'),
              onCancelRest: () =>
                  _cancelRestOfSeries('${selected['repeatGroup']}'),
              onDelete: () => _deleteOne(selected),
              onLaunch: _launch,
              onSelectSeries: (id) => setState(() => _selectedId = id),
            ),
          );

    return DesktopSplitView(
      id: 'appointments',
      emptyIcon: Icons.event_note_rounded,
      emptyTitle: 'اختر موعداً لعرض التفاصيل',
      emptyHint: 'اختر موعداً من القائمة لعرض تفاصيله وإدارته',
      masterWidth: 440,
      master: master,
      detail: detailWidget,
    );
  }
}

// ── م164: تبويبات العيادات (أعلى الجدول — تفلتر القائمة والجدولة) ────────────

class _ClinicTabs extends StatelessWidget {
  const _ClinicTabs({
    required this.clinics,
    required this.selected,
    required this.hasUnassigned,
    required this.onChanged,
  });

  final List<String> clinics;
  final String selected;
  final bool hasUnassigned;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (clinics.length <= 1 && !hasUnassigned) {
      return const SizedBox.shrink();
    }
    Widget tab(String value, String label) {
      final on = selected == value;
      return InkWell(
        key: Key('appt-desk-clinic-${value.isEmpty ? 'all' : value}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: on
                ? BrandColors.brand600
                : BrandColors.brand600.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: on
                    ? BrandColors.brand600
                    : BrandColors.brand600.withValues(alpha: .22)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : BrandColors.brand700)),
        ),
      );
    }

    // م165ب — بلا صفٍّ مستقل: يعيش وسط شريط المبدّل الأعلى.
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // م165 — أيقونة طبية (كانت storefront تشبه الدكان).
      Icon(Icons.medical_services_rounded,
          size: 15, color: BrandColors.mut2),
      const SizedBox(width: 8),
      Wrap(spacing: 6, children: [
        tab('', 'الكل'),
        for (final c in clinics) tab(c, c),
        if (hasUnassigned) tab(kNoClinic, 'غير محددة'),
      ]),
    ]);
  }
}

// ── شريط مبدّل العرض (أعلى الشاشة، محاذٍ لليمين في RTL) ─────────────────────

/// الشريط الحاوي لمبدّل العرض — خطٌّ رفيع أعلى الشاشة يضع المبدّل في
/// أقصى اليمين (بداية RTL) كما ينص عقد التصميم.
class _SwitcherBar extends StatelessWidget {
  const _SwitcherBar({required this.switcher, this.center});
  final Widget switcher;

  /// م165ب — تبويبات العيادات تُرفع لوسط نفس صف المبدّل (قرار المالك).
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: BrandColors.surface,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          switcher,
          const SizedBox(width: 10),
          Expanded(
            child: center == null
                ? const SizedBox.shrink()
                : Center(
                    child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal, child: center),
                  ),
          ),
        ],
      ),
    );
  }
}

/// مبدّل العرض (📅 أسبوع | ☰ قائمة) — SegmentedButton محفوظ عبر
/// saveDesktopPref. أعيد ضبط كثافته البصرية لتناسب رأس الشاشة.
class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({required this.view, required this.onChanged});
  final _ApptView view;
  final void Function(_ApptView) onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_ApptView>(
      key: const Key('appt-view-switcher'),
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
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
          value: _ApptView.week,
          icon: Icon(Icons.calendar_view_week_rounded, size: 16),
          label: Text('أسبوع'),
        ),
        ButtonSegment(
          value: _ApptView.list,
          icon: Icon(Icons.view_list_rounded, size: 16),
          label: Text('قائمة'),
        ),
      ],
      selected: {view},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

// ── شريط الأدوات (بحث + فلتر حالة + تنقّل نطاق + إضافة) ──────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchCtl,
    required this.statusFilter,
    required this.rangeFilter,
    required this.onSearch,
    required this.onStatus,
    required this.onRange,
    required this.onAdd,
  });

  final TextEditingController searchCtl;
  final _StatusFilter statusFilter;
  final _RangeFilter rangeFilter;
  final VoidCallback onSearch;
  final void Function(_StatusFilter) onStatus;
  final void Function(_RangeFilter) onRange;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    // النطاق يظهر فقط لقوائم القادمة/اليوم (لا معنى له للملغاة/الكل).
    final showRange = statusFilter == _StatusFilter.upcoming ||
        statusFilter == _StatusFilter.today;

    return Container(
      color: BrandColors.surface,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 34,
                child: TextField(
                  key: const Key('appt-desk-search'),
                  controller: searchCtl,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'بحث بالاسم أو الهاتف...',
                    hintStyle:
                        TextStyle(fontSize: 12, color: BrandColors.mut2),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 16, color: BrandColors.mut2),
                    filled: true,
                    fillColor: BrandColors.surface2,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: BrandColors.line, width: .8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: BrandColors.line, width: .8),
                    ),
                  ),
                  onChanged: (_) => onSearch(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('appt-desk-add'),
              style: FilledButton.styleFrom(
                backgroundColor: BrandColors.gold,
                foregroundColor: BrandColors.brand900,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('موعد جديد',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 8),
          // فلتر الحالة.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final entry in const [
                (_StatusFilter.upcoming, 'القادمة', 'upcoming'),
                (_StatusFilter.today, 'اليوم', 'today'),
                (_StatusFilter.cancelled, 'الملغاة', 'cancelled'),
                (_StatusFilter.all, 'الكل', 'all'),
              ])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    key: Key('appt-desk-status-${entry.$3}'),
                    label:
                        Text(entry.$2, style: const TextStyle(fontSize: 11)),
                    selected: statusFilter == entry.$1,
                    selectedColor: BrandColors.goldDark,
                    labelStyle: TextStyle(
                        color: statusFilter == entry.$1
                            ? Colors.white
                            : BrandColors.ink,
                        fontWeight: FontWeight.w700),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onStatus(entry.$1),
                  ),
                ),
            ]),
          ),
          // تنقّل النطاق (اليوم/الغد/الأسبوع/الكل).
          if (showRange) ...[
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final entry in const [
                  (_RangeFilter.all, 'كل القادم', 'all'),
                  (_RangeFilter.day, 'اليوم', 'day'),
                  (_RangeFilter.tomorrow, 'الغد', 'tomorrow'),
                  (_RangeFilter.week, 'هذا الأسبوع', 'week'),
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      key: Key('appt-desk-range-${entry.$3}'),
                      label: Text(entry.$2,
                          style: const TextStyle(fontSize: 10.5)),
                      selected: rangeFilter == entry.$1,
                      selectedColor: BrandColors.brand600,
                      labelStyle: TextStyle(
                          color: rangeFilter == entry.$1
                              ? Colors.white
                              : BrandColors.ink,
                          fontWeight: FontWeight.w700),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => onRange(entry.$1),
                    ),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ── عنوان قسم التاريخ ────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});
  final String date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
      child: Row(children: [
        Text(
          date,
          textDirection: TextDirection.ltr,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: BrandColors.brand700),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: dayDiff(date) == 0
                ? const Color(0x1AF59E0B)
                : BrandColors.brand600.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            dayLabel(date),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: dayDiff(date) == 0
                  ? const Color(0xFFB8860B)
                  : BrandColors.mut,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: BrandColors.line, height: 1)),
      ]),
    );
  }
}

// ── بطاقة موعد في القائمة اليمنى ─────────────────────────────────────────────

class _ApptTile extends StatefulWidget {
  const _ApptTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final JMap row;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ApptTile> createState() => _ApptTileState();
}

class _ApptTileState extends State<_ApptTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.row;
    final id = '${a['id']}';
    final status = '${a['status'] ?? 'pending'}';
    final completed = status == 'completed';
    final cancelled = status == 'cancelled';
    final isRecurring = '${a['repeatGroup'] ?? ''}'.isNotEmpty;
    final time = '${a['time'] ?? ''}';

    final bg = widget.selected
        ? BrandColors.gold.withValues(alpha: .10)
        : _hovered
            ? BrandColors.surface2
            : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          key: Key('appt-desk-tile-$id'),
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected
                  ? BrandColors.gold.withValues(alpha: .4)
                  : Colors.transparent,
            ),
          ),
          child: Opacity(
            opacity: completed || cancelled ? .65 : 1,
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (isRecurring) ...[
                        Icon(Icons.repeat_rounded,
                            key: Key('appt-desk-recur-icon-$id'),
                            size: 13,
                            color: BrandColors.goldDark),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          '${a['name'] ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: BrandColors.brandText),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      '${jsOr(a['service'], '—')}'
                      '${time.isNotEmpty ? ' · ${to12h(time)}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // م165ب — أغمق للقراءة.
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: BrandColors.ink.withValues(alpha: .7)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(status: status),
            ]),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    // م164 — الكتالوج الموحّد: 8 حالات باسمٍ ظاهرٍ ولونٍ هادئ.
    final norm = normApptStatus(status);
    final prefix = switch (norm) {
      'upcoming' => '⏱ ',
      'completed' => '✓ ',
      'cancelled' || 'no_show' => '✕ ',
      _ => '',
    };
    final label = '$prefix${apptStatusLabel(norm)}';
    final color = apptStatusColor(norm);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}

// ── لوحة تفاصيل الموعد المختار ───────────────────────────────────────────────

class _ApptDetail extends StatelessWidget {
  const _ApptDetail({
    required this.row,
    required this.centerName,
    required this.currency,
    required this.series,
    required this.onClose,
    required this.onEdit,
    required this.onCancel,
    required this.onCancelRest,
    required this.onDelete,
    required this.onLaunch,
    required this.onSelectSeries,
  });

  final JMap row;
  final String centerName;
  final String currency;
  final List<JMap> series;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onCancelRest;
  final VoidCallback onDelete;
  final Future<void> Function(String) onLaunch;
  final void Function(String) onSelectSeries;

  @override
  Widget build(BuildContext context) {
    final name = '${row['name'] ?? '—'}';
    final phone = cleanPhone(row['phone']);
    final service = '${row['service'] ?? ''}'.trim();
    final date = '${row['date'] ?? ''}';
    final time = '${row['time'] ?? ''}';
    final notes = '${row['notes'] ?? ''}'.trim();
    final status = '${row['status'] ?? 'pending'}';
    final cancelled = status == 'cancelled';
    final isRecurring = '${row['repeatGroup'] ?? ''}'.isNotEmpty;
    final repeat = '${row['repeat'] ?? ''}';
    final idx = jsNumOr0(row['repeatIndex']).toInt();
    final cnt = jsNumOr0(row['repeatCount']).toInt();

    Widget field(String label, String value) {
      if (value.isEmpty || value == 'null') return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 10.5, color: BrandColors.mut2)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: BrandColors.ink)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      key: const Key('appt-desk-detail'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس التفاصيل.
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BrandColors.gold.withValues(alpha: .12),
                border:
                    Border.all(color: BrandColors.gold.withValues(alpha: .35)),
              ),
              child: Icon(
                isRecurring ? Icons.repeat_rounded : Icons.event_rounded,
                size: 22,
                color: BrandColors.goldDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: BrandColors.brandText)),
                  const SizedBox(height: 3),
                  Text('$date${time.isNotEmpty ? ' · ${to12h(time)}' : ''}',
                      style: TextStyle(
                          fontSize: 11.5, color: BrandColors.mut2)),
                ],
              ),
            ),
            _StatusPill(status: status),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: BrandColors.mut,
              tooltip: 'إغلاق',
              onPressed: onClose,
            ),
          ]),
          const SizedBox(height: 16),

          // شارة الدورية.
          if (isRecurring)
            Container(
              key: const Key('appt-desk-recur-badge'),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: BrandColors.gold.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: BrandColors.gold.withValues(alpha: .3)),
              ),
              child: Row(children: [
                Icon(Icons.repeat_rounded,
                    size: 18, color: BrandColors.goldDark),
                const SizedBox(width: 8),
                Text(
                  'موعد دوري — ${_repeatLabels[repeat] ?? repeat} ($idx/$cnt)',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.goldDark),
                ),
              ]),
            ),

          // حقول التفاصيل.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: BrandColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: BrandColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                field('اسم المريض', name),
                field('رقم الهاتف', '${row['phone'] ?? ''}'.trim()),
                // م164 — العيادة ظاهرة في التفاصيل دائماً.
                field(
                    'العيادة',
                    '${row['clinic'] ?? ''}'.isEmpty
                        ? 'غير محددة'
                        : '${row['clinic']}'),
                field('الخدمة / الإجراء', service),
                field('التاريخ', date),
                field('الوقت', time.isEmpty ? '' : to12h(time)),
                field('الملاحظات', notes),
                // م164 — اسم الحالة من الكتالوج الموحّد (8 حالات).
                field('الحالة', apptStatusLabel(row['status'])),
              ],
            ),
          ),

          // أفعال التواصل (اتصال/واتساب/SMS) — بنفس بوابات الهاتف.
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _ActionChip(
                label: 'اتصال',
                icon: Icons.call_rounded,
                color: const Color(0xFF15604A),
                keyId: 'appt-desk-call',
                onTap: () => onLaunch('tel:$phone'),
              ),
              _ActionChip(
                label: 'تذكير واتساب',
                icon: Icons.chat_rounded,
                color: const Color(0xFF25D366),
                keyId: 'appt-desk-wa',
                onTap: () => onLaunch(
                    'https://wa.me/$phone?text=${Uri.encodeComponent(waReminderText(row, centerName))}'),
              ),
              _ActionChip(
                label: 'SMS',
                icon: Icons.sms_rounded,
                color: BrandColors.goldDark,
                keyId: 'appt-desk-sms',
                onTap: () => onLaunch(
                    'sms:$phone?body=${Uri.encodeComponent(smsReminderText(row, centerName))}'),
              ),
            ]),
          ],

          // أفعال إدارة الموعد.
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('appt-desk-edit'),
                onPressed: onEdit,
                icon: Icon(Icons.edit_rounded,
                    size: 15, color: BrandColors.brandIcon),
                label: const Text('تعديل', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('appt-desk-cancel'),
                onPressed: cancelled ? null : onCancel,
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444)),
                icon: const Icon(Icons.block_rounded, size: 15),
                label: Text(isRecurring ? 'إلغاء هذا الموعد' : 'إلغاء',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('appt-desk-delete'),
              tooltip: 'حذف نهائياً',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 18, color: BrandColors.red),
            ),
          ]),

          // قسم السلسلة للموعد الدوري.
          if (isRecurring && series.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(children: [
              Icon(Icons.list_alt_rounded,
                  size: 16, color: BrandColors.goldDark),
              const SizedBox(width: 6),
              Text('مواعيد السلسلة (${series.length})',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: BrandColors.brand700)),
              const Spacer(),
              TextButton.icon(
                key: const Key('appt-desk-cancel-rest'),
                onPressed: onCancelRest,
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444)),
                icon: const Icon(Icons.block_rounded, size: 15),
                label: const Text('إلغاء بقية السلسلة',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ]),
            const SizedBox(height: 6),
            Container(
              key: const Key('appt-desk-series'),
              decoration: BoxDecoration(
                color: BrandColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: BrandColors.line),
              ),
              child: Column(
                children: [
                  for (final s in series)
                    _SeriesRow(
                      row: s,
                      isCurrent: '${s['id']}' == '${row['id']}',
                      onTap: () => onSelectSeries('${s['id']}'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeriesRow extends StatelessWidget {
  const _SeriesRow({
    required this.row,
    required this.isCurrent,
    required this.onTap,
  });

  final JMap row;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final idx = jsNumOr0(row['repeatIndex']).toInt();
    final cnt = jsNumOr0(row['repeatCount']).toInt();
    final date = '${row['date'] ?? ''}';
    final status = '${row['status'] ?? 'pending'}';

    return InkWell(
      key: Key('appt-desk-series-row-${row['id']}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isCurrent
              ? BrandColors.gold.withValues(alpha: .08)
              : null,
          border: Border(bottom: BorderSide(color: BrandColors.line)),
        ),
        child: Row(children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BrandColors.brand600.withValues(alpha: .1),
            ),
            child: Text('$idx',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: BrandColors.brand700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$date  ·  الموعد $idx من $cnt',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                      isCurrent ? FontWeight.w800 : FontWeight.w600,
                  color: BrandColors.ink),
            ),
          ),
          _StatusPill(status: status),
        ]),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.keyId,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String keyId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key(keyId),
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  نموذج «موعد جديد / تعديل» — يفتح في showDesktopDialog
// ══════════════════════════════════════════════════════════════════════════

/// نتيجة النموذج المعادة عبر Navigator.pop.
class _FormResult {
  const _FormResult({
    required this.editingId,
    required this.name,
    required this.phone,
    required this.service,
    required this.date,
    required this.time,
    required this.notes,
    required this.clinic,
    required this.repeat,
    required this.count,
    required this.durationMin,
  });

  /// م164 — عيادة الموعد (إلزامية عند تعدد العيادات).
  final String clinic;

  final String? editingId;
  final String name;
  final String phone;
  final String service;
  final String date;
  final String time;
  final String notes;

  /// null = موعد عادي؛ 'weekly'|'biweekly'|'monthly' = دوري.
  final String? repeat;
  final int count;

  /// مدة الموعد بالدقائق — null = تُترك على الافتراضي/القيمة السابقة.
  final int? durationMin;
}

class _AppointmentForm extends StatefulWidget {
  const _AppointmentForm({
    required this.editing,
    required this.records,
    required this.prosthetics,
    required this.debts,
    required this.appointments,
    required this.clinics,
    required this.defaultDate,
    this.defaultTime,
    this.prefill,
  });

  /// م164 — عيادات الإعدادات: واحدة ⇒ اختيار تلقائي؛ تعدد ⇒ إلزامي.
  final List<String> clinics;

  final JMap? editing;
  final List<JMap> records;
  final List<JMap> prosthetics;
  final List<JMap> debts;
  final List<JMap> appointments;
  final String defaultDate;

  /// وقتٌ مسبق التعبئة (نقر خانةٍ فارغة في الجدولة) — اختياري غير كاسر.
  final String? defaultTime;

  /// تعبئةٌ مسبقة لموعدٍ **جديد** (نسخ الموعد): حقولٌ ميدانية فقط بلا id،
  /// فالحفظ ينشئ صفاً جديداً (لا تعديلاً). تُستعمل فقط عند [editing]==null.
  final JMap? prefill;

  @override
  State<_AppointmentForm> createState() => _AppointmentFormState();
}

class _AppointmentFormState extends State<_AppointmentForm> {
  late final TextEditingController _nameCtl;
  late final TextEditingController _phoneCtl;
  late final TextEditingController _serviceCtl;
  late final TextEditingController _notesCtl;
  late final TextEditingController _durationCtl;
  String _date = '';
  String _time = '';
  String _clinic = '';
  List<String> _suggestions = [];

  /// نمط التكرار المختار: null = بلا (عادي).
  String? _repeat;
  int _count = 4;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    // مصدر التعبئة: صف التعديل، أو (لموعدٍ جديد) خريطة النسخ المسبقة.
    final e = widget.editing ?? (widget.editing == null ? widget.prefill : null);
    _nameCtl = TextEditingController(text: '${e?['name'] ?? ''}');
    _phoneCtl = TextEditingController(text: '${e?['phone'] ?? ''}');
    _serviceCtl = TextEditingController(text: '${e?['service'] ?? ''}');
    _notesCtl = TextEditingController(text: '${e?['notes'] ?? ''}');
    // المدة: تظهر القيمة السابقة/المنسوخة، وتبقى فارغة (=افتراضي 30) عند
    // غيابها. لا نفرض «30» نصاً كي يبقى الفارغ معناه «الافتراضي».
    final dur = jsNumOr0(e?['durationMin']);
    _durationCtl =
        TextEditingController(text: dur > 0 ? '${dur.toInt()}' : '');
    // التاريخ/الوقت: من صف التعديل إن وُجد، وإلا من الافتراضات الممرّرة
    // (النسخ لا يمرّر date/time في e لأنه خريطة حقولٍ ميدانية فقط).
    _date = '${widget.editing?['date'] ?? widget.defaultDate}';
    _time = '${widget.editing?['time'] ?? widget.defaultTime ?? ''}';
    // م164 — العيادة: من الصف/النسخة، وإلا اختيار تلقائي عند عيادة واحدة
    // فقط (التعدد يوجب اختياراً صريحاً — لا افتراض بأول عيادة).
    _clinic = '${e?['clinic'] ?? ''}';
    if (_clinic.isEmpty && widget.clinics.length == 1) {
      _clinic = widget.clinics.first;
    }
    if (!widget.clinics.contains(_clinic)) _clinic = '';
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _phoneCtl.dispose();
    _serviceCtl.dispose();
    _notesCtl.dispose();
    _durationCtl.dispose();
    super.dispose();
  }

  void _submit() {
    final durTxt = _durationCtl.text.trim();
    final dur = durTxt.isEmpty ? null : jsNumOr0(durTxt).toInt();
    Navigator.of(context).pop(_FormResult(
      editingId: _isEdit ? '${widget.editing!['id']}' : null,
      name: _nameCtl.text,
      phone: _phoneCtl.text,
      service: _serviceCtl.text,
      date: _date,
      time: _time,
      notes: _notesCtl.text,
      clinic: _clinic,
      // التكرار يظهر عند الإنشاء فقط — التعديل يمس الموعد الواحد.
      repeat: _isEdit ? null : _repeat,
      count: _count,
      durationMin: (dur != null && dur > 0) ? dur : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Enter / Ctrl+S يحفظ داخل الحوار.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _submit,
      },
      child: FocusScope(
        autofocus: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // م164 — العيادة أولاً: إلزامية عند التعدد وظاهرة دائماً.
              if (widget.clinics.length > 1) ...[
                DropdownButtonFormField<String>(
                  key: const Key('appt-form-clinic'),
                  initialValue: _clinic.isEmpty ? null : _clinic,
                  isDense: true,
                  style: TextStyle(
                      fontSize: 12.5, color: BrandColors.ink),
                  decoration:
                      const InputDecoration(labelText: 'العيادة *'),
                  items: [
                    for (final c in widget.clinics)
                      DropdownMenuItem(
                          value: c,
                          child: Text(c,
                              style: const TextStyle(fontSize: 12.5))),
                  ],
                  onChanged: (v) => setState(() => _clinic = v ?? ''),
                ),
                const SizedBox(height: 10),
              ] else if (widget.clinics.length == 1) ...[
                Text('العيادة: ${widget.clinics.first}',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.mut)),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('appt-form-name'),
                    controller: _nameCtl,
                    autofocus: true,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                        isDense: true, labelText: 'اسم المريض *'),
                    onChanged: (v) => setState(() {
                      _suggestions = apptNameSuggestions(
                          v, widget.records, widget.prosthetics);
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const Key('appt-form-phone'),
                    controller: _phoneCtl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: const InputDecoration(
                        isDense: true, labelText: 'رقم الهاتف'),
                  ),
                ),
              ]),
              if (_suggestions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: BrandColors.gold.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: BrandColors.gold.withValues(alpha: .25)),
                  ),
                  child: Wrap(spacing: 6, runSpacing: 4, children: [
                    for (final s in _suggestions)
                      ActionChip(
                        key: Key('appt-form-suggest-$s'),
                        label:
                            Text(s, style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          _nameCtl.text = s;
                          _suggestions = [];
                          final phone = phoneForName(s,
                              records: widget.records,
                              prosthetics: widget.prosthetics,
                              debts: widget.debts,
                              appointments: widget.appointments);
                          if (phone.isNotEmpty) _phoneCtl.text = phone;
                        }),
                      ),
                  ]),
                ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('appt-form-service'),
                controller: _serviceCtl,
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'الخدمة / الإجراء',
                    hintText: 'مثال: كشف، تنظيف، حشو...'),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('appt-form-date'),
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () async {
                      final init = _date.isNotEmpty
                          ? DateTime.tryParse(_date) ?? DateTime.now()
                          : DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: init,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setState(() => _date =
                            '${picked.year.toString().padLeft(4, '0')}-'
                            '${picked.month.toString().padLeft(2, '0')}-'
                            '${picked.day.toString().padLeft(2, '0')}');
                      }
                    },
                    icon: const Icon(Icons.event_rounded, size: 14),
                    label: Text(_date.isEmpty ? 'التاريخ *' : _date,
                        style: const TextStyle(fontSize: 11.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('appt-form-time'),
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (picked != null) {
                        setState(() => _time =
                            '${picked.hour.toString().padLeft(2, '0')}:'
                            '${picked.minute.toString().padLeft(2, '0')}');
                      }
                    },
                    icon: const Icon(Icons.schedule_rounded, size: 14),
                    label: Text(_time.isEmpty ? 'الوقت' : to12h(_time),
                        style: const TextStyle(fontSize: 11.5)),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              // ── المدة (دقائق) — حقلٌ رقمي اختياري، الافتراضي 30 عند الفراغ ──
              TextField(
                key: const Key('appt-form-duration'),
                controller: _durationCtl,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'المدة (دقائق)',
                    hintText: 'افتراضي 30'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('appt-form-notes'),
                controller: _notesCtl,
                maxLines: 2,
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'ملاحظات',
                    hintText: 'ملاحظات إضافية...'),
              ),

              // ── محدد التكرار — يظهر عند الإنشاء فقط ──
              if (!_isEdit) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: BrandColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: BrandColors.brand600.withValues(alpha: .2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.repeat_rounded,
                            size: 15, color: BrandColors.goldDark),
                        const SizedBox(width: 6),
                        Text('التكرار',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: BrandColors.goldDark)),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        for (final entry in const [
                          (null, 'بلا', 'none'),
                          ('weekly', 'أسبوعي', 'weekly'),
                          ('biweekly', 'كل أسبوعين', 'biweekly'),
                          ('monthly', 'شهري', 'monthly'),
                        ])
                          ChoiceChip(
                            key: Key('appt-form-repeat-${entry.$3}'),
                            label: Text(entry.$2,
                                style: const TextStyle(fontSize: 11)),
                            selected: _repeat == entry.$1,
                            selectedColor: BrandColors.goldDark,
                            labelStyle: TextStyle(
                                color: _repeat == entry.$1
                                    ? Colors.white
                                    : BrandColors.ink,
                                fontWeight: FontWeight.w700),
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) =>
                                setState(() => _repeat = entry.$1),
                          ),
                      ]),
                      // عدد المرات (2-24) — يظهر عند اختيار نمط دوري.
                      if (_repeat != null) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          Text('عدد المرات:',
                              style: TextStyle(
                                  fontSize: 12, color: BrandColors.mut)),
                          const SizedBox(width: 10),
                          IconButton(
                            key: const Key('appt-form-count-dec'),
                            visualDensity: VisualDensity.compact,
                            onPressed: _count > 2
                                ? () => setState(() => _count--)
                                : null,
                            icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                size: 20),
                          ),
                          Text('$_count',
                              key: const Key('appt-form-count'),
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900)),
                          IconButton(
                            key: const Key('appt-form-count-inc'),
                            visualDensity: VisualDensity.compact,
                            onPressed: _count < 24
                                ? () => setState(() => _count++)
                                : null,
                            icon: const Icon(
                                Icons.add_circle_outline_rounded,
                                size: 20),
                          ),
                          const Spacer(),
                          Text('من 2 إلى 24',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: BrandColors.mut2)),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton(
                    key: const Key('appt-form-save'),
                    style: FilledButton.styleFrom(
                        backgroundColor: BrandColors.gold,
                        foregroundColor: BrandColors.brand900,
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: _submit,
                    child: Text(
                        _isEdit
                            ? 'تحديث'
                            : (_repeat == null
                                ? 'حفظ الموعد'
                                : 'إنشاء السلسلة'),
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('appt-form-cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child:
                      const Text('إلغاء', style: TextStyle(fontSize: 12.5)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
