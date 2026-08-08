/// تبويب المواعيد التقليدي — نقل بنيوي كامل لـ CalendarTab.vue فوق المنطق
/// الحرفي في appointments_logic:
///   • رأس «جدول المواعيد» + شهر سابق/تالٍ + زر إضافة موعد جديد
///   • نموذج سطري (اسم باقتراحات ضبابية تملأ الهاتف تلقائياً، هاتف، خدمة
///     نصية حرة، تاريخ/وقت، ملاحظات) للإضافة والتعديل ووضع المتابعة
///   • شبكة الشهر: بداية أحدية، نقطة وعدّاد وأول اسمين لكل يوم
///   • لوحة اليوم: حالة قادم/تم/ملغي، اتصال، تذكير واتساب/SMS، تذكير دين
///     أحمر عند وجود متبقٍ، إتمام/تراجع، تعديل/حذف (dcConfirm نوع المواعيد)
///   • المواعيد القادمة (12) — النقر ينتقل ليوم الموعد
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
    show patientKeyFor;
import '../patients/patients_tab.dart'
    show patientSearchProvider, patientsRevProvider;
import '../shell/app_shell.dart' show activeTabProvider;
import 'appointments_logic.dart';

/// نبضة إعادة قراءة بعد كل كتابة موعد.
final apptRevProvider = StateProvider<int>((ref) => 0);

/// مسودة «موعد متابعة» القادمة من شاشة الإضافة (اسم/هاتف/خدمة) —
/// توأم query {followup:'1', name, phone, service}. يستهلكها التبويب مرة.
final followUpDraftProvider = StateProvider<JMap?>((ref) => null);

class AppointmentsTab extends ConsumerStatefulWidget {
  const AppointmentsTab({super.key});

  @override
  ConsumerState<AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends ConsumerState<AppointmentsTab> {
  late int calYear;
  late int calMonth; // 0-11 كما الأصل
  String? selectedDay;
  bool showForm = false;
  String? editingId;
  bool followUpMode = false;
  List<String> suggestions = [];

  final nameCtl = TextEditingController();
  final phoneCtl = TextEditingController();
  final serviceCtl = TextEditingController();
  final notesCtl = TextEditingController();
  final durationCtl = TextEditingController();
  String formDate = '';
  String formTime = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    calYear = now.year;
    calMonth = now.month - 1;
    // مسودة المتابعة (goFollowUpAppt) — تُستهلك بعد الإطار الأول.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final draft = ref.read(followUpDraftProvider);
      if (draft == null || !mounted) return;
      ref.read(followUpDraftProvider.notifier).state = null;
      setState(() {
        followUpMode = true;
        showForm = true;
        editingId = null;
        nameCtl.text = '${draft['name'] ?? ''}';
        phoneCtl.text = '${draft['phone'] ?? ''}';
        serviceCtl.text = '${draft['service'] ?? ''}';
        formDate = '';
        formTime = '';
        notesCtl.text = nameCtl.text.isNotEmpty
            ? 'متابعة — ${draft['service'] ?? ''}'
            : '';
      });
    });
  }

  @override
  void dispose() {
    nameCtl.dispose();
    phoneCtl.dispose();
    serviceCtl.dispose();
    notesCtl.dispose();
    durationCtl.dispose();
    super.dispose();
  }

  void _bump() {
    ref.read(apptRevProvider.notifier).state++;
    setState(() {});
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  void _resetForm() {
    editingId = null;
    followUpMode = false;
    nameCtl.clear();
    phoneCtl.clear();
    serviceCtl.clear();
    notesCtl.clear();
    durationCtl.clear();
    formDate = selectedDay ?? getCurrentDate();
    formTime = '';
    suggestions = [];
  }

  // ── الحفظ (saveAppt حرفياً) ──
  void _saveAppt() {
    final name = nameCtl.text.trim();
    final date = formDate;
    if (name.isEmpty) {
      _snack('⚠ أدخل اسم المريض');
      return;
    }
    if (date.isEmpty) {
      _snack('⚠ أدخل التاريخ');
      return;
    }
    // م: المدة (durationMin) — حقلٌ مرن اختياري في كتلة data. فارغ = افتراضي
    // 30 عند العرض/القراءة (لا نكتب القيمة صراحةً حتى لا نُثبّت رقماً).
    final durTxt = durationCtl.text.trim();
    final durMin = durTxt.isEmpty ? 0 : jsNumOr0(durTxt).toInt();
    final repos = ref.read(reposProvider);
    if (editingId != null) {
      final prev = repos.appointments.getById(editingId!);
      if (prev != null) {
        final patientId = jsTruthy(prev['patient_id'])
            ? prev['patient_id']
            : (patientKeyFor(name: name, phone: phoneCtl.text) ?? '');
        repos.appointments.upsertLocal({
          ...prev,
          'name': name,
          'phone': phoneCtl.text,
          'date': date,
          'time': formTime,
          'service': serviceCtl.text,
          'notes': notesCtl.text,
          'patient_id': patientId,
          if (durMin > 0) 'durationMin': durMin,
          '_mod': jsNow(),
        });
      }
      _snack('تم تعديل الموعد');
    } else {
      final auth = ref.read(authProvider);
      repos.appointments.upsertLocal({
        'id': genId(),
        'uid': auth is SignedIn ? auth.user.uid : '',
        'name': name,
        'phone': phoneCtl.text,
        'date': date,
        'time': formTime,
        'service': serviceCtl.text,
        'notes': notesCtl.text,
        'status': 'pending',
        'patient_id':
            patientKeyFor(name: name, phone: phoneCtl.text) ?? '',
        'clinic_id': '',
        if (durMin > 0) 'durationMin': durMin,
        '_mod': jsNow(),
        '_t': 'a',
      });
      _snack(followUpMode ? 'تم حفظ موعد المتابعة' : 'تم إضافة الموعد');
    }
    final wasFollowUp = followUpMode;
    setState(() {
      showForm = false;
      followUpMode = false;
    });
    _bump();
    ref.read(patientsRevProvider.notifier).state++;

    // العودة التلقائية لتبويب الإضافة بعد موعد المتابعة (followUpAuto).
    if (wasFollowUp) {
      final cfg = ref.read(appConfigProvider);
      if (cfg['followUpAuto'] != false) {
        ref.read(activeTabProvider.notifier).state = 'home';
      }
    }
  }

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

  Future<void> _deleteAppt(JMap a) async {
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
    _bump();
  }

  void _goPatient(String? name) {
    if (name == null || name.isEmpty) return;
    ref.read(patientSearchProvider.notifier).state = name;
    ref.read(activeTabProvider.notifier).state = 'clinics';
  }

  Future<void> _launch(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    ref.watch(apptRevProvider);
    final repos = ref.watch(reposProvider);
    final appointments = repos.appointments.getAll();
    final records = repos.records.getAll();
    final prosthetics = repos.prosthetics.getAll();
    final debts = repos.debts.getAll();
    final cfg = ref.watch(appConfigProvider);
    final centerName = '${jsOr(cfg['centerName'], 'المركز')}';
    final currency = ref.watch(currencyProvider);

    final apptMap = buildApptMap(
      appointments: appointments,
      records: records,
      prosthetics: prosthetics,
    );
    final cells = calendarCells(calYear, calMonth, apptMap);
    final dayList = selectedDay == null
        ? const <JMap>[]
        : ([...?apptMap[selectedDay]]..sort((a, b) =>
            jsNumOr0(b['_mod']).compareTo(jsNumOr0(a['_mod']))));
    final upcoming = upcomingAppts(apptMap);

    return ListView(
      key: const Key('appointments-tab'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        // ── الرأس: العنوان + تنقّل الشهر ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.event_note_rounded,
                    size: 16, color: BrandColors.goldDark),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('جدول المواعيد',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: BrandColors.goldDark)),
                ),
                IconButton(
                  key: const Key('cal-prev'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    calMonth--;
                    if (calMonth < 0) {
                      calMonth = 11;
                      calYear--;
                    }
                  }),
                  icon: const Icon(Icons.chevron_right_rounded, size: 22),
                ),
                Text('${monthNames[calMonth]} $calYear',
                    key: const Key('cal-month-label'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                IconButton(
                  key: const Key('cal-next'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    calMonth++;
                    if (calMonth > 11) {
                      calMonth = 0;
                      calYear++;
                    }
                  }),
                  icon: const Icon(Icons.chevron_left_rounded, size: 22),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('appt-add-toggle'),
                  style: FilledButton.styleFrom(
                      backgroundColor: BrandColors.gold,
                      foregroundColor: BrandColors.brand900,
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => setState(() {
                    if (showForm && editingId == null) {
                      showForm = false;
                      return;
                    }
                    _resetForm();
                    showForm = true;
                  }),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('إضافة موعد جديد',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
              ),

              // ── النموذج السطري ──
              if (showForm) _apptForm(records, prosthetics, debts,
                  appointments),

              const SizedBox(height: 10),
              // ── شبكة الشهر ──
              Row(children: [
                for (final d in dayNames)
                  Expanded(
                    child: Text(d,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.mut2)),
                  ),
              ]),
              const SizedBox(height: 3),
              for (var row = 0; row < cells.length ~/ 7; row++)
                Row(children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                        child: _dayCell(cells[row * 7 + col])),
                ]),
            ]),
          ),
        ),

        // ── لوحة اليوم المحدد ──
        if (selectedDay != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        '$selectedDay (${dayLabel(selectedDay!)}) — ${dayList.length} موعد',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: BrandColors.brand700),
                      ),
                    ),
                    FilledButton(
                      key: const Key('appt-add-for-day'),
                      style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.gold,
                          foregroundColor: BrandColors.brand900,
                          visualDensity: VisualDensity.compact),
                      onPressed: () => setState(() {
                        _resetForm();
                        formDate = selectedDay!;
                        showForm = true;
                      }),
                      child: const Text('+ موعد جديد',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  if (dayList.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Center(
                        child: Text('لا مواعيد في هذا اليوم',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: BrandColors.mut2)),
                      ),
                    )
                  else
                    for (final a in dayList)
                      _apptCard(a, debts, centerName, currency),
                ],
              ),
            ),
          ),

        // ── المواعيد القادمة ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('المواعيد القادمة',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                if (upcoming.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('لا توجد مواعيد قادمة',
                          style: TextStyle(
                              fontSize: 11.5, color: BrandColors.mut2)),
                    ),
                  )
                else
                  for (final a in upcoming)
                    InkWell(
                      key: Key('upcoming-${a['id']}'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () =>
                          setState(() => selectedDay = '${a['date']}'),
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
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('${a['name'] ?? ''}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: BrandColors.brand700)),
                                Text(
                                  '${a['date']}'
                                  '${jsTruthy(a['time']) ? ' — ${to12h('${a['time']}')}' : ''}'
                                  ' — ${jsOr(a['service'], '—')}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: BrandColors.mut),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            dayLabel('${a['date']}'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: dayDiff('${a['date']}') == 0
                                  ? const Color(0xFFF59E0B)
                                  : dayDiff('${a['date']}') <= 2
                                      ? const Color(0xFF15604A)
                                      : const Color(0xFF94A3B8),
                            ),
                          ),
                        ]),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── خلية يوم ──
  Widget _dayCell(CalCell cell) {
    final selected = cell.dateStr.isNotEmpty && cell.dateStr == selectedDay;
    return InkWell(
      key: cell.dateStr.isEmpty ? null : Key('cal-day-${cell.dateStr}'),
      borderRadius: BorderRadius.circular(8),
      onTap: cell.other
          ? null
          : () => setState(() => selectedDay = cell.dateStr),
      child: Container(
        height: 44,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: selected
              ? BrandColors.brand600.withValues(alpha: .18)
              : cell.isToday
                  ? BrandColors.gold.withValues(alpha: .2)
                  : cell.apptCount > 0
                      ? BrandColors.brand600.withValues(alpha: .07)
                      : null,
          border: cell.isToday
              ? Border.all(color: BrandColors.gold, width: 1.2)
              : selected
                  ? Border.all(color: BrandColors.brand600)
                  : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${cell.day}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: cell.isToday || selected
                    ? FontWeight.w800
                    : FontWeight.w500,
                color: cell.other ? BrandColors.faint2 : BrandColors.ink,
              ),
            ),
            if (cell.apptCount > 0 && !cell.other)
              Container(
                margin: const EdgeInsets.only(top: 1),
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 0.5),
                decoration: BoxDecoration(
                  color: BrandColors.brand600,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${cell.apptCount}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }

  // ── النموذج ──
  Widget _apptForm(List<JMap> records, List<JMap> prosthetics,
      List<JMap> debts, List<JMap> appointments) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BrandColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: BrandColors.brand600.withValues(alpha: .2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            editingId != null
                ? 'تعديل الموعد'
                : (followUpMode ? 'موعد متابعة' : 'موعد جديد'),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: BrandColors.mut),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('appt-name'),
                controller: nameCtl,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                    isDense: true, labelText: 'اسم المريض *'),
                onChanged: (v) => setState(() {
                  suggestions =
                      apptNameSuggestions(v, records, prosthetics);
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
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: BrandColors.gold.withValues(alpha: .25)),
              ),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final s in suggestions)
                  ActionChip(
                    key: Key('appt-suggest-$s'),
                    label: Text(s, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      nameCtl.text = s;
                      suggestions = [];
                      final phone = phoneForName(s,
                          records: records,
                          prosthetics: prosthetics,
                          debts: debts,
                          appointments: appointments);
                      if (phone.isNotEmpty) phoneCtl.text = phone;
                    }),
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
                labelText: 'الخدمة / الإجراء',
                hintText: 'مثال: كشف، تنظيف، حشو...'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('appt-date'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                onPressed: () async {
                  final init = formDate.isNotEmpty
                      ? DateTime.tryParse(formDate) ?? DateTime.now()
                      : DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: init,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    setState(() => formDate =
                        '${picked.year.toString().padLeft(4, '0')}-'
                        '${picked.month.toString().padLeft(2, '0')}-'
                        '${picked.day.toString().padLeft(2, '0')}');
                  }
                },
                icon: const Icon(Icons.event_rounded, size: 14),
                label: Text(formDate.isEmpty ? 'التاريخ *' : formDate,
                    style: const TextStyle(fontSize: 11.5)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('appt-time'),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (picked != null) {
                    setState(() => formTime =
                        '${picked.hour.toString().padLeft(2, '0')}:'
                        '${picked.minute.toString().padLeft(2, '0')}');
                  }
                },
                icon: const Icon(Icons.schedule_rounded, size: 14),
                label: Text(
                    formTime.isEmpty ? 'الوقت' : to12h(formTime),
                    style: const TextStyle(fontSize: 11.5)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // ── المدة (دقائق) — حقلٌ رقمي اختياري، الافتراضي 30 عند الفراغ ──
          TextField(
            key: const Key('appt-duration'),
            controller: durationCtl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
                isDense: true,
                labelText: 'المدة (دقائق)',
                hintText: 'افتراضي 30'),
          ),
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
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton(
                key: const Key('appt-save'),
                style: FilledButton.styleFrom(
                    backgroundColor: BrandColors.gold,
                    foregroundColor: BrandColors.brand900),
                onPressed: _saveAppt,
                child: Text(editingId != null ? 'تحديث' : 'حفظ الموعد',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('appt-cancel'),
              onPressed: () => setState(() => showForm = false),
              child: const Text('إلغاء', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ],
      ),
    );
  }

  // ── بطاقة موعد اليوم ──
  Widget _apptCard(
      JMap a, List<JMap> debts, String centerName, String currency) {
    final id = '${a['id']}';
    final status = '${a['status'] ?? 'pending'}';
    final completed = status == 'completed';
    final cancelled = status == 'cancelled';
    final isAppt = a['_src'] == 'appt';
    final phone = cleanPhone(a['phone']);
    // م-عزل الهوية — دين هوية صاحب الموعد (هاتفه) لا كل من يحمل الاسم.
    final debt = getPatientDebt(debts, '${a['name'] ?? ''}', phone: a['phone']);

    return Opacity(
      opacity: completed ? .7 : 1,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: InkWell(
                            key: Key('appt-patient-$id'),
                            onTap: () => _goPatient('${a['name'] ?? ''}'),
                            child: Text('${a['name'] ?? '—'}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: BrandColors.brand700)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          completed
                              ? '✓ تم'
                              : cancelled
                                  ? '✕ ملغي'
                                  : '⏱ قادم',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: completed
                                ? const Color(0xFF22C55E)
                                : cancelled
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFF15604A),
                          ),
                        ),
                      ]),
                      Text(
                        '🦷 ${jsOr(a['service'], '—')}'
                        '${jsTruthy(a['time']) ? ' · 🕐 ${to12h('${a['time']}')}' : ''}',
                        style: TextStyle(
                            fontSize: 11.5, color: BrandColors.mut),
                      ),
                      if ('${a['notes'] ?? ''}'.isNotEmpty)
                        Text('✎ ${a['notes']}',
                            style: TextStyle(
                                fontSize: 11, color: BrandColors.mut2)),
                    ],
                  ),
                ),
                if (!completed)
                  IconButton(
                    key: Key('appt-done-$id'),
                    tooltip: 'تم',
                    visualDensity: VisualDensity.compact,
                    onPressed: isAppt ? () => _markDone(id) : null,
                    icon: const Icon(Icons.check_rounded,
                        size: 17, color: Color(0xFF22C55E)),
                  )
                else
                  IconButton(
                    key: Key('appt-undone-$id'),
                    tooltip: 'إلغاء تم',
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        isAppt ? () => _markDone(id, done: false) : null,
                    icon: const Icon(Icons.replay_rounded,
                        size: 17, color: Color(0xFFF59E0B)),
                  ),
                if (isAppt)
                  IconButton(
                    key: Key('appt-edit-$id'),
                    tooltip: 'تعديل',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _resetForm();
                      editingId = id;
                      nameCtl.text = '${a['name'] ?? ''}';
                      phoneCtl.text = '${a['phone'] ?? ''}';
                      serviceCtl.text = '${a['service'] ?? ''}';
                      notesCtl.text = '${a['notes'] ?? ''}';
                      final dur = jsNumOr0(a['durationMin']).toInt();
                      durationCtl.text = dur > 0 ? '$dur' : '';
                      formDate = '${a['date'] ?? ''}';
                      formTime = '${a['time'] ?? ''}';
                      showForm = true;
                    }),
                    icon: Icon(Icons.edit_rounded,
                        size: 15, color: BrandColors.brandIcon),
                  ),
                // نسخ الموعد — يفتح نموذج الإضافة مسبق التعبئة بكل البيانات
                // (اسم/هاتف/خدمة/ملاحظات/مدة) بتاريخ اليوم المحدد ووقتٍ فارغ.
                // المكافئ الهاتفي لنسخ المكتب؛ النقل بين الأيام مكافئه تعديلُ
                // التاريخ الموجود أصلاً فلا حاجة لبندٍ إضافي.
                if (isAppt)
                  IconButton(
                    key: Key('appt-copy-$id'),
                    tooltip: 'نسخ الموعد',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _resetForm();
                      editingId = null; // صفٌّ جديد عند الحفظ.
                      nameCtl.text = '${a['name'] ?? ''}';
                      phoneCtl.text = '${a['phone'] ?? ''}';
                      serviceCtl.text = '${a['service'] ?? ''}';
                      notesCtl.text = '${a['notes'] ?? ''}';
                      final dur = jsNumOr0(a['durationMin']).toInt();
                      durationCtl.text = dur > 0 ? '$dur' : '';
                      formDate = selectedDay ?? '${a['date'] ?? ''}';
                      formTime = ''; // وقتٌ فارغ ليختار الطبيب.
                      showForm = true;
                    }),
                    icon: Icon(Icons.copy_rounded,
                        size: 15, color: BrandColors.brandIcon),
                  ),
                if (isAppt)
                  IconButton(
                    key: Key('appt-del-$id'),
                    tooltip: 'حذف',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _deleteAppt(a),
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 16, color: BrandColors.red),
                  ),
              ],
            ),
            if (phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
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
              ),
          ],
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .3)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color)),
      ),
    );
  }
}
