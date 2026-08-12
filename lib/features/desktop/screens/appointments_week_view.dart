/// ============================================================================
///  المواعيد — الجدولة الأسبوعية المكتبية (Weekly Scheduler)
/// ============================================================================
///
///  عرضٌ مكتبيٌّ خالص للمواعيد التقليدية على هيئة تقويمٍ أسبوعيٍّ زمني —
///  المكافئ المكتبي لجدولة العيادات الاحترافية. **بلا أي مساسٍ بمنطق الحجز
///  أو قاعدة البيانات أو المزامنة**: كل كتابة تمرّ عبر الدوال المشتركة
///  المرفوعة في [DesktopAppointmentsScreen] (المُمرَّرة هنا في [ApptActions])،
///  وهي بدورها توائم حرفية لمسارات الهاتف في appointments_tab.dart.
///
///  البنية (بلا حزم — Stack+Positioned داخل SingleChildScrollView رأسي واحد):
///   • رأس أيامٍ أعلى: السبت→الجمعة (عربي) + التاريخ، اليوم مبرزٌ ذهبياً.
///   • عمود ساعاتٍ يمين (RTL) من إعداد ساعات الدوام (workdayStart/workdayEnd)
///     بارتفاع ساعةٍ 64px وخطوط نصف ساعةٍ باهتة عبر CustomPaint.
///   • شريطٌ علويٌّ «بلا وقت» للمواعيد بلا time أو خارج مدى الدوام (لا موعد
///     يختفي).
///   • خط «الآن» أحمر على عمود اليوم الحالي (Timer.periodic دقيقة، يُلغى في
///     dispose).
///   • تنقّل أسابيع (السابق/التالي/اليوم) + عنوان مدى الأسبوع.
///
///  مصدر البيانات: repos.appointments.getByDateRange(weekStart, weekEnd) —
///  صفوف المواعيد الحقيقية القابلة للتحرير فقط (لا صفوف السجلات/التركيبات
///  المقروءة، فهي غير قابلة للنقل/التحرير هنا).
///
///  التفاعلات: نقرة = popover تفاصيل بكل إجراءات الهاتف؛ نقر مزدوج = تعديل؛
///  سحب = نقل (شبحٌ فقط أثناء السحب، الكتابة عند الإفلات)؛ Ctrl+سحب = نسخ؛
///  سحب الحافة السفلية = ضبط المدة (durationMin)؛ نقر خانةٍ فارغة = موعدٌ
///  جديدٌ بتاريخ/وقتٍ مسبقين.
library;

import 'dart:async' show Timer;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyEvent, LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart' show appConfigProvider, reposProvider;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/js_compat.dart';
import '../../appointments/appointments_logic.dart'
    show
        JMap,
        buildApptMap, // م169/ج — توحيد مصدر الجدول مع القائمة
        cleanPhone,
        debtSmsText,
        debtWaText,
        getPatientDebt,
        smsReminderText,
        to12h,
        waReminderText;
import '../../appointments/appt_lifecycle.dart'
    show apptStatusColor, filterByClinic, normApptStatus;
import '../../appointments/appointments_tab.dart'
    show apptGoDayProvider, apptRevProvider;
import '../../patients/patients_tab.dart' show patientsRevProvider;
import '../desktop_prefs.dart'
    show desktopPrefsProvider, saveDesktopPref;

// ── ثوابت التخطيط ───────────────────────────────────────────────────────────

/// ارتفاع الساعة الافتراضي بالبكسل (عقد التصميم).
const double _kHourHDefault = 64;

/// م166 — ارتفاع الساعة الحي: يتغير بـ Ctrl+عجلة الفأرة (40–160) ويُحفظ
/// في تفضيلات الجهاز. متغير مكتبةٍ خاص: جدولة واحدة معروضة في أي لحظة
/// (عادية أو ملء شاشة)، وإعادة البناء بعد كل تغيير تعيد قراءة القيمة
/// في كل الأبناء (عمود الساعات وأعمدة الأيام).
double _kHourH = _kHourHDefault;

/// مفتاح تفضيل مقياس الجدول.
const _kHourHKey = 'appt.hourH';

/// عرض عمود الساعات على اليمين.
const double _kTimeColW = 56;

/// أدنى ارتفاعٍ لبطاقة الموعد (عقد التصميم: 22px).
const double _kMinCardH = 22;

/// مدة الموعد الافتراضية عند غياب durationMin (عقد التصميم: 30 دقيقة).
const int _kDefaultDuration = 30;

/// تقطيع السحب/تغيير الحجم (snap) بالدقائق.
const int _kSnapMin = 15;

/// أسماء الأيام العربية مرتّبةً من السبت (بداية الأسبوع في العقد).
const _weekdayNamesSat = ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء',
    'الأربعاء', 'الخميس', 'الجمعة'];

/// عقد الإجراءات المشتركة — تُمرَّرها الشاشة الأم فتستدعي الجدولة نفس
/// مسارات الكتابة الحرفية (لا تكرار منطقٍ ولا كتابة مباشرة من هنا للمستودع
/// إلا القراءة).
class ApptActions {
  const ApptActions({
    required this.openForm,
    required this.move,
    required this.copy,
    required this.setDuration,
    required this.cancelOne,
    required this.markDone,
    required this.deleteOne,
    required this.launch,
    required this.openSeriesList,
    required this.centerName,
    required this.currency,
  });

  /// فتح نموذج موعد (تعديل، أو جديد بتاريخ/وقتٍ مسبقين، أو نسخةٌ عبر
  /// [prefill] = حقولٌ ميدانية لموعدٍ جديد).
  final void Function({
    JMap? editing,
    String? defaultDate,
    String? defaultTime,
    JMap? prefill,
  }) openForm;

  /// نقل موعد (upsertLocal بدمجٍ ثلاثي عبر base).
  final void Function(JMap prev, {required String date, required String time})
      move;

  /// نسخ موعد (معرّفٌ جديد، حقولٌ ميدانية فقط، بلا base).
  final void Function(JMap src, {required String date, required String time})
      copy;

  /// ضبط مدة موعد (durationMin) بدمجٍ ثلاثي.
  final void Function(JMap prev, int durationMin) setDuration;

  /// إلغاء موعد (status=cancelled).
  final void Function(String id) cancelOne;

  /// إتمام/تراجع (status=completed/upcoming).
  final void Function(String id, {bool done}) markDone;

  /// حذف نهائي (confirmDelete ثم delete).
  final Future<void> Function(JMap a) deleteOne;

  /// فتح رابط خارجي (tel/wa/sms).
  final Future<void> Function(String url) launch;

  /// «عرض السلسلة»: يبدّل لعرض القائمة على مجموعة الدورية.
  final void Function(String group) openSeriesList;

  final String centerName;
  final String currency;
}

// ── الودجة الرئيسية ─────────────────────────────────────────────────────────

class WeeklyScheduler extends ConsumerStatefulWidget {
  const WeeklyScheduler(
      {super.key, required this.actions, this.clinicFilter = ''});

  final ApptActions actions;

  /// م164 — تبويب العيادة: يفلتر صفوف الأسبوع ('' = الكل).
  final String clinicFilter;

  @override
  ConsumerState<WeeklyScheduler> createState() => _WeeklySchedulerState();
}

class _WeeklySchedulerState extends ConsumerState<WeeklyScheduler> {
  /// بداية الأسبوع المعروض (سبتٌ، منتصف الليل).
  late DateTime _weekStart;

  /// مؤقّت تحديث خط «الآن» كل دقيقة.
  Timer? _nowTimer;

  /// لحظة «الآن» المعاد رسمها دورياً.
  DateTime _now = DateTime.now();

  /// م166 — Ctrl مضغوطاً؟ (يوقف سكرول الشبكة ليصير العجلةُ تكبيراً).
  bool _ctrlDown = false;

  bool _onKey(KeyEvent e) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (ctrl != _ctrlDown && mounted) setState(() => _ctrlDown = ctrl);
    return false; // لا نستهلك الحدث.
  }

  @override
  void initState() {
    super.initState();
    // م169 — أسبوعٌ متدحرج يبدأ من اليوم: اليومُ أولُ عمودٍ على اليمين
    // دائماً (كان يبدأ من سبت الأسبوع)، والتنقل للخلف يبقى للعرض فقط.
    _weekStart = _todayMidnight();
    // م171 — يوم هبوطٍ من مربع مواعيد بطاقة المريض: الأسبوع يبدأ منه
    // («النقر يأخذني ليوم الحجز»). القراءة هنا وتصفيرُ المزود بعد الإطار
    // (تعديله أثناء initState يرمي «modify provider while building»).
    final go = ref.read(apptGoDayProvider);
    if (go.isNotEmpty) {
      final d = DateTime.tryParse(go);
      if (d != null) _weekStart = DateTime(d.year, d.month, d.day);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(apptGoDayProvider.notifier).state = '';
      });
    }
    // م166 — استرجاع مقياس الجدول المحفوظ (40–160).
    final saved = double.tryParse(
        '${ref.read(desktopPrefsProvider)[_kHourHKey] ?? ''}');
    if (saved != null) _kHourH = saved.clamp(40.0, 160.0);
    HardwareKeyboard.instance.addHandler(_onKey);
    // تحديث خط «الآن» كل دقيقة (يُلغى في dispose — لا مؤقتٌ معلّق).
    _nowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _nowTimer?.cancel();
    super.dispose();
  }

  /// م166 — تكبير/تصغير بخطوة ~10% مع حفظ التفضيل.
  void _zoom(double factor) {
    setState(() {
      _kHourH = (_kHourH * factor).clamp(40.0, 160.0);
    });
    saveDesktopPref(ref, _kHourHKey, '$_kHourH', immediate: true);
  }

  /// م169 — منتصف ليل اليوم: بداية الأسبوع المتدحرج (بدل سبت الأسبوع).
  static DateTime _todayMidnight() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// (ساعة البداية, ساعة النهاية) من إعداد ساعات الدوام. تُقصُّ إلى نطاقٍ
  /// صالحٍ: البداية 0..23، النهاية > البداية وحتى 24.
  ({int start, int end}) _workHours() {
    final cfg = ref.read(appConfigProvider);
    final s = _hourOf('${jsOr(cfg['workdayStart'], '09:00')}', 9);
    var e = _hourOf('${jsOr(cfg['workdayEnd'], '21:00')}', 21);
    // إن كانت النهاية دقائقها > 0 نصعد للساعة التالية كي يظهر آخر خانة كاملة.
    final endMin = _minuteOf('${jsOr(cfg['workdayEnd'], '21:00')}');
    if (endMin > 0) e += 1;
    if (e <= s) e = s + 1;
    if (e > 24) e = 24;
    return (start: s.clamp(0, 23), end: e.clamp(1, 24));
  }

  static int _hourOf(String hhmm, int fallback) {
    final parts = hhmm.split(':');
    if (parts.isEmpty) return fallback;
    return int.tryParse(parts[0].trim()) ?? fallback;
  }

  static int _minuteOf(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return 0;
    return int.tryParse(parts[1].trim()) ?? 0;
  }

  /// دقائق منتصف الليل لوقتٍ "HH:mm" (أو null إن غاب/تعذّر).
  static int? _timeToMinutes(Object? t) {
    final s = '${t ?? ''}'.trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  /// "HH:mm" من دقائق منتصف الليل (مقصوصةً إلى يومٍ واحد).
  static String _minutesToTime(int mins) {
    final c = mins.clamp(0, 23 * 60 + 59);
    final h = c ~/ 60;
    final m = c % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  int _durationOf(JMap a) {
    final d = jsNumOr0(a['durationMin']).toInt();
    return d > 0 ? d : _kDefaultDuration;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(apptRevProvider);
    ref.watch(patientsRevProvider);

    final wh = _workHours();
    final startHour = wh.start;
    final endHour = wh.end;
    final hours = endHour - startHour;
    final gridHeight = hours * _kHourH;

    final days = [for (var i = 0; i < 7; i++) _weekStart.add(Duration(days: i))];
    final weekEnd = days.last;
    final todayStr = getCurrentDate();

    // م169/ج — الجدول والقائمة أساسٌ واحد بطريقتَي عرض (قرار المالك):
    // المصدر الموحد buildApptMap نفسه — صفوف المستودع الحقيقية القابلة
    // للتحرير + الحجوزات المشتقة من السجلات/التركيبات (حقل appointment —
    // تظهر بلا وقتٍ في شريط «بلا وقت» وتُدار من ملف المريض، عرضٌ فقط).
    // م164 — تبويب العيادة يفلتر الجدولة أيضاً (توأم فلترة القائمة).
    final weekRepos = ref.watch(reposProvider);
    final mergedMap = buildApptMap(
      appointments: weekRepos.appointments
          .getByDateRange(_ymd(_weekStart), _ymd(weekEnd)),
      records: weekRepos.records.getAll(),
      prosthetics: weekRepos.prosthetics.getAll(),
    );
    // الصفوف الحقيقية تُجرَّد من علامة _src العارضة قبل بلوغ مسارات
    // الكتابة (upsertLocal ينشر الخريطة كاملة)؛ المشتقة تُبقيها كوسم
    // «عرضٌ فقط» يفحصه _showDetails.
    final rows = [
      for (final r in filterByClinic(
        [
          for (final day in days) ...(mergedMap[_ymd(day)] ?? const <JMap>[]),
        ],
        widget.clinicFilter,
      ))
        if (r['_src'] == 'rec') r else ({...r}..remove('_src')),
    ];

    final byDay = <String, List<JMap>>{};
    final noTime = <JMap>[]; // بلا وقتٍ أو خارج مدى الدوام.
    for (final r in rows) {
      final d = '${r['date'] ?? ''}';
      if (d.isEmpty) continue;
      final mins = _timeToMinutes(r['time']);
      final within = mins != null &&
          mins >= startHour * 60 &&
          mins < endHour * 60;
      if (within) {
        (byDay[d] ??= []).add(r);
      } else {
        noTime.add(r);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeekNav(
          weekStart: _weekStart,
          weekEnd: weekEnd,
          onPrev: () => setState(() =>
              _weekStart = _weekStart.subtract(const Duration(days: 7))),
          onNext: () => setState(() =>
              _weekStart = _weekStart.add(const Duration(days: 7))),
          // م169 — «اليوم» يعيد الأسبوع المتدحرج (اليوم أول الأعمدة).
          onToday: () => setState(() => _weekStart = _todayMidnight()),
          // م166 — مؤشر المقياس وزر العودة لـ 100% (Ctrl+عجلة للتغيير).
          zoomPct: (_kHourH / _kHourHDefault * 100).round(),
          onResetZoom: () {
            setState(() => _kHourH = _kHourHDefault);
            saveDesktopPref(ref, _kHourHKey, '$_kHourHDefault',
                immediate: true);
          },
        ),
        _DayHeaderRow(days: days, todayStr: todayStr),
        if (noTime.isNotEmpty)
          _NoTimeBar(
            rows: noTime,
            onTap: (a) => _showDetails(a),
          ),
        Expanded(
          // م166 — Ctrl+عجلة = تكبير/تصغير (السكرول العادي بلا Ctrl).
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent &&
                  HardwareKeyboard.instance.isControlPressed) {
                _zoom(e.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1);
              }
            },
            child: SingleChildScrollView(
            key: const Key('appt-week-scroll'),
            physics: _ctrlDown
                ? const NeverScrollableScrollPhysics()
                : null,
            child: SizedBox(
              height: gridHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // عمود الساعات على اليمين (بداية RTL).
                  _HourColumn(startHour: startHour, endHour: endHour),
                  // أعمدة الأيام.
                  for (final day in days)
                    Expanded(
                      child: RepaintBoundary(
                        child: _DayColumn(
                          day: day,
                          dayStr: _ymd(day),
                          isToday: _ymd(day) == todayStr,
                          // م169 — الأيام السابقة تُعرض مبهتة (عرضٌ فقط).
                          isPast: _ymd(day).compareTo(todayStr) < 0,
                          startHour: startHour,
                          endHour: endHour,
                          now: _now,
                          rows: byDay[_ymd(day)] ?? const [],
                          durationOf: _durationOf,
                          timeToMinutes: _timeToMinutes,
                          minutesToTime: _minutesToTime,
                          // م169 — قفل الإنشاء في الأيام السابقة: الماضي
                          // للعرض فقط (يبقى مبهتاً)، ورسالة عند المحاولة.
                          onEmptyTap: (mins) {
                            if (_ymd(day).compareTo(todayStr) < 0) {
                              _pastDaySnack();
                              return;
                            }
                            widget.actions.openForm(
                              defaultDate: _ymd(day),
                              defaultTime: _minutesToTime(mins),
                            );
                          },
                          onTapCard: _showDetails,
                          onDoubleTapCard: (a) =>
                              widget.actions.openForm(editing: a),
                          // م169 — الأيام السابقة للعرض فقط: لا نقل ولا
                          // نسخ ولا تغيير مدة على موعدٍ في يومٍ ماضٍ.
                          onMove: (a, newDayStr, newMins) {
                            if (newDayStr.compareTo(todayStr) < 0) {
                              _pastDaySnack();
                              return;
                            }
                            widget.actions.move(a,
                                date: newDayStr,
                                time: _minutesToTime(newMins));
                          },
                          onCopy: (a, newDayStr, newMins) {
                            if (newDayStr.compareTo(todayStr) < 0) {
                              _pastDaySnack();
                              return;
                            }
                            widget.actions.copy(a,
                                date: newDayStr,
                                time: _minutesToTime(newMins));
                          },
                          onResize: (a, newDuration) {
                            if (_ymd(day).compareTo(todayStr) < 0) {
                              _pastDaySnack();
                              return;
                            }
                            widget.actions.setDuration(a, newDuration);
                          },
                          weekStart: _weekStart,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ),
        ),
      ],
    );
  }

  /// م169 — رسالة قفل الأيام السابقة الموحدة.
  void _pastDaySnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('الأيام السابقة للعرض فقط — لا إضافة ولا تعديل مواعيد فيها')),
    );
  }

  // ── popover التفاصيل ──
  void _showDetails(JMap a) {
    // م169/ج — الصف المشتق من سجل زيارةٍ (rec) عرضٌ فقط هنا: لا إجراءات
    // موعدٍ عليه — يُدار من ملف المريض نفسه (توأم وسمه بالهاتف).
    if (a['_src'] == 'rec') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'حجزٌ من سجل الزيارة («${a['name']}») — يُدار من ملف المريض')));
      return;
    }
    final repos = ref.read(reposProvider);
    final debts = repos.debts.getAll();
    showDialog<void>(
      context: context,
      barrierColor: const Color.fromRGBO(10, 48, 36, .45),
      builder: (ctx) => _DetailsDialog(
        row: a,
        actions: widget.actions,
        // م-عزل الهوية — دين هوية صاحب الموعد (هاتفه) لا سميّه.
        debt: getPatientDebt(debts, '${a['name'] ?? ''}', phone: a['phone']),
      ),
    );
  }
}

// ── تنقّل الأسابيع ───────────────────────────────────────────────────────────

class _WeekNav extends StatelessWidget {
  const _WeekNav({
    required this.weekStart,
    required this.weekEnd,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.zoomPct,
    required this.onResetZoom,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  /// م166 — مقياس الجدول (100 = الافتراضي) وزر العودة إليه.
  final int zoomPct;
  final VoidCallback onResetZoom;

  String _range() {
    String d(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}';
    return '${d(weekStart)} — ${d(weekEnd)} / ${weekEnd.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: BrandColors.surface,
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      child: Row(children: [
        // في RTL: «السابق» يمينٌ بأيقونة chevron_right.
        IconButton(
          key: const Key('appt-week-prev'),
          visualDensity: VisualDensity.compact,
          tooltip: 'الأسبوع السابق',
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_right_rounded, size: 22),
        ),
        OutlinedButton.icon(
          key: const Key('appt-week-today'),
          style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: BrandColors.brand700),
          onPressed: onToday,
          icon: const Icon(Icons.today_rounded, size: 15),
          label: const Text('اليوم', style: TextStyle(fontSize: 11.5)),
        ),
        IconButton(
          key: const Key('appt-week-next'),
          visualDensity: VisualDensity.compact,
          tooltip: 'الأسبوع التالي',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_left_rounded, size: 22),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _range(),
            key: const Key('appt-week-range'),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: BrandColors.brand700),
          ),
        ),
        const SizedBox(width: 8),
        // م166 — شارة المقياس: تظهر عند غير 100% ونقرها يعيد الضبط
        // (التغيير بـ Ctrl + عجلة الفأرة).
        if (zoomPct != 100)
          Tooltip(
            message: 'المقياس $zoomPct% — انقر للعودة إلى 100%\n(Ctrl + عجلة الفأرة للتكبير/التصغير)',
            child: InkWell(
              key: const Key('appt-week-zoom-reset'),
              borderRadius: BorderRadius.circular(12),
              onTap: onResetZoom,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: BrandColors.gold.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: BrandColors.gold.withValues(alpha: .4)),
                ),
                child: Text('$zoomPct% ⟲',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.goldDark)),
              ),
            ),
          )
        else
          // موازنة بصرية لعرض الأزرار على اليسار.
          const SizedBox(width: 40),
      ]),
    );
  }
}

// ── رأس الأيام ───────────────────────────────────────────────────────────────

class _DayHeaderRow extends StatelessWidget {
  const _DayHeaderRow({required this.days, required this.todayStr});

  final List<DateTime> days;
  final String todayStr;

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border(bottom: BorderSide(color: BrandColors.line)),
      ),
      child: Row(children: [
        // ركن عمود الساعات (فارغ).
        const SizedBox(width: _kTimeColW, height: 46),
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: _DayHeaderCell(
              name: _weekdayNamesSat[i],
              day: days[i],
              isToday: _ymd(days[i]) == todayStr,
            ),
          ),
      ]),
    );
  }
}

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({
    required this.name,
    required this.day,
    required this.isToday,
  });

  final String name;
  final DateTime day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isToday ? BrandColors.gold.withValues(alpha: .14) : null,
        border: Border(
          right: BorderSide(color: BrandColors.line, width: .6),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: isToday ? BrandColors.goldDark : BrandColors.brand700,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isToday ? BrandColors.goldDark : BrandColors.mut2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── شريط «بلا وقت» ───────────────────────────────────────────────────────────

class _NoTimeBar extends StatelessWidget {
  const _NoTimeBar({required this.rows, required this.onTap});

  final List<JMap> rows;
  final void Function(JMap) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('appt-week-notime'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BrandColors.surface2,
        border: Border(bottom: BorderSide(color: BrandColors.line)),
      ),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text('بلا وقت',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: BrandColors.mut)),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final a in rows)
                InkWell(
                  key: Key('appt-week-notime-${a['id']}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onTap(a),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor('${a['status'] ?? 'pending'}')
                          .withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _statusColor('${a['status'] ?? 'pending'}')
                              .withValues(alpha: .3)),
                    ),
                    child: Text(
                      '${a['name'] ?? '—'}'
                      '${'${a['date'] ?? ''}'.isNotEmpty ? ' · ${a['date']}' : ''}',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: BrandColors.ink),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── عمود الساعات ─────────────────────────────────────────────────────────────

class _HourColumn extends StatelessWidget {
  const _HourColumn({required this.startHour, required this.endHour});

  final int startHour;
  final int endHour;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kTimeColW,
      child: Column(
        children: [
          for (var h = startHour; h < endHour; h++)
            SizedBox(
              height: _kHourH,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    to12h('${h.toString().padLeft(2, '0')}:00'),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: BrandColors.mut2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── عمود يومٍ واحد (الشبكة + البطاقات + خط الآن) ─────────────────────────────

class _DayColumn extends StatefulWidget {
  const _DayColumn({
    required this.day,
    required this.dayStr,
    required this.isToday,
    this.isPast = false, // م169 — يومٌ سابق: عرضٌ مبهت فقط.
    required this.startHour,
    required this.endHour,
    required this.now,
    required this.rows,
    required this.durationOf,
    required this.timeToMinutes,
    required this.minutesToTime,
    required this.onEmptyTap,
    required this.onTapCard,
    required this.onDoubleTapCard,
    required this.onMove,
    required this.onCopy,
    required this.onResize,
    required this.weekStart,
  });

  final DateTime day;
  final String dayStr;
  final bool isToday;

  /// م169 — الأيام السابقة تظهر مبهتةً (الإنشاء/التعديل محجوبان أعلى).
  final bool isPast;
  final int startHour;
  final int endHour;
  final DateTime now;
  final List<JMap> rows;
  final int Function(JMap) durationOf;
  final int? Function(Object?) timeToMinutes;
  final String Function(int) minutesToTime;

  /// نقر خانةٍ فارغة (دقائق منتصف الليل، مقطّعة).
  final void Function(int mins) onEmptyTap;
  final void Function(JMap) onTapCard;
  final void Function(JMap) onDoubleTapCard;

  /// نقل: (الموعد, تاريخ اليوم الجديد, دقائق البداية الجديدة).
  final void Function(JMap a, String newDayStr, int newMins) onMove;

  /// نسخ (Ctrl+سحب).
  final void Function(JMap a, String newDayStr, int newMins) onCopy;

  /// تغيير المدة (دقائق).
  final void Function(JMap a, int newDuration) onResize;

  final DateTime weekStart;

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

class _DayColumnState extends State<_DayColumn> {
  // حالة السحب/التغيير المحلية — تحرّك الشبح فقط بلا كتابةٍ حتى الإفلات.

  /// معرّف الموعد الجاري سحبه (شبحاً)، أو null.
  String? _dragId;

  /// إزاحة الشبح الرأسية الحالية (بكسل من أعلى العمود).
  double _ghostTop = 0;

  /// هندسة الشبح (يسار/عرض/ارتفاع/لون) — تُلتقط عند بدء السحب.
  double _ghostLeft = 0;
  double _ghostW = 0;
  double _ghostH = 0;
  Color _ghostColor = const Color(0xFF15604A);

  /// معاينة مدة تغيير الحجم (بكسل)، أو null.
  double? _resizeH;
  String? _resizeId;

  double get _minutePx => _kHourH / 60.0;

  /// دقائق البداية النسبية لأعلى الشبكة (منتصف الليل - startHour*60).
  int _topToMinutes(double top) {
    final mins = widget.startHour * 60 + (top / _minutePx).round();
    // تقطيع 15 دقيقة.
    final snapped = (mins / _kSnapMin).round() * _kSnapMin;
    return snapped;
  }

  double _minutesToTop(int mins) =>
      (mins - widget.startHour * 60) * _minutePx;

  @override
  Widget build(BuildContext context) {
    final gridMinutes = (widget.endHour - widget.startHour) * 60;
    final height = (widget.endHour - widget.startHour) * _kHourH;

    // تخطيط العناقيد المتراكبة (memoized على مدخلات هذا البناء).
    final layout = _WeekLayout.compute(
      rows: widget.rows,
      timeToMinutes: widget.timeToMinutes,
      durationOf: widget.durationOf,
    );

    return LayoutBuilder(builder: (context, constraints) {
      final colWidth = constraints.maxWidth;

      return Container(
        decoration: BoxDecoration(
          // م169 — الأيام السابقة مبهتة بطبقةٍ حبرية خفيفة (عرضٌ فقط).
          color: widget.isPast
              ? BrandColors.ink.withValues(alpha: .05)
              : widget.isToday
                  ? BrandColors.gold.withValues(alpha: .04)
                  : null,
          border: Border(
            right: BorderSide(color: BrandColors.line, width: .6),
          ),
        ),
        child: Stack(
          children: [
            // شبكة الخلفية: خطوط الساعات + خطوط نصف الساعة الباهتة.
            Positioned.fill(
              child: CustomPaint(
                painter: _GridPainter(
                  hours: widget.endHour - widget.startHour,
                ),
              ),
            ),
            // طبقة النقر على الخانات الفارغة (خلف البطاقات).
            Positioned.fill(
              child: GestureDetector(
                key: Key('appt-week-empty-${widget.dayStr}'),
                behavior: HitTestBehavior.translucent,
                onTapUp: (d) {
                  final mins = _topToMinutes(d.localPosition.dy);
                  widget.onEmptyTap(mins.clamp(
                      widget.startHour * 60, widget.endHour * 60 - _kSnapMin));
                },
              ),
            ),
            // البطاقات.
            for (final item in layout)
              _buildCard(item, colWidth, gridMinutes, height),
            // شبح السحب — يتحرّك وحده أثناء السحب بلا إعادة بناءٍ للشبكة.
            if (_dragId != null) _dragGhost(),
            // خط «الآن» على اليوم الحالي فقط، ضمن مدى الدوام.
            if (widget.isToday) ..._nowLine(),
          ],
        ),
      );
    });
  }

  /// شبح السحب: مستطيلٌ شفافٌ متقطّعُ الحدّ عند الموضع الجاري + شارة الوقت
  /// المقترح. لا يلتقط اللمس (IgnorePointer).
  Widget _dragGhost() {
    final newMins = _topToMinutes(_ghostTop).clamp(
        widget.startHour * 60, widget.endHour * 60 - _kSnapMin);
    return Positioned(
      top: _ghostTop,
      left: _ghostLeft,
      width: _ghostW,
      height: _ghostH,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: _ghostColor.withValues(alpha: .22),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _ghostColor, width: 1.4),
          ),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              widget.minutesToTime(newMins),
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: _ghostColor),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _nowLine() {
    final nowMins = widget.now.hour * 60 + widget.now.minute;
    if (nowMins < widget.startHour * 60 || nowMins >= widget.endHour * 60) {
      return const [];
    }
    final top = _minutesToTop(nowMins);
    return [
      Positioned(
        top: top - 1,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Row(children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFFEF4444),
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Container(
                key: const Key('appt-week-nowline'),
                height: 2,
                color: const Color(0xFFEF4444),
              ),
            ),
          ]),
        ),
      ),
    ];
  }

  Widget _buildCard(
      _LaidOut item, double colWidth, int gridMinutes, double gridHeight) {
    final a = item.row;
    final id = '${a['id']}';
    final mins = widget.timeToMinutes(a['time']) ?? widget.startHour * 60;
    final duration = widget.durationOf(a);

    final isDragging = _dragId == id;
    final isResizing = _resizeId == id;

    // الموضع الرأسي: البطاقة الحقيقية تبقى ثابتةً في مكانها أثناء السحب كي
    // لا ينزلق هدف اللمس من تحت المؤشّر — الحركة تُعرض عبر «شبحٍ» منفصل
    // (انظر _dragGhost). عند الإفلات فقط تُكتب القيمة الجديدة.
    final baseTop = _minutesToTop(mins);
    final top = baseTop;

    // الارتفاع: أثناء تغيير الحجم نتبع المعاينة، وإلا من المدة (بحدٍّ أدنى).
    final rawH = duration * _minutePx;
    final height =
        (isResizing ? (_resizeH ?? rawH) : rawH).clamp(_kMinCardH, gridHeight);

    // القص البصري إن تجاوز الموعد نهاية الدوام.
    final overflow = (top + height) > gridHeight;

    // الأعمدة الفرعية للتراكب.
    final subW = colWidth / item.numCols;
    final left = item.col * subW;

    return Positioned(
      top: top,
      // في RTL يبقى left/right منطقياً؛ نستخدم left البصري داخل العمود.
      left: left,
      width: subW,
      height: height,
      child: _ApptCardWidget(
        key: Key('appt-week-card-$id'),
        row: a,
        heightPx: height,
        durationMin: duration,
        overflow: overflow,
        // م169 — بطاقات الأيام السابقة مبهتة (عرضٌ فقط).
        dimmed: isDragging || widget.isPast,
        onTap: () => widget.onTapCard(a),
        onDoubleTap: () => widget.onDoubleTapCard(a),
        onDragStart: () {
          setState(() {
            _dragId = id;
            _ghostTop = baseTop;
            _ghostLeft = left;
            _ghostW = subW;
            _ghostH = height;
            _ghostColor = _statusColor('${a['status'] ?? 'pending'}');
          });
        },
        onDragUpdate: (dy) {
          setState(() {
            _ghostTop = (_ghostTop + dy)
                .clamp(0.0, gridHeight - _kMinCardH);
          });
        },
        onDragEnd: () {
          final newMins = _topToMinutes(_ghostTop).clamp(
              widget.startHour * 60, widget.endHour * 60 - _kSnapMin);
          final ctrl = HardwareKeyboard.instance.logicalKeysPressed.any(
              (k) =>
                  k == LogicalKeyboardKey.controlLeft ||
                  k == LogicalKeyboardKey.controlRight);
          final movedId = _dragId;
          setState(() {
            _dragId = null;
          });
          if (movedId == null) return;
          // النقل/النسخ داخل نفس اليوم (النقل عبر الأيام: تحرير التاريخ من
          // النموذج، وهو المكافئ المضمون بلا سحبٍ أفقيٍّ هشّ).
          if (ctrl) {
            widget.onCopy(a, widget.dayStr, newMins);
          } else {
            widget.onMove(a, widget.dayStr, newMins);
          }
        },
        onResizeStart: () {
          setState(() {
            _resizeId = id;
            _resizeH = rawH;
          });
        },
        onResizeUpdate: (dy) {
          setState(() {
            _resizeH = ((_resizeH ?? rawH) + dy).clamp(_kMinCardH, gridHeight);
          });
        },
        onResizeEnd: () {
          final h = _resizeH ?? rawH;
          // تحويل الارتفاع لدقائق مع تقطيع 15 وحدٍّ أدنى 15.
          var newDur = (h / _minutePx).round();
          newDur = (newDur / _kSnapMin).round() * _kSnapMin;
          if (newDur < _kSnapMin) newDur = _kSnapMin;
          final resizedId = _resizeId;
          setState(() {
            _resizeId = null;
            _resizeH = null;
          });
          if (resizedId == null) return;
          if (newDur != duration) widget.onResize(a, newDur);
        },
      ),
    );
  }
}

// ── تخطيط العناقيد المتراكبة ────────────────────────────────────────────────

/// موعدٌ بعد حساب عموده الفرعي.
class _LaidOut {
  _LaidOut(this.row, this.col, this.numCols);
  final JMap row;
  final int col;
  final int numCols;
}

/// خوارزمية تراكب: رتّب مواعيد اليوم بالبداية، جمّعها بالعناقيد المتراكبة،
/// أعطِ كل موعدٍ أقصى عمودٍ فرعيٍّ حر، والعرض = 1/numCols لكل العنقود.
class _WeekLayout {
  static List<_LaidOut> compute({
    required List<JMap> rows,
    required int? Function(Object?) timeToMinutes,
    required int Function(JMap) durationOf,
  }) {
    if (rows.isEmpty) return const [];

    // (row, start, end).
    final items = <({JMap row, int start, int end})>[];
    for (final r in rows) {
      final s = timeToMinutes(r['time']);
      if (s == null) continue;
      final e = s + durationOf(r);
      items.add((row: r, start: s, end: e));
    }
    items.sort((a, b) {
      if (a.start != b.start) return a.start.compareTo(b.start);
      return a.end.compareTo(b.end);
    });

    final out = <_LaidOut>[];
    // عنقودٌ = مجموعة مواعيد متصلة التراكب.
    var i = 0;
    while (i < items.length) {
      // ابنِ العنقود: وسّعه ما دام أيّ عنصرٍ يبدأ قبل أقصى نهايةٍ حتى الآن.
      var clusterEnd = items[i].end;
      var j = i + 1;
      final cluster = <({JMap row, int start, int end})>[items[i]];
      while (j < items.length && items[j].start < clusterEnd) {
        cluster.add(items[j]);
        if (items[j].end > clusterEnd) clusterEnd = items[j].end;
        j++;
      }
      // وزّع أعمدة العنقود: أول عمودٍ حرٍّ لكل موعد.
      final colEnds = <int>[]; // نهاية آخر موعدٍ في كل عمود.
      final assigned = <_LaidOut>[];
      for (final it in cluster) {
        var placed = false;
        for (var c = 0; c < colEnds.length; c++) {
          if (it.start >= colEnds[c]) {
            colEnds[c] = it.end;
            assigned.add(_LaidOut(it.row, c, 0));
            placed = true;
            break;
          }
        }
        if (!placed) {
          colEnds.add(it.end);
          assigned.add(_LaidOut(it.row, colEnds.length - 1, 0));
        }
      }
      final numCols = colEnds.length;
      for (final la in assigned) {
        out.add(_LaidOut(la.row, la.col, numCols));
      }
      i = j;
    }
    return out;
  }
}

// ── رسّام الشبكة (خطوط الساعات + نصف الساعة) ─────────────────────────────────

class _GridPainter extends CustomPainter {
  const _GridPainter({required this.hours});
  final int hours;

  @override
  void paint(Canvas canvas, Size size) {
    final hourPaint = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = .6;
    final halfPaint = Paint()
      ..color = const Color(0x11000000)
      ..strokeWidth = .5;
    for (var h = 0; h <= hours; h++) {
      final y = h * _kHourH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hourPaint);
      if (h < hours) {
        final yh = y + _kHourH / 2;
        canvas.drawLine(Offset(0, yh), Offset(size.width, yh), halfPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.hours != hours;
}

// ── لون الحالة (قيد مطلق #3) ────────────────────────────────────────────────

/// م164 — لون الحالة من الكتالوج الموحّد (8 حالات بألوان هادئة).
Color _statusColor(String status) => apptStatusColor(normApptStatus(status));

// ── بطاقة الموعد ─────────────────────────────────────────────────────────────

class _ApptCardWidget extends StatefulWidget {
  const _ApptCardWidget({
    super.key,
    required this.row,
    required this.heightPx,
    required this.durationMin,
    required this.overflow,
    required this.dimmed,
    required this.onTap,
    required this.onDoubleTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final JMap row;
  final double heightPx;
  final int durationMin;
  final bool overflow;
  final bool dimmed;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;
  final VoidCallback onDragStart;
  final void Function(double dy) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onResizeStart;
  final void Function(double dy) onResizeUpdate;
  final VoidCallback onResizeEnd;

  @override
  State<_ApptCardWidget> createState() => _ApptCardWidgetState();
}

class _ApptCardWidgetState extends State<_ApptCardWidget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.row;
    final status = '${a['status'] ?? 'pending'}';
    final completed = status == 'completed';
    final cancelled = status == 'cancelled';
    // م164 — الاستراحة ☕ بلونٍ كهرماني مميز (ليست مريضاً).
    final isBreak = jsTruthy(a['isBreak']);
    final color =
        isBreak ? const Color(0xFFB45309) : _statusColor(status);
    final time = '${a['time'] ?? ''}';
    final name = isBreak
        ? '☕ ${jsOr(a['name'], 'استراحة')}'
        : '${a['name'] ?? '—'}';
    final service = '${a['service'] ?? ''}'.trim();
    final isRecurring = '${a['repeatGroup'] ?? ''}'.isNotEmpty;
    final showService = widget.heightPx > 40 && service.isNotEmpty;

    final tooltip = StringBuffer()
      ..write(name)
      ..write(time.isNotEmpty ? '  ·  ${to12h(time)}' : '')
      ..write('  ·  ${widget.durationMin} د');
    if (service.isNotEmpty) tooltip.write('\n$service');

    Widget card = Opacity(
      opacity: (completed || cancelled) ? .65 : (widget.dimmed ? .4 : 1),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: .5),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: .30), width: .8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // شريط لونٍ جانبي 4px (بداية RTL = يمين المحتوى بصرياً).
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      if (time.isNotEmpty) ...[
                        Text(
                          to12h(time),
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: color),
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (isRecurring) ...[
                        Icon(Icons.repeat_rounded,
                            key: Key('appt-week-recur-${a['id']}'),
                            size: 10,
                            color: BrandColors.goldDark),
                        const SizedBox(width: 2),
                      ],
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: BrandColors.brandText),
                        ),
                      ),
                    ]),
                    if (showService)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          service,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          // م165ب — أغمق: كان فاتحاً تصعب قراءته.
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color:
                                  BrandColors.ink.withValues(alpha: .72)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // مؤشر القص إن تجاوز الدوام.
    if (widget.overflow) {
      card = Stack(children: [
        Positioned.fill(child: card),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0),
                    color.withValues(alpha: .5),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: tooltip.toString(),
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          // السحب الرأسي = نقل (شبح فقط؛ الكتابة عند الإفلات).
          onVerticalDragStart: (_) => widget.onDragStart(),
          onVerticalDragUpdate: (d) => widget.onDragUpdate(d.delta.dy),
          onVerticalDragEnd: (_) => widget.onDragEnd(),
          child: Stack(
            children: [
              Positioned.fill(child: card),
              // مقبض تغيير الحجم على الحافة السفلية (6px).
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 6,
                child: _ResizeHandle(
                  visible: _hovered,
                  color: _statusColor(status),
                  onStart: widget.onResizeStart,
                  onUpdate: widget.onResizeUpdate,
                  onEnd: widget.onResizeEnd,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── مقبض تغيير الحجم (الحافة السفلية) ────────────────────────────────────────

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.visible,
    required this.color,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final bool visible;
  final Color color;
  final VoidCallback onStart;
  final void Function(double dy) onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => onStart(),
        onVerticalDragUpdate: (d) => onUpdate(d.delta.dy),
        onVerticalDragEnd: (_) => onEnd(),
        child: Center(
          child: Container(
            width: 22,
            height: 3,
            decoration: BoxDecoration(
              color: visible ? color.withValues(alpha: .7) : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

// ── حوار التفاصيل (popover) — كل إجراءات الهاتف ───────────────────────────────

class _DetailsDialog extends StatelessWidget {
  const _DetailsDialog({
    required this.row,
    required this.actions,
    required this.debt,
  });

  final JMap row;
  final ApptActions actions;
  final num debt;

  @override
  Widget build(BuildContext context) {
    final a = row;
    final id = '${a['id']}';
    final name = '${a['name'] ?? '—'}';
    final phone = cleanPhone(a['phone']);
    final service = '${a['service'] ?? ''}'.trim();
    final date = '${a['date'] ?? ''}';
    final time = '${a['time'] ?? ''}';
    final notes = '${a['notes'] ?? ''}'.trim();
    final status = '${a['status'] ?? 'pending'}';
    final completed = status == 'completed';
    final cancelled = status == 'cancelled';
    final isRecurring = '${a['repeatGroup'] ?? ''}'.isNotEmpty;
    final duration = jsNumOr0(a['durationMin']).toInt();
    final durText = duration > 0 ? duration : _kDefaultDuration;

    void close() => Navigator.of(context).maybePop();

    final (statusLabel, statusColor) = switch (status) {
      'completed' => ('✓ تم', const Color(0xFF22C55E)),
      'cancelled' => ('✕ ملغي', const Color(0xFFEF4444)),
      _ => ('⏱ قادم', const Color(0xFF15604A)),
    };

    return Dialog(
      backgroundColor: BrandColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color.fromRGBO(201, 162, 75, .25)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          key: Key('appt-week-details-$id'),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: BrandColors.gold.withValues(alpha: .12),
                    border: Border.all(
                        color: BrandColors.gold.withValues(alpha: .35)),
                  ),
                  child: Icon(
                    isRecurring ? Icons.repeat_rounded : Icons.event_rounded,
                    size: 20,
                    color: BrandColors.goldDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: BrandColors.brandText)),
                      const SizedBox(height: 2),
                      Text(
                        '$date${time.isNotEmpty ? ' · ${to12h(time)}' : ''} · $durText د',
                        style: TextStyle(
                            fontSize: 11, color: BrandColors.mut2),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor)),
                ),
              ]),
              if (service.isNotEmpty || notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                if (service.isNotEmpty)
                  _field('الخدمة / الإجراء', service),
                if (notes.isNotEmpty) _field('الملاحظات', notes),
              ],

              // أفعال التواصل.
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _chip('اتصال', Icons.call_rounded, const Color(0xFF15604A),
                      key: Key('appt-week-call-$id'),
                      onTap: () => actions.launch('tel:$phone')),
                  _chip('واتساب', Icons.chat_rounded, const Color(0xFF25D366),
                      key: Key('appt-week-wa-$id'),
                      onTap: () => actions.launch(
                          'https://wa.me/$phone?text=${Uri.encodeComponent(waReminderText(a, actions.centerName))}')),
                  _chip('SMS', Icons.sms_rounded, BrandColors.goldDark,
                      key: Key('appt-week-sms-$id'),
                      onTap: () => actions.launch(
                          'sms:$phone?body=${Uri.encodeComponent(smsReminderText(a, actions.centerName))}')),
                  if (debt > 0) ...[
                    _chip('دين $debt ${actions.currency}',
                        Icons.account_balance_wallet_rounded,
                        const Color(0xFFEF4444),
                        key: Key('appt-week-debtwa-$id'),
                        onTap: () => actions.launch(
                            'https://wa.me/$phone?text=${Uri.encodeComponent(debtWaText(a, debt, actions.currency, actions.centerName))}')),
                    _chip('SMS دين', Icons.sms_failed_rounded,
                        const Color(0xFFEF4444),
                        key: Key('appt-week-debtsms-$id'),
                        onTap: () => actions.launch(
                            'sms:$phone?body=${Uri.encodeComponent(debtSmsText(a, debt, actions.currency, actions.centerName))}')),
                  ],
                ]),
              ],

              const SizedBox(height: 14),
              // الحالة (تم/تراجع).
              Row(children: [
                if (!completed)
                  Expanded(
                    child: OutlinedButton.icon(
                      key: Key('appt-week-done-$id'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF22C55E),
                          visualDensity: VisualDensity.compact),
                      onPressed: () {
                        close();
                        actions.markDone(id);
                      },
                      icon: const Icon(Icons.check_rounded, size: 15),
                      label: const Text('تم', style: TextStyle(fontSize: 12)),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      key: Key('appt-week-undone-$id'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF59E0B),
                          visualDensity: VisualDensity.compact),
                      onPressed: () {
                        close();
                        actions.markDone(id, done: false);
                      },
                      icon: const Icon(Icons.replay_rounded, size: 15),
                      label:
                          const Text('تراجع', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('appt-week-edit-$id'),
                    style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () {
                      close();
                      actions.openForm(editing: a);
                    },
                    icon: Icon(Icons.edit_rounded,
                        size: 15, color: BrandColors.brandIcon),
                    label: const Text('تعديل', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('appt-week-copy-$id'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: BrandColors.brand700,
                        visualDensity: VisualDensity.compact),
                    onPressed: () {
                      close();
                      // نسخٌ: يفتح نموذج موعدٍ جديد مسبق التعبئة بالحقول
                      // الميدانية (بلا id/تكرار/تخزين) بتاريخ الموعد ووقتٍ
                      // فارغٍ ليختار الطبيب موضعاً جديداً. الحفظ ينشئ صفاً
                      // جديداً بمعرّفٍ جديد (قيد النسخ #5).
                      actions.openForm(
                        prefill: {
                          'name': a['name'],
                          'phone': a['phone'],
                          'service': a['service'],
                          'notes': a['notes'],
                          if (jsNumOr0(a['durationMin']) > 0)
                            'durationMin': a['durationMin'],
                        },
                        defaultDate: date,
                        defaultTime: '',
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('نسخ', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('appt-week-cancel-$id'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        visualDensity: VisualDensity.compact),
                    onPressed: cancelled
                        ? null
                        : () {
                            close();
                            actions.cancelOne(id);
                          },
                    icon: const Icon(Icons.block_rounded, size: 15),
                    label:
                        const Text('إلغاء', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: Key('appt-week-delete-$id'),
                  tooltip: 'حذف نهائياً',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    close();
                    actions.deleteOne(a);
                  },
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: BrandColors.red),
                ),
              ]),

              // «عرض السلسلة» للموعد الدوري.
              if (isRecurring) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    key: Key('appt-week-series-$id'),
                    style: TextButton.styleFrom(
                        foregroundColor: BrandColors.goldDark),
                    onPressed: () {
                      close();
                      actions.openSeriesList('${a['repeatGroup']}');
                    },
                    icon: const Icon(Icons.list_alt_rounded, size: 15),
                    label: const Text('عرض السلسلة',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 10, color: BrandColors.mut2)),
            const SizedBox(height: 1),
            Text(value,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: BrandColors.ink)),
          ],
        ),
      );

  Widget _chip(String label, IconData icon, Color color,
      {required Key key, required VoidCallback onTap}) {
    return InkWell(
      key: key,
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
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }
}
