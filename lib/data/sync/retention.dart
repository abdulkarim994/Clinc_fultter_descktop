/// م71 — احتفاظ المواعيد: شطب تلقائي بعد أسبوع + حذف فعلي من السحابة.
///
/// قرار المالك الصريح: «المواعيد تحذف بعد مضي أسبوع تلقائياً — ما في داعي
/// للأبد المواعيد تتخزن». نظام الدور يفعلها أصلاً يومياً (م56)؛ هذه الوحدة
/// تضيف النظير للحجز التقليدي، وتكمل الحلقة المفقودة في النظامين معاً:
/// الشطب وحده يترك شاهد قبر يعيش على الخادم للأبد — هنا يُستدعى
/// `purge_expired` (موجود على الخادم منذ زمن بلا مستدعٍ) ليحذف الشواهد
/// القديمة حذفاً فعلياً.
///
/// المهلتان — ولماذا ليستا رقماً واحداً
/// ─────────────────────────────────────
///   7 أيام  : عمر الموعد الماضي قبل شطبه. **بتاريخ الموعد نفسه** لا بوقت
///             آخر تعديل — موعد مستقبلي لا يُشطب مهما قدُم إنشاؤه.
///   30 يوماً: عمر الشاهد قبل حذفه النهائي من الخادم. الفارق مقصود:
///             الشاهد هو ما يُبلغ بقية الأجهزة بالحذف، فلو حُذف فور
///             الشطب لبقي الموعد حياً على جهاز كان مطفأً أياماً. ثلاثون
///             يوماً تغطي غياب أي جهاز واقعي؛ جهاز غائب أكثر من شهر قد
///             يعرض محلياً موعداً قديماً حُذف — مقبول ومصارَح به (نفس
///             فلسفة نافذة applied_ops وأفق الضغط 0013).
///
/// البوابات: الكنسة مرة يومياً، والحذف الخادمي مرة أسبوعياً — معلّقتان على
/// اكتمال دورة مزامنة (لا على فتح شاشة)، فتعملان حتى لو بقي التطبيق على
/// تبويب واحد طوال اليوم. الحالة في sync_meta لكل حساب.
///
/// الحذف الفعلي يشمل شواهد **كل** الكيانات (مواعيد، دور، سجلات، أشعة…) —
/// الشاهد الذي أدى مهمته التبليغية لا قيمة لبقائه أياً كان كيانه.
library;

import 'db_sync.dart' show getMetaValue, setMetaValue;
import 'engine.dart' show EngineStatus;
import 'context.dart';

/// عقد الحذف الفعلي للشواهد — SupabaseTransport ينفذه فوق RPC
/// `purge_expired`؛ الوضع المحلي بلا منفذ فيُمرَّر null وتصمت الخطوة.
abstract interface class TombstonePurge {
  /// يحذف شواهد قبور المستدعي الأقدم من [retainDays] حذفاً فعلياً.
  /// يعيد عدد المحذوف.
  Future<int> purgeExpired({required int retainDays});
}

class RetentionPolicy {
  const RetentionPolicy({
    this.appointmentsDays = 7,
    this.tombstoneRetainDays = 30,
    this.purgeEveryDays = 7,
  });

  /// عمر الموعد الماضي قبل الشطب (بتاريخ الموعد).
  final int appointmentsDays;

  /// عمر الشاهد قبل الحذف الفعلي من الخادم.
  final int tombstoneRetainDays;

  /// تواتر نداء الحذف الفعلي.
  final int purgeEveryDays;
}

class RetentionSweepResult {
  const RetentionSweepResult({required this.swept, required this.purged});

  /// مواعيد شُطبت في هذه الكنسة.
  final int swept;

  /// شواهد حُذفت فعلياً من الخادم (null = لم يحن موعد النداء أو لا منفذ).
  final int? purged;
}

String _dayKey(String uid) => 'retention_day_$uid';
String _purgeKey(String uid) => 'retention_purge_ms_$uid';

class RetentionSweeper {
  RetentionSweeper({
    required this.ctx,
    this.purge,
    this.policy = const RetentionPolicy(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SyncContext ctx;
  final TombstonePurge? purge;
  final RetentionPolicy policy;
  final DateTime Function() _now;

  String get _uid => ctx.db.getOwnerUid() ?? 'local';

  bool _busy = false;

  /// خطاف المحرك — يُسجَّل في statusListeners.
  void onEngineStatus(EngineStatus s) {
    if (s.phase != 'complete' || _busy) return;
    _busy = true;
    Future(() async {
      try {
        await sweep();
      } catch (_) {/* أفضل جهد — الدورة التالية تعيد */} finally {
        _busy = false;
      }
    });
  }

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// الكنسة الكاملة: شطب المواعيد القديمة (مرة يومياً) ثم الحذف الفعلي
  /// للشواهد (مرة أسبوعياً). قابلة للنداء اليدوي من الاختبارات.
  Future<RetentionSweepResult> sweep({bool force = false}) async {
    final today = _dateStr(_now());
    var swept = 0;

    // ── ١) شطب المواعيد الماضية — بوابة يوم ──────────────────────────────
    final lastDay = '${getMetaValue(ctx.db, _dayKey(_uid)) ?? ''}';
    if (force || lastDay != today) {
      swept = _sweepAppointments();
      setMetaValue(ctx.db, _dayKey(_uid), today, _uid);
    }

    // ── ٢) الحذف الفعلي للشواهد — بوابة أسبوع ────────────────────────────
    int? purged;
    final p = purge;
    if (p != null) {
      final lastMs =
          int.tryParse('${getMetaValue(ctx.db, _purgeKey(_uid)) ?? ''}') ?? 0;
      final due = _now().millisecondsSinceEpoch - lastMs >
          policy.purgeEveryDays * 24 * 60 * 60 * 1000;
      if (force || due) {
        // فشل النداء لا يقدّم البوابة — يُعاد مع الدورة المكتملة التالية.
        purged = await p.purgeExpired(retainDays: policy.tombstoneRetainDays);
        setMetaValue(ctx.db, _purgeKey(_uid),
            '${_now().millisecondsSinceEpoch}', _uid);
      }
    }

    return RetentionSweepResult(swept: swept, purged: purged);
  }

  /// شطب المواعيد التقليدية الأقدم من [RetentionPolicy.appointmentsDays].
  /// بتاريخ الموعد حصراً: بلا تاريخ أو بتاريخ مستقبلي/حديث ⇒ لا يُمسّ.
  /// الشطب عبر repo.delete: شاهد قبر بساعة جديدة + _dirty فينتشر بالمزامنة
  /// لكل الأجهزة (وdb.kickSync يدفعه فوراً).
  int _sweepAppointments() {
    final cutoff =
        _dateStr(_now().subtract(Duration(days: policy.appointmentsDays)));
    final oc = ctx.db.ownerClause();
    final rows = ctx.db.query(
      'SELECT id FROM appointments '
      "WHERE IFNULL(_deleted,0) = 0 AND IFNULL(date,'') <> '' "
      'AND date < ?${oc.sql}',
      [cutoff, ...oc.params],
    );
    for (final r in rows) {
      final id = '${r['id'] ?? ''}';
      if (id.isNotEmpty) ctx.repos.appointments.delete(id);
    }
    return rows.length;
  }
}
