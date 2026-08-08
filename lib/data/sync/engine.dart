/// ============================================================================
///  Delta Sync Engine — literal port of sync/engine.js (behind SYNC_V2)
/// ============================================================================
///
///  Single-flight, push-then-pull reconciler: the local DB is authoritative;
///  the network is a background reconciler. Preserved semantics:
///   - single-flight guard: callers arriving mid-cycle AWAIT the in-flight
///     cycle (no phantom "check connection" failures)
///   - forced (user) sync bypasses backoff and re-runs after a ride-along
///   - exponential backoff (cap 5 min) on failure; rows never dropped
///   - hard per-cycle timeout so a hung RPC can never wedge a cycle open
///   - adaptive background poll: fast while active, relaxing when idle
///   - backlog drain: a capped push batch immediately kicks another cycle
library;

import 'dart:async';
import 'dart:math';

import 'context.dart';
import 'db_sync.dart';
import 'feature_flags.dart';
import 'pull.dart';
import 'push.dart';

const timerMs = 30 * 1000;
const idlePollMaxMs = 5 * 60 * 1000;
const kickDebounceMs = 600;
const backoffBase = 2 * 1000;
const backoffCap = 5 * 60 * 1000;
const lastSyncKey = 'sync.lastSyncTs';
const cycleTimeoutMs = 20 * 1000;

class CycleResult {
  const CycleResult({
    required this.ok,
    required this.status,
    required this.pushed,
    required this.merged,
  });

  final bool ok;

  /// ok | offline | error | backoff | disabled
  final String status;
  final int pushed;
  final int merged;
}

class EngineStatus {
  const EngineStatus({
    required this.online,
    required this.pending,
    required this.quarantined,
    this.lastSyncTs,
    this.phase,
    this.reason,
    this.pushed,
    this.merged,
    this.cursor,
  });

  final bool online;
  final int pending;
  final int quarantined;
  final int? lastSyncTs;
  final String? phase;
  final String? reason;
  final int? pushed;
  final int? merged;
  final int? cursor;
}

class SyncEngine {
  SyncEngine(this.ctx, {int? pollBaseMs, int Function()? idleCapMs})
      : _pollBase = pollBaseMs ?? timerMs,
        _idleCapMs = idleCapMs ?? (() => idlePollMaxMs);

  final SyncContext ctx;

  /// قاعدة الاستطلاع الدوري — أصل المحرك (timerMs = ٣٠ث): الإيقاع السريع
  /// أثناء النشاط. م54 — كانت تُحقن بإعداد «فاصل المزامنة» (syncMin
  /// بالدقائق، أرضية ٥) فانقلب التصميم رأساً على عقب: «الإيقاع السريع»
  /// صار ٥–٣٠ دقيقة، والجهاز المستقبِل لا يرى معالجة أُضيفت على الجهاز
  /// الآخر إلا بعد دقائق طويلة. syncMin يُحقن الآن سقفاً للخمول عبر
  /// [_idleCapMs] (انظر أدناه) فيبقى للمستخدم التحكم بأقصى فاصل.
  final int _pollBase;

  /// م54 — سقف تراخي الاستطلاع عند الخمول: دالة تُقرأ عند كل نبضة
  /// (فيسري تغيير الإعداد حياً بلا إعادة تشغيل). الافتراضي سقف الأصل
  /// (idlePollMaxMs = ٥ دقائق)، والموفر يمررها قارئةً syncMin.
  final int Function() _idleCapMs;

  /// م54 — مقرآن تشخيصيان (للاختبارات): يثبّتان أن القاعدة عادت لأصل
  /// المحرك (٣٠ث) وأن سقف الخمول يُقرأ حياً من الإعدادات.
  int get debugPollBaseMs => _pollBase;
  int get debugIdleCapMs => _idleCapMs();

  bool _started = false;
  bool _running = false;
  Future<CycleResult>? _runningFuture;
  Timer? _timer;
  Timer? _kickT;
  int _backoffUntil = 0;
  int _cycleRetries = 0;
  late int _pollDelay = _pollBase;
  final _rand = Random();

  // ── Event buses (JS listener-set twins) ───────────────────────────────────
  final List<void Function(String entity)> changeListeners = [];
  final List<void Function(EngineStatus s)> statusListeners = [];
  final List<void Function(({int merged, String reason}) info)>
      projectionListeners = [];

  void emitChanged(String entity) {
    for (final cb in changeListeners) {
      try {
        cb(entity);
      } catch (_) {/* ignore */}
    }
    if (isSyncV2Enabled()) kickSync();
  }

  void _emitStatus(EngineStatus s) {
    for (final cb in statusListeners) {
      try {
        cb(s);
      } catch (_) {/* ignore */}
    }
  }

  void _notifyProjection(({int merged, String reason}) info) {
    for (final cb in projectionListeners) {
      try {
        cb(info);
      } catch (_) {/* ignore */}
    }
  }

  int _nextBackoff() {
    final base =
        min(backoffBase * pow(2, _cycleRetries).toInt(), backoffCap);
    return base + _rand.nextInt(1000);
  }

  EngineStatus _buildCounts({
    String? phase,
    String? reason,
    int? pushed,
    int? merged,
    int? cursor,
  }) {
    var pending = 0;
    var quarantined = 0;
    int? lastSyncTs;
    try {
      pending = getPendingCount(ctx);
    } catch (_) {/* ignore */}
    try {
      quarantined = getQuarantinedCount(ctx);
    } catch (_) {/* ignore */}
    try {
      final v = num.tryParse('${getMetaValue(ctx.db, lastSyncKey) ?? ''}');
      lastSyncTs = (v != null && v > 0) ? v.toInt() : null;
    } catch (_) {/* ignore */}
    return EngineStatus(
      online: ctx.isOnline(),
      pending: pending,
      quarantined: quarantined,
      lastSyncTs: lastSyncTs,
      phase: phase,
      reason: reason,
      pushed: pushed,
      merged: merged,
      cursor: cursor,
    );
  }

  /// Bound a future so a hung transport can never wedge a cycle open.
  Future<T> _withTimeout<T>(Future<T> f, int ms, String label) =>
      f.timeout(Duration(milliseconds: ms),
          onTimeout: () => throw TimeoutException('$label timed out'));

  /// Run one push-then-pull cycle. Single-flight; explicit status on no-op.
  Future<CycleResult> runCycle(String reason, {bool force = false}) async {
    if (!isSyncV2Enabled()) {
      return const CycleResult(
          ok: false, status: 'disabled', pushed: 0, merged: 0);
    }
    // Coalesce with the in-flight cycle. EXCEPTION: a forced sync awaits it
    // then runs a fresh cycle so the newest edits push and newest rows pull.
    if (_running && _runningFuture != null) {
      if (!force) return _runningFuture!;
      try {
        await _runningFuture;
      } catch (_) {/* fall through to a fresh forced cycle */}
    }
    if (!ctx.isOnline()) {
      return const CycleResult(
          ok: false, status: 'offline', pushed: 0, merged: 0);
    }
    // Forced sync bypasses the backoff gate (explicit "try now").
    if (!force && DateTime.now().millisecondsSinceEpoch < _backoffUntil) {
      return const CycleResult(
          ok: false, status: 'backoff', pushed: 0, merged: 0);
    }

    _running = true;
    _runningFuture = _runCycleInner(reason);
    try {
      return await _runningFuture!;
    } finally {
      _running = false;
      _runningFuture = null;
    }
  }

  /// Never rejects: errors are caught and reported as status 'error'.
  Future<CycleResult> _runCycleInner(String reason) async {
    _emitStatus(_buildCounts(phase: 'start', reason: reason));

    var pushed = 0;
    var merged = 0;
    var ok = true;
    var drainMore = false;
    try {
      // م18/2 — عزل «أول مزامنة على جهاز فارغ»: جهاز لم يسحب قط (لا مؤشر
      // بعد) يسحب أولاً قبل أول دفع. التوأم الدلالي لملء loadAfterSync عند
      // الدخول في الأصل: حالة الحساب تصل محلياً وتُدمج (بنيوياً للإعدادات)
      // قبل أن يسافر أي صف محلي، فلا يسبق دفعُ config شبه فارغ بساعة أحدث
      // إعداداتِ الحساب على الخادم فيمسح خطط العلاج وقوائم العيادات.
      // بعد نجاح أول سحب يتقدم المؤشر فتعود الدورة push→pull حرفياً.
      // v31 — **سحب ثم دفع** (كان دفعاً ثم سحباً): الخادم يحسم الصف كاملاً
      // بالدفعة الأخيرة، فمن يدفع أولاً كان يفقد تعديله إذا دفع الآخر
      // لقطةً أقدم بعده. بالسحب أولاً يُدمج ما على الخادم حقلاً بحقل في
      // صفنا المحلي، ثم نَدفع **النتيجة المدموجة** — فلا يُمسح عمل أحد.
      final pl = await _withTimeout(pullOnce(ctx), cycleTimeoutMs, 'pull');
      merged = pl.merged;
      final pr =
          await _withTimeout(pushOnce(ctx), cycleTimeoutMs, 'push');
      pushed = pr.pushed;
      drainMore = pr.hasMore;

      _cycleRetries = 0;
      _backoffUntil = 0;
      setMetaValue(
          ctx.db, lastSyncKey, '${DateTime.now().millisecondsSinceEpoch}');
    } catch (_) {
      ok = false;
      _cycleRetries += 1;
      _backoffUntil = DateTime.now().millisecondsSinceEpoch + _nextBackoff();
    } finally {
      _emitStatus(_buildCounts(
        phase: ok ? 'complete' : 'error',
        reason: reason,
        pushed: pushed,
        merged: merged,
      ));
    }
    // Reactive projection: a pull that merged rows must refresh the UI.
    if (ok && merged > 0) _notifyProjection((merged: merged, reason: reason));
    // Backlog drain: the push batch was capped — kick another cycle now.
    if (ok && drainMore) kickSync(kickDebounceMs);
    // v28 — دورة أنتجت دمجاً وتركت صفوفاً غير مدفوعة (نتيجة الدمج نفسها
    // تُكتب محلياً بساعة جديدة): ادفعها **فوراً** بدل انتظار المؤقّت —
    // فيكفي ضغط «مزامنة» على الجهازين ليتطابقا بدل نصف دقيقة انتظار.
    if (ok && merged > 0 && !drainMore) {
      var pending = 0;
      try {
        pending = getPendingCount(ctx);
      } catch (_) {/* ignore */}
      if (pending > 0) kickSync(kickDebounceMs);
    }
    return CycleResult(
        ok: ok, status: ok ? 'ok' : 'error', pushed: pushed, merged: merged);
  }

  /// Debounced trigger (after local writes / `kickSync`).
  void kickSync([int delay = kickDebounceMs]) {
    if (!isSyncV2Enabled()) return;
    _pollDelay = _pollBase; // local activity → fast cadence
    _kickT?.cancel();
    _kickT = Timer(Duration(milliseconds: delay), () => runCycle('kick'));
  }

  void _schedulePoll(int delay) {
    _timer?.cancel();
    _timer = null;
    if (!_started) return;
    _timer = Timer(Duration(milliseconds: delay), _runPoll);
  }

  Future<void> _runPoll() async {
    _timer = null;
    if (!_started) return;
    if (ctx.isOnline()) {
      final r = await runCycle('timer');
      if (r.pushed > 0 || r.merged > 0) {
        _pollDelay = _pollBase;
      } else {
        // م54 — التراخي عند الخمول يتوقف عند سقف قابل للحقن (syncMin)،
        // ولا ينزل السقف تحت القاعدة مهما صغُر الإعداد.
        _pollDelay = min(_pollDelay * 2, max(_idleCapMs(), _pollBase));
      }
    }
    _schedulePoll(_pollDelay);
  }

  /// Start the engine (idempotent; no-op when SYNC_V2 is off). Also registers
  /// the LocalDb kick hook so repository writes trigger a debounced reconcile.
  void startEngine() {
    if (!isSyncV2Enabled() || _started) return;
    _started = true;
    ctx.db.setSyncKicker(kickSync);
    _pollDelay = _pollBase;
    _schedulePoll(_pollDelay);
    Timer(const Duration(milliseconds: 300), () => runCycle('start'));
  }

  /// Stop the engine and release timers (call on logout).
  void stopEngine() {
    _started = false;
    _running = false;
    _timer?.cancel();
    _timer = null;
    _kickT?.cancel();
    _backoffUntil = 0;
    _cycleRetries = 0;
    _pollDelay = _pollBase;
    ctx.db.setSyncKicker(null);
  }

  /// Force a reconcile now (user-initiated by default: bypasses backoff).
  Future<CycleResult> syncNow({bool force = true}) =>
      runCycle('manual', force: force);

  /// Re-arm quarantined rows then reconcile.
  Future<CycleResult> retryFailedAndSync() async {
    retryQuarantined(ctx);
    return runCycle('retry');
  }

  /// Snapshot of engine status (one-off reads).
  EngineStatus getEngineStatus() => _buildCounts(
        phase: _running ? 'running' : 'idle',
        cursor: getCursor(ctx),
      );
}
