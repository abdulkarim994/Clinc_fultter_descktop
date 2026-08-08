/// نظام الدور (الحجوزات) — نقل بنيوي لـ QueueClinicSelect + QueueBoard فوق
/// QueueRepository المنقول:
///   • اختيار اليوم (مع الحجز المسبق وأيامه القادمة) ثم العيادة مع عدّاد
///     المنتظرين
///   • لوحة الدور: إحصاءات حية، فترتا صباح/مساء + أرشيف اليوم، إضافة سريعة
///     تبقى مفتوحة للمريض التالي، «تم الدخول» يؤرشف برقم أرشيف، تخطٍّ وإلغاء
///   • كل كتابة عبر upsertLocal/delete ⇒ مختومة dirty وجاهزة للمزامنة فوراً.
///
/// م56 — إكمال التطابق مع الأصل (Vue): إعادة ترقيم متقاربة عبر الأجهزة
/// (queue_order)، تخطٍّ للنهاية، إغلاق الفجوات بعد الإلغاء/الدخول، سحب
/// وإفلات لإعادة الترتيب، نافذة تعديل كاملة، ملاحظات إدخالاً وعرضاً، اتصال
/// ورسالة جاهزة بمعاينة وSMS، تأكيد إلغاء، إشعارات، تنسيق 12 ساعة، وتنظيف
/// يومي، وزر رجوع فيزيائي، ومصالحة الترقيم بعد كل دورة مزامنة دمجت صفوفاً.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/js_compat.dart';
import '../../core/utils/uid.dart';
import 'package:url_launcher/url_launcher.dart';

import 'queue_order.dart';
import '../settings/settings_screen.dart' show kDefaultQueueWaTemplate;

/// تنسيق وقت 12 ساعة (4:30 PM) — fmtTime حرفياً من الأصل. الفارغ ⇒ «—».
String fmtQueueTime12(Object? t) {
  final s = '${t ?? ''}';
  if (s.isEmpty) return '—';
  final parts = s.split(':');
  final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  final ap = h >= 12 ? 'PM' : 'AM';
  final hh = ((h + 11) % 12) + 1;
  return '$hh:${m.toString().padLeft(2, '0')} $ap';
}

/// "HH:MM" + دقائق -> "HH:MM" (مثبتة داخل اليوم) — addMinutes حرفياً.
String addMinutesHHMM(String? hhmm, int minutes) {
  final parts = '${(hhmm ?? '').isEmpty ? '09:00' : hhmm}'.split(':');
  final h = int.tryParse(parts[0]) ?? 9;
  final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  var total = h * 60 + m + minutes;
  total = total.clamp(0, 23 * 60 + 59);
  return '${(total ~/ 60).toString().padLeft(2, '0')}:'
      '${(total % 60).toString().padLeft(2, '0')}';
}

/// تعبئة قالب رسالة الدور — buildMsg حرفياً.
String buildQueueMsg(Map<String, Object?> cfg, QRow r, String clinic) {
  final tpl = '${jsOr(cfg['queueWaTemplate'], kDefaultQueueWaTemplate)}';
  return tpl
      .replaceAll('{name}', '${r['patient_name'] ?? ''}')
      .replaceAll('{center}', '${jsOr(cfg['centerName'], 'المركز')}')
      .replaceAll('{clinic}', clinic)
      // م56 — الوقت في الرسالة بنظام 12 ساعة كالأصل (كان 24س خاماً).
      .replaceAll('{time}', fmtQueueTime12(r['est_time']));
}

// ═══════════════ الحالة والمتحكم ═══════════════

class QueueView {
  const QueueView({this.clinic, required this.date, this.period = 'morning'});

  final String? clinic; // null ⇒ شاشة اختيار العيادة
  final String date;
  final String period; // morning | evening | archive

  QueueView copyWith({String? clinic, String? date, String? period}) =>
      QueueView(
        clinic: clinic ?? this.clinic,
        date: date ?? this.date,
        period: period ?? this.period,
      );

  QueueView backToSelect() => QueueView(clinic: null, date: date);
}

/// نبضة إعادة قراءة لبيانات الدور بعد كل كتابة (لا تمس حالة العرض).
final queueRevProvider = StateProvider<int>((ref) => 0);

class QueueController extends Notifier<QueueView> {
  @override
  QueueView build() => QueueView(date: getCurrentDate());

  void _bump() => ref.read(queueRevProvider.notifier).state++;

  void openClinic(String clinic) =>
      state = state.copyWith(clinic: clinic, period: 'morning');

  void back() => state = state.backToSelect();

  void setDate(String d) => state = state.copyWith(date: d);

  void setPeriod(String p) => state = state.copyWith(period: p);

  void shiftDay(int delta) {
    final d = DateTime.parse(state.date).add(Duration(days: delta));
    setDate('${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}');
  }

  num get _slotMin {
    final v = jsNumOr0(
        ref.read(appConfigProvider)['queueSlotMin']);
    return v > 0 ? v : 15;
  }

  String _startOf(String p) {
    final cfg = ref.read(appConfigProvider);
    return p == 'evening'
        ? '${jsOr(cfg['queueEveningStart'], '16:00')}'
        : '${jsOr(cfg['queueMorningStart'], '09:00')}';
  }

  /// إعادة حساب الأوقات المتوقعة لقائمة انتظار فترة (يتخطى اليدوي) —
  /// recomputeEst حرفياً.
  void _recomputeEst(String p) {
    final waiting = sortWaiting(
        _rows().where((r) => r['period'] == p && r['state'] == 'waiting'));
    final start = _startOf(p);
    final repos = ref.read(reposProvider);
    for (var i = 0; i < waiting.length; i++) {
      final r = waiting[i];
      if (jsNumOr0(r['est_manual']) == 1) continue;
      final t = addMinutesHHMM(start, (i * _slotMin).toInt());
      if (r['est_time'] != t) {
        repos.queue.upsertLocal({...r, 'est_time': t}, base: r);
      }
    }
  }

  /// م56 — إعادة ترقيم فترة 1..N بترتيب متقارب (seq، ثم id) ثم حساب
  /// الأوقات — renumber حرفياً. idempotent: يكتب الصف المتغيّر فقط، فلا
  /// تُبعث كتابةٌ عبثية ولا يتأرجح جهازان على ترتيب واحد.
  void _renumber(String p) {
    final repos = ref.read(reposProvider);
    final plan = planWaitingSeq(
        _rows().where((r) => r['period'] == p && r['state'] == 'waiting'));
    final byId = {for (final r in _rows()) '${r['id']}': r};
    for (final e in plan) {
      final r = byId[e.id];
      if (r != null && jsNumOr0(r['seq']).toInt() != e.seq) {
        repos.queue.upsertLocal({...r, 'seq': e.seq}, base: r);
      }
    }
    _recomputeEst(p);
  }

  /// م56 — إعادة ترقيم الأرشيف 1..M بترتيب الوصول المتقارب — renumberArchive.
  void _renumberArchive() {
    final repos = ref.read(reposProvider);
    final plan =
        planArchiveSeq(_rows().where((r) => r['state'] == 'done'));
    final byId = {for (final r in _rows()) '${r['id']}': r};
    for (final e in plan) {
      final r = byId[e.id];
      if (r != null && jsNumOr0(r['archive_seq']).toInt() != e.archiveSeq) {
        repos.queue.upsertLocal({...r, 'archive_seq': e.archiveSeq}, base: r);
      }
    }
  }

  /// م56 — مصالحة كل الفترات والأرشيف: تُستدعى بعد دورة مزامنة دمجت صفوفاً
  /// (من مستمع الإسقاط) فتتقارب الأجهزة على نفس الترقيم. idempotent.
  void reconcileNumbers() {
    if (state.clinic == null) return;
    _renumber('morning');
    _renumber('evening');
    _renumberArchive();
    _bump();
  }

  /// م56 — التنظيف اليومي: حذف صفوف الأيام الأقدم من اليوم (توأم
  /// purgeOldDays) — شواهد القبور تصل السحابة عبر المزامنة العادية.
  void purgeOldDays() {
    try {
      ref.read(reposProvider).queue.purgeOlderThan(getCurrentDate());
      _bump();
    } catch (_) {/* أفضل جهد */}
  }

  List<QRow> _rows() {
    final c = state.clinic;
    if (c == null) return const [];
    return ref.read(reposProvider).queue.getByClinicDate(c, state.date);
  }

  /// إضافة سريعة — تعيين seq التالي داخل (عيادة، يوم، فترة).
  /// م56 — يعيد الصف المضاف (أو null) ليتمكن استدعاء الواجهة من الإشعار.
  QRow? quickAdd({
    required String name,
    String phone = '',
    String status = 'new',
    String notes = '',
  }) {
    if (name.trim().isEmpty || state.clinic == null) return null;
    final period = state.period == 'archive' ? 'morning' : state.period;
    final waiting = _rows().where(
        (r) => r['period'] == period && r['state'] == 'waiting');
    final nextSeq = waiting.fold<int>(
            0, (m, r) => jsNumOr0(r['seq']).toInt() > m
                ? jsNumOr0(r['seq']).toInt()
                : m) +
        1;
    final row = <String, Object?>{
      'id': genId(),
      'clinic': state.clinic,
      'clinic_id': state.clinic,
      'date': state.date,
      'period': period,
      'seq': nextSeq,
      'patient_name': name.trim(),
      'phone': phone.trim(),
      'status': status,
      'notes': notes.trim(),
      'est_time': addMinutesHHMM(
          _startOf(period), ((nextSeq - 1) * _slotMin).toInt()),
      'est_manual': 0,
      'state': 'waiting',
      // م56 — ختم created_at عند الإضافة (كان غائباً؛ الأصل يختمه).
      'created_at': jsIsoNow(),
    };
    ref.read(reposProvider).queue.upsertLocal(row);
    _bump();
    return row;
  }

  /// م56 — تعديل مريض: يكتب الحقول الممرّرة فقط (لقطة أساس) مع أتمتة علم
  /// est_manual عند تحرير الوقت يدوياً — updatePatient حرفياً.
  void updatePatient(QRow r, Map<String, Object?> fields) {
    var f = {...fields};
    if (f.containsKey('est_time') && f['est_time'] != r['est_time']) {
      f = {...f, 'est_manual': 1};
    }
    ref.read(reposProvider).queue.upsertLocal({...r, ...f}, base: r);
    _bump();
  }

  /// م56 — تطبيق ترتيب صريح من السحب والإفلات على فترة — applyOrder.
  void applyOrder(String p, List<String> idOrder) {
    final repos = ref.read(reposProvider);
    final byId = {for (final r in _rows()) '${r['id']}': r};
    for (final (i, id) in idOrder.indexed) {
      final r = byId[id];
      if (r != null && jsNumOr0(r['seq']).toInt() != i + 1) {
        repos.queue.upsertLocal({...r, 'seq': i + 1}, base: r);
      }
    }
    _recomputeEst(p);
    _bump();
  }

  /// «تم الدخول» — أرشفة برقم أرشيف اليوم التالي ثم إغلاق فجوة الانتظار.
  void finish(QRow r) {
    final rows = _rows();
    final maxArchive = rows
        .where((x) => x['state'] == 'done')
        .fold<int>(0, (m, x) => jsNumOr0(x['archive_seq']).toInt() > m
            ? jsNumOr0(x['archive_seq']).toInt()
            : m);
    ref.read(reposProvider).queue.upsertLocal({
      ...r,
      'state': 'done',
      'archive_seq': maxArchive + 1,
      'entered_at': jsIsoNow(),
    }, base: r);
    // م56 — إعادة ترقيم كاملة تُغلق الفجوة (كان يعيد الأوقات فقط فتبقى
    // الأرقام مفجوّة: 1،3،4 بعد دخول رقم 2).
    _renumber('${r['period']}');
    _bump();
  }

  /// تخطٍّ — إرسال المريض لنهاية فترته ثم إعادة الترقيم — skip حرفياً.
  /// م56 — كان يبدّل مع التالي (خطوة واحدة) بينما الأصل يرسله للنهاية.
  void skip(QRow r) {
    if (r['state'] != 'waiting') return;
    final maxSeq = _rows()
        .where((x) => x['period'] == r['period'] && x['state'] == 'waiting')
        .fold<int>(0, (m, x) => jsNumOr0(x['seq']).toInt() > m
            ? jsNumOr0(x['seq']).toInt()
            : m);
    ref.read(reposProvider).queue.upsertLocal({...r, 'seq': maxSeq + 1},
        base: r);
    _renumber('${r['period']}');
    _bump();
  }

  void cancel(QRow r) {
    ref.read(reposProvider).queue.delete(r['id'] as String);
    // م56 — إعادة ترقيم كاملة تُغلق الفجوة (توأم cancel: renumber(p)).
    _renumber('${r['period']}');
    _bump();
  }
}

final queueViewProvider =
    NotifierProvider<QueueController, QueueView>(QueueController.new);

/// صفوف اليوم الحالي للعيادة المفتوحة.
/// اسم بديل لأن Row اسم ويدجت في Flutter أيضاً.
typedef QRow = Map<String, Object?>;

final queueRowsProvider = Provider<List<QRow>>((ref) {
  ref.watch(queueRevProvider);
  final view = ref.watch(queueViewProvider);
  if (view.clinic == null) return const [];
  return ref
      .watch(reposProvider)
      .queue
      .getByClinicDate(view.clinic!, view.date);
});

/// أيام قادمة محجوزة مسبقاً.
final upcomingDatesProvider = Provider<List<String>>((ref) {
  ref.watch(queueRevProvider);
  ref.watch(queueViewProvider);
  return ref.watch(reposProvider).queue.getUpcomingDates(getCurrentDate());
});

// ═══════════════ الشاشة ═══════════════

class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(queueViewProvider);
    return view.clinic == null
        ? const _ClinicSelect()
        : const _QueueBoard();
  }
}

// ── اختيار اليوم والعيادة ──
class _ClinicSelect extends ConsumerWidget {
  const _ClinicSelect();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(queueViewProvider);
    ref.watch(queueRevProvider); // لعدّادات الانتظار
    final clinics = ref.watch(clinicsProvider);
    final upcoming = ref.watch(upcomingDatesProvider);
    final repos = ref.watch(reposProvider);
    final today = getCurrentDate();
    final isFuture = view.date.compareTo(today) > 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        const Text(
          'الحجوزات — نظام الدور',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            color: BrandColors.goldDark,
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('اختر اليوم',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.parse(view.date),
                            firstDate: DateTime.now()
                                .subtract(const Duration(days: 30)),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 90)),
                          );
                          if (picked != null) {
                            ref.read(queueViewProvider.notifier).setDate(
                                '${picked.year.toString().padLeft(4, '0')}-'
                                '${picked.month.toString().padLeft(2, '0')}-'
                                '${picked.day.toString().padLeft(2, '0')}');
                          }
                        },
                        icon: const Icon(Icons.calendar_month_rounded,
                            size: 17),
                        label: Text(view.date),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => ref
                          .read(queueViewProvider.notifier)
                          .setDate(today),
                      style: FilledButton.styleFrom(
                          backgroundColor: BrandColors.brand600),
                      child: const Text('اليوم'),
                    ),
                  ],
                ),
                if (isFuture)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '🗓 حجز مسبق ليوم ${view.date} — اختر العيادة لفتح قائمة انتظار مستقلة لهذا اليوم.',
                      style: const TextStyle(
                          fontSize: 11.5, color: BrandColors.brand700),
                    ),
                  ),
                if (upcoming.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('أيام قادمة محجوزة:',
                      style: TextStyle(
                          fontSize: 11, color: BrandColors.mut)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final d in upcoming)
                        ChoiceChip(
                          label: Text(d,
                              style: const TextStyle(fontSize: 11)),
                          selected: d == view.date,
                          onSelected: (_) => ref
                              .read(queueViewProvider.notifier)
                              .setDate(d),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('اختر العيادة',
            style:
                TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (clinics.isEmpty)
          Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Text(
                'لا توجد عيادات. أضِف عيادة من الإعدادات.',
                textAlign: TextAlign.center,
                style: TextStyle(color: BrandColors.mut2, fontSize: 13),
              ),
            ),
          )
        else
          for (final c in clinics)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 5),
              child: ListTile(
                key: Key('clinic-$c'),
                onTap: () =>
                    ref.read(queueViewProvider.notifier).openClinic(c),
                leading: CircleAvatar(
                  backgroundColor: BrandColors.paper,
                  child: const Icon(Icons.local_hospital_rounded,
                      color: BrandColors.brand600, size: 20),
                ),
                title: Text(c,
                    style:
                        const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${repos.queue.getByClinicDate(c, today).where((r) => r['state'] == 'waiting').length} في الانتظار اليوم',
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: const Icon(Icons.chevron_left_rounded),
              ),
            ),
      ],
    );
  }
}

// ── لوحة الدور ──
class _QueueBoard extends ConsumerStatefulWidget {
  const _QueueBoard();

  @override
  ConsumerState<_QueueBoard> createState() => _QueueBoardState();
}

class _QueueBoardState extends ConsumerState<_QueueBoard> {
  bool addOpen = false;
  String addStatus = 'new';
  int addedCount = 0; // م56 — عدّاد المضافين في الجلسة (توأم addedCount).
  final nameCtl = TextEditingController();
  final phoneCtl = TextEditingController();
  final notesCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // م56 — تنظيف يومي عند فتح اللوحة (توأم purgeOldDays في onMounted).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(queueViewProvider.notifier).purgeOldDays();
    });
  }

  @override
  void dispose() {
    nameCtl.dispose();
    phoneCtl.dispose();
    notesCtl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), duration: const Duration(milliseconds: 1400)));
  }

  void _quickAdd() {
    // م56 — تنبيه الاسم الفارغ (كان يفشل بصمت) + إشعار وعدّاد كالأصل.
    if (nameCtl.text.trim().isEmpty) {
      _snack('الرجاء إدخال الاسم');
      return;
    }
    final added = ref.read(queueViewProvider.notifier).quickAdd(
          name: nameCtl.text,
          phone: phoneCtl.text,
          status: addStatus,
          notes: notesCtl.text,
        );
    if (added != null) {
      setState(() => addedCount++);
      _snack('تمت الإضافة');
    }
    nameCtl.clear();
    phoneCtl.clear();
    notesCtl.clear();
    // تبقى النافذة مفتوحة لإضافة المريض التالي فوراً (سلوك الأصل).
  }

  // ═══ v62 — حالات لوحة «التالي في الدور» البطلة ═══

  Widget _heroArchive(List<QRow> done) => Row(children: [
        const Icon(Icons.task_alt_rounded,
            color: BrandColors.goldLight, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text('تم علاجهم اليوم: ${done.length}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
        ),
      ]);

  Widget _heroEmpty() => Row(children: [
        Icon(Icons.hourglass_empty_rounded,
            color: Colors.white.withValues(alpha: .8), size: 26),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('لا منتظرين حالياً — أضف حجزاً بزر +',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700)),
        ),
      ]);

  Widget _heroNext(QRow next, List<QRow> done, List<QRow> waiting) {
    final isReview = next['status'] == 'review';
    final hasNotes = '${next['notes'] ?? ''}'.trim().isNotEmpty;
    final total = done.length + waiting.length;
    final progress = total > 0 ? done.length / total : 0.0;
    return Column(children: [
      Row(children: [
        // رقم الدور الذهبي الضخم — قلب لوحة Now Serving.
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [BrandColors.goldLight, BrandColors.goldDark]),
            border: Border.all(
                color: Colors.white.withValues(alpha: .35),
                width: 1.5),
          ),
          child: Text('${next['seq']}',
              key: const Key('hero-seq'),
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('التالي في الدور',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.white.withValues(alpha: .75),
                      fontWeight: FontWeight.w700)),
              Text('${next['patient_name'] ?? '—'}',
                  key: const Key('hero-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
              Row(children: [
                Text(isReview ? 'مراجعة' : 'جديد',
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: BrandColors.goldLight)),
                if ('${next['est_time'] ?? ''}'.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                        '🕐 ${fmtQueueTime12(next['est_time'])}',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white
                                .withValues(alpha: .85))),
                  ),
                if (hasNotes)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('📝 ${'${next['notes']}'.trim()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5,
                              color: Colors.white
                                  .withValues(alpha: .85))),
                    ),
                  ),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // زرا «إدخال التالي» الذهبي و«تخطّي».
        Column(children: [
          Material(
            color: Colors.transparent,
            child: Ink(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [
                  BrandColors.goldLight,
                  BrandColors.goldDark,
                ]),
                borderRadius: BorderRadius.circular(50),
              ),
              child: InkWell(
                key: const Key('hero-admit'),
                borderRadius: BorderRadius.circular(50),
                onTap: () {
                  ref.read(queueViewProvider.notifier).finish(next);
                  _snack('تم نقل المريض لأرشيف اليوم');
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 15, color: Colors.white),
                        SizedBox(width: 5),
                        Text('إدخال التالي',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            key: const Key('hero-skip'),
            borderRadius: BorderRadius.circular(50),
            onTap: () {
              ref.read(queueViewProvider.notifier).skip(next);
              _snack('نُقل لآخر الدور');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 2),
              child: Text('تخطّي',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: .8),
                      decoration: TextDecoration.underline,
                      decorationColor:
                          Colors.white.withValues(alpha: .5))),
            ),
          ),
        ]),
      ]),
      const SizedBox(height: 8),
      // شريط تقدم اليوم — «تم N من M» بالذهبي.
      Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Stack(children: [
                Container(
                    color: Colors.white.withValues(alpha: .18)),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                      decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [
                    BrandColors.goldLight,
                    BrandColors.gold,
                  ]))),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('تم ${done.length} من $total',
            key: const Key('hero-progress'),
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: .85))),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(queueViewProvider);
    final rows = ref.watch(queueRowsProvider);
    final today = getCurrentDate();

    final waiting =
        rows.where((r) => r['state'] == 'waiting').toList();
    final done = rows.where((r) => r['state'] == 'done').toList()
      ..sort((a, b) => jsNumOr0(a['archive_seq'])
          .compareTo(jsNumOr0(b['archive_seq'])));
    final morning = waiting
        .where((r) => r['period'] == 'morning')
        .toList()
      ..sort(
          (a, b) => jsNumOr0(a['seq']).compareTo(jsNumOr0(b['seq'])));
    final evening = waiting
        .where((r) => r['period'] == 'evening')
        .toList()
      ..sort(
          (a, b) => jsNumOr0(a['seq']).compareTo(jsNumOr0(b['seq'])));

    final display = switch (view.period) {
      'archive' => done,
      'evening' => evening,
      _ => morning,
    };

    // م56 — زر الرجوع الفيزيائي يغلق اللوحة أولاً (لوحة ← اختيار عيادة)
    // قبل مغادرة التبويب (توأم pushBackHandler(_onHardwareBack) في الأصل).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(queueViewProvider.notifier).back();
      },
      child: Column(
      children: [
        // ── الشريط العلوي: رجوع + عيادة + تنقل اليوم ──
        // ── v61 — رأس الدور بالقالب الموحد (توأم السجلات/المالية):
        // [رجوع 38×36 | العيادة+التاريخ | سهما تنقل ذهبيان] على خلفية
        // الصفحة مباشرة بلا بطاقة حاضنة. ──
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(
            children: [
              Material(
                color: BrandColors.brand600.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: const Key('queue-back'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () =>
                      ref.read(queueViewProvider.notifier).back(),
                  child: SizedBox(
                    width: 38,
                    height: 36,
                    child: Icon(Icons.arrow_back_rounded,
                        size: 18, color: BrandColors.brandIcon),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.clinic!,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          color: BrandColors.brandText),
                    ),
                    Row(children: [
                      Text(view.date,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                              color: BrandColors.mut2)),
                      if (view.date == today)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Text('اليوم',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: BrandColors.green,
                                  fontWeight: FontWeight.w700)),
                        )
                      else if (view.date.compareTo(today) > 0)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Text('حجز مسبق',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: BrandColors.goldDark,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // سهما تنقل التاريخ — مربعان ذهبيان بعائلة القمع.
              Material(
                color: BrandColors.gold.withValues(alpha: .08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                      color: BrandColors.gold.withValues(alpha: .3)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => ref
                      .read(queueViewProvider.notifier)
                      .shiftDay(-1),
                  child: const SizedBox(
                    width: 38,
                    height: 36,
                    child: Icon(Icons.chevron_right_rounded,
                        size: 18, color: BrandColors.goldDark),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: BrandColors.gold.withValues(alpha: .08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                      color: BrandColors.gold.withValues(alpha: .3)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => ref
                      .read(queueViewProvider.notifier)
                      .shiftDay(1),
                  child: const SizedBox(
                    width: 38,
                    height: 36,
                    child: Icon(Icons.chevron_left_rounded,
                        size: 18, color: BrandColors.goldDark),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── v62 — لوحة «التالي في الدور» البطلة (بحث أنظمة الدور:
        // Now Serving + Call Next): رقم ذهبي ضخم، اسم كبير، سطر خاطف،
        // زر «إدخال التالي» بضغطة، تخطٍّ، وشريط تقدم اليوم.
        // تُخفى مؤقتاً أثناء فتح نافذة الإضافة (تفسح لها المكان). ──
        if (!(addOpen && view.period != 'archive'))
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Container(
            key: const Key('queue-hero'),
            decoration: BoxDecoration(
              gradient: BrandColors.brandGradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                    color: Color.fromRGBO(10, 48, 36, .25),
                    blurRadius: 14,
                    offset: Offset(0, 4)),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: view.period == 'archive'
                ? _heroArchive(done)
                : display.isEmpty
                    ? _heroEmpty()
                    : _heroNext(display.first, done, waiting),
          ),
        ),

        // ── الإحصاءات الحية — v62: رقاقات مدمجة بدل البطاقات الضخمة ──
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Row(
            children: [
              _Stat(
                  label: 'الموجودون حالياً',
                  value: waiting.length,
                  color: const Color(0xFF2563EB)),
              _Stat(
                  label: 'تم علاجهم اليوم',
                  value: done.length,
                  color: BrandColors.green),
              _Stat(
                  label: 'المتبقّون',
                  value: waiting.length,
                  color: BrandColors.goldDark),
            ],
          ),
        ),

        // ── الفترات + زر الإضافة ──
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Row(
            children: [
              _PeriodTab(
                  id: 'morning',
                  label: 'صباح',
                  count: morning.length,
                  view: view),
              _PeriodTab(
                  id: 'evening',
                  label: 'مساء',
                  count: evening.length,
                  view: view),
              _PeriodTab(
                  id: 'archive',
                  label: 'الأرشيف',
                  count: done.length,
                  view: view),
              const Spacer(),
              if (view.period != 'archive')
                Badge(
                  isLabelVisible: addedCount > 0,
                  label: Text('$addedCount'),
                  child: FloatingActionButton.small(
                    key: const Key('queue-add-toggle'),
                    heroTag: 'q-add',
                    backgroundColor:
                        addOpen ? BrandColors.goldDark : BrandColors.gold,
                    foregroundColor: BrandColors.brand900,
                    onPressed: () => setState(() {
                      addOpen = !addOpen;
                      if (addOpen) addedCount = 0;
                    }),
                    child: Icon(
                        addOpen ? Icons.close_rounded : Icons.add_rounded),
                  ),
                ),
            ],
          ),
        ),

        // ── الإضافة السريعة ──
        if (addOpen && view.period != 'archive')
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Card(
              color: BrandColors.surface2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            key: const Key('queue-add-name'),
                            controller: nameCtl,
                            autofocus: true,
                            onSubmitted: (_) => _quickAdd(),
                            decoration: const InputDecoration(
                                hintText: 'اسم المريض', isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: phoneCtl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                                hintText: 'الهاتف (اختياري)',
                                isDense: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // م56 — حقل الملاحظات في الإضافة السريعة (كان المتحكم
                    // يُنشأ ويُفرّغ بلا حقل معروض — الملاحظة تُهمل).
                    TextField(
                      key: const Key('queue-add-notes'),
                      controller: notesCtl,
                      onSubmitted: (_) => _quickAdd(),
                      decoration: const InputDecoration(
                          hintText: 'ملاحظات (اختياري)', isDense: true),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('جديد'),
                          selected: addStatus == 'new',
                          onSelected: (_) =>
                              setState(() => addStatus = 'new'),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('مراجعة'),
                          selected: addStatus == 'review',
                          onSelected: (_) =>
                              setState(() => addStatus = 'review'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          key: const Key('queue-add-go'),
                          onPressed: _quickAdd,
                          style: FilledButton.styleFrom(
                              backgroundColor: BrandColors.brand600),
                          icon: const Icon(Icons.check_rounded, size: 17),
                          label: const Text('إضافة ومتابعة'),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'اكتب الاسم واضغط Enter — تبقى النافذة مفتوحة '
                        'لإضافة المريض التالي فوراً.',
                        style: TextStyle(
                            fontSize: 11, color: BrandColors.mut2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── القائمة ──
        Expanded(
          child: display.isEmpty
              ? Center(
                  child: Text(
                    view.period == 'archive'
                        ? 'لا أحد في أرشيف اليوم بعد.'
                        : 'قائمة الانتظار فارغة.',
                    style: TextStyle(
                        color: BrandColors.mut2, fontSize: 13),
                  ),
                )
              : view.period == 'archive'
                  // الأرشيف بترتيب الوصول الثابت — لا سحب.
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
                      itemCount: display.length,
                      itemBuilder: (context, i) =>
                          _QueueRow(row: display[i], view: view),
                    )
                  // م56 — سحب وإفلات لإعادة الترتيب في قائمة الانتظار
                  // (توأم onPointerMove/applyOrder): الإفلات يطبّق الترتيب
                  // الجديد ويعيد حساب الأوقات للجميع.
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
                      buildDefaultDragHandles: false,
                      itemCount: display.length,
                      // onReorder مستقر ومتوافق عبر الإصدارات (البديل
                      // onReorderItem أحدث)؛ نُبقيه ونُسكت التنبيه.
                      // ignore: deprecated_member_use
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final ids = [
                          for (final r in display) '${r['id']}'
                        ];
                        final moved = ids.removeAt(oldIndex);
                        ids.insert(newIndex, moved);
                        ref
                            .read(queueViewProvider.notifier)
                            .applyOrder(view.period, ids);
                      },
                      itemBuilder: (context, i) => _QueueRow(
                        key: ValueKey(display[i]['id']),
                        row: display[i],
                        view: view,
                        dragIndex: i,
                        isNext: i == 0,
                      ),
                    ),
        ),
      ],
    ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // v62 — رقاقة مدمجة أنحف (بدل البطاقة الضخمة): الرقم بجانب الوسم.
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: BrandColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BrandColors.line, width: .8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: color)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10, color: BrandColors.mut)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodTab extends ConsumerWidget {
  const _PeriodTab({
    required this.id,
    required this.label,
    required this.count,
    required this.view,
  });

  final String id;
  final String label;
  final int count;
  final QueueView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = view.period == id;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        key: Key('period-$id'),
        label: Text('$label ($count)'),
        selected: on,
        selectedColor: BrandColors.brand600,
        labelStyle: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: on ? Colors.white : BrandColors.ink,
        ),
        onSelected: (_) =>
            ref.read(queueViewProvider.notifier).setPeriod(id),
      ),
    );
  }
}

/// م56 — صف الدور القابل للطي (توأم q-head/q-body في QueueBoard.vue):
/// رأس مضغوط (رقم، اسم، دخول، مقبض سحب) يُوسّع عند اللمس فيظهر: الحالة،
/// رقاقة الوقت (تفتح التعديل)، رقاقة الملاحظة، صف التواصل (اتصال/واتساب/
/// رسالة جاهزة)، وأزرار تخطٍّ/تعديل/إلغاء (بتأكيد).
class _QueueRow extends ConsumerStatefulWidget {
  const _QueueRow({
    super.key,
    required this.row,
    required this.view,
    this.dragIndex,
    this.isNext = false,
  });

  final QRow row;
  final QueueView view;
  final int? dragIndex;

  /// v62 — الأول في قائمة الانتظار: حد ذهبي وشارة «التالي».
  final bool isNext;

  @override
  ConsumerState<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends ConsumerState<_QueueRow> {
  bool open = false;

  QRow get row => widget.row;
  QueueView get view => widget.view;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), duration: const Duration(milliseconds: 1400)));
  }

  String _digits(Object? phone) =>
      '${phone ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _launch(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _snack('تعذّر فتح التطبيق');
    }
  }

  // م56 — نافذة التعديل الكاملة (توأم form modal): اسم/هاتف/حالة/وقت
  // متوقع/ملاحظات. تحرير الوقت يؤتمت علم est_manual في المتحكم.
  Future<void> _openEdit() async {
    final nameCtl = TextEditingController(text: '${row['patient_name'] ?? ''}');
    final phoneCtl = TextEditingController(text: '${row['phone'] ?? ''}');
    final notesCtl = TextEditingController(text: '${row['notes'] ?? ''}');
    var status = '${row['status'] ?? 'new'}';
    var est = '${row['est_time'] ?? ''}';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('تعديل بيانات المريض',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: const Key('q-edit-name'),
                  controller: nameCtl,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('q-edit-phone'),
                  controller: phoneCtl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'الهاتف'),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  ChoiceChip(
                    label: const Text('جديد'),
                    selected: status == 'new',
                    onSelected: (_) => setLocal(() => status = 'new'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('مراجعة'),
                    selected: status == 'review',
                    onSelected: (_) => setLocal(() => status = 'review'),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  const Text('الوقت المتوقع: ',
                      style: TextStyle(fontSize: 12.5)),
                  TextButton(
                    key: const Key('q-edit-time'),
                    onPressed: () async {
                      final parts = est.split(':');
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay(
                          hour: int.tryParse(
                                  parts.isNotEmpty ? parts[0] : '') ??
                              9,
                          minute: int.tryParse(
                                  parts.length > 1 ? parts[1] : '') ??
                              0,
                        ),
                      );
                      if (picked != null) {
                        setLocal(() => est =
                            '${picked.hour.toString().padLeft(2, '0')}:'
                            '${picked.minute.toString().padLeft(2, '0')}');
                      }
                    },
                    child: Text(est.isEmpty ? 'اختر' : fmtQueueTime12(est)),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('q-edit-notes'),
                  controller: notesCtl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'الملاحظات'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              key: const Key('q-edit-save'),
              onPressed: () {
                if (nameCtl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      ref.read(queueViewProvider.notifier).updatePatient(row, {
        'patient_name': nameCtl.text.trim(),
        'phone': phoneCtl.text.trim(),
        'status': status,
        'notes': notesCtl.text,
        'est_time': est,
      });
      _snack('تم التعديل');
    }
    nameCtl.dispose();
    phoneCtl.dispose();
    notesCtl.dispose();
  }

  // م56 — نافذة الملاحظات (توأم note modal): عرض النص الكامل.
  void _openNote() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ملاحظات — ${row['patient_name'] ?? ''}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        content: Text('${row['notes'] ?? ''}'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق')),
        ],
      ),
    );
  }

  // م56 — نافذة الرسالة الجاهزة (توأم msg modal): معاينة النص المعبّأ ثم
  // إرسال عبر واتساب أو SMS.
  void _openMsg() {
    final cfg = ref.read(appConfigProvider);
    final msg = buildQueueMsg(cfg, row, view.clinic ?? '');
    final digits = _digits(row['phone']);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('رسالة جاهزة — ${row['patient_name'] ?? ''}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        content: Text(msg, style: const TextStyle(fontSize: 12.5)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _launch(Uri.parse('sms:${row['phone']}?body='
                  '${Uri.encodeComponent(msg)}'));
            },
            child: const Text('SMS'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _launch(Uri.parse('https://wa.me/$digits?text='
                  '${Uri.encodeComponent(msg)}'));
            },
            child: const Text('واتساب'),
          ),
        ],
      ),
    );
  }

  // م56 — تأكيد الإلغاء قبل الحذف (توأم confirm في onCancel).
  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الحجز',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text('إلغاء حجز ${row['patient_name'] ?? ''}؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          FilledButton(
            key: const Key('q-cancel-confirm'),
            style: FilledButton.styleFrom(backgroundColor: BrandColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إلغاء الحجز'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(queueViewProvider.notifier).cancel(row);
      _snack('تم الإلغاء وإعادة الترقيم');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isArchive = view.period == 'archive';
    final isReview = row['status'] == 'review';
    final seq = isArchive ? row['archive_seq'] : row['seq'];
    final hasPhone = '${row['phone'] ?? ''}'.trim().isNotEmpty;
    final hasNotes = '${row['notes'] ?? ''}'.trim().isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        // v62 — الأول في الانتظار: حد ذهبي أوضح (توأم اللوحة البطلة).
        side: widget.isNext
            ? const BorderSide(color: BrandColors.gold, width: 1.4)
            : BorderSide(
                color:
                    (isReview ? BrandColors.gold : BrandColors.brand600)
                        .withValues(alpha: .35),
              ),
      ),
      child: Column(
        children: [
          // ── الرأس المضغوط (لمسة للتوسيع) ──
          InkWell(
            key: Key('qrow-${row['id']}'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => open = !open),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor:
                        isReview ? BrandColors.gold : BrandColors.brand600,
                    child: Text(
                      '$seq',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text('${row['patient_name'] ?? '—'}',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5)),
                          ),
                          // v62 — شارة «التالي» للأول في الانتظار.
                          if (widget.isNext)
                            Container(
                              margin:
                                  const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: BrandColors.gold
                                    .withValues(alpha: .15),
                                borderRadius:
                                    BorderRadius.circular(20),
                                border: Border.all(
                                    color: BrandColors.gold
                                        .withValues(alpha: .45)),
                              ),
                              child: const Text('التالي',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: BrandColors.goldDark)),
                            ),
                        ]),
                        // v61 — سطر خاطف واحد: النوع • الوقت •
                        // الملاحظة مختصرة — كل المهم يُرى بلا توسيع.
                        Row(children: [
                          Text(
                            isReview ? 'مراجعة' : 'جديد',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isReview
                                  ? BrandColors.goldDark
                                  : BrandColors.brand600,
                            ),
                          ),
                          if (!isArchive &&
                              '${row['est_time'] ?? ''}'.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                '🕐 ${fmtQueueTime12(row['est_time'])}'
                                '${jsNumOr0(row['est_manual']) == 1 ? ' ·يدوي' : ''}',
                                key: Key('est-${row['id']}'),
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: BrandColors.mut),
                              ),
                            ),
                          if (hasNotes)
                            Flexible(
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(right: 8),
                                child: Text(
                                  '📝 ${'${row['notes']}'.trim()}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: BrandColors.goldDark),
                                ),
                              ),
                            ),
                        ]),
                      ],
                    ),
                  ),
                  if (!isArchive) ...[
                    IconButton(
                      key: Key('admit-${row['id']}'),
                      tooltip: 'تم الدخول',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        ref.read(queueViewProvider.notifier).finish(row);
                        _snack('تم نقل المريض لأرشيف اليوم');
                      },
                      icon: const Icon(Icons.check_circle_rounded,
                          color: BrandColors.green),
                    ),
                    if (widget.dragIndex != null)
                      ReorderableDragStartListener(
                        index: widget.dragIndex!,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.drag_handle_rounded,
                              size: 20, color: BrandColors.mut),
                        ),
                      ),
                  ] else
                    Text(
                      'دخل: ${'${row['entered_at'] ?? ''}'.length >= 16 ? fmtQueueTime12('${row['entered_at']}'.substring(11, 16)) : '—'}',
                      style: TextStyle(
                          fontSize: 11.5, color: BrandColors.mut),
                    ),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: BrandColors.mut,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // ── التفاصيل الموسّعة — v61: بلا تكرار للسطر المطوي ──
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // الملاحظة كاملة بصندوق خفيف — تنقر لنافذتها.
                  if (hasNotes) ...[
                    InkWell(
                      key: Key('note-${row['id']}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: _openNote,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              BrandColors.gold.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: BrandColors.gold
                                  .withValues(alpha: .25)),
                        ),
                        child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.sticky_note_2_outlined,
                                  size: 13,
                                  color: BrandColors.goldDark),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text('${row['notes']}'.trim(),
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        height: 1.4)),
                              ),
                            ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // رقاقة الوقت القابلة للتعديل بالنقر (خارج الأرشيف).
                  if (!isArchive &&
                      '${row['est_time'] ?? ''}'.isNotEmpty) ...[
                    InkWell(
                      key: Key('est-edit-${row['id']}'),
                      onTap: _openEdit,
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '🕐 ${fmtQueueTime12(row['est_time'])}'
                              '${jsNumOr0(row['est_manual']) == 1 ? ' ·يدوي' : ''}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: BrandColors.mut),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.edit_rounded,
                                size: 12, color: BrandColors.mut2),
                          ]),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // v61 — كل الرقاقات بصف واحد ملفوف: تواصل + إجراءات.
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (hasPhone) ...[
                        _MiniBtn(
                          icon: Icons.call_rounded,
                          label: 'اتصال',
                          color: BrandColors.brand600,
                          onTap: () =>
                              _launch(Uri.parse('tel:${row['phone']}')),
                        ),
                        _MiniBtn(
                          key: Key('wa-${row['id']}'),
                          icon: Icons.chat_rounded,
                          label: 'واتساب',
                          color: const Color(0xFF25D366),
                          onTap: () {
                            final digits = _digits(row['phone']);
                            _launch(
                                Uri.parse('https://wa.me/$digits'));
                          },
                        ),
                        _MiniBtn(
                          key: Key('msg-${row['id']}'),
                          icon: Icons.send_rounded,
                          label: 'رسالة',
                          color: BrandColors.goldDark,
                          onTap: _openMsg,
                        ),
                      ] else
                        Text('لا يوجد رقم هاتف',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: BrandColors.mut2)),
                      if (!isArchive) ...[
                        _MiniBtn(
                          icon: Icons.low_priority_rounded,
                          label: 'تخطّي',
                          color: BrandColors.goldDark,
                          onTap: () {
                            ref
                                .read(queueViewProvider.notifier)
                                .skip(row);
                            _snack('نُقل لآخر الدور');
                          },
                        ),
                        _MiniBtn(
                          key: Key('edit-${row['id']}'),
                          icon: Icons.edit_rounded,
                          label: 'تعديل',
                          color: BrandColors.brand600,
                          onTap: _openEdit,
                        ),
                        _MiniBtn(
                          key: Key('cancel-${row['id']}'),
                          icon: Icons.close_rounded,
                          label: 'إلغاء',
                          color: BrandColors.red,
                          onTap: _confirmCancel,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// زر صغير موحّد لصف التواصل والأفعال في اللوحة.
class _MiniBtn extends StatelessWidget {
  const _MiniBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: .5)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
    );
  }
}


