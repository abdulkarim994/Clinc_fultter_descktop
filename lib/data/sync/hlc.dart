/// ============================================================================
///  Hybrid Logical Clock (HLC) — literal Dart port of services/sync/hlc.js
/// ============================================================================
///
///  Produces a monotonic, totally-ordered timestamp string:
///    `"<wallMillis>:<counter>:<deviceId>"`
///  It stays monotonic even when the device wall clock is wrong or moves
///  backwards, and the deviceId suffix guarantees a total order across devices.
///
///  Used by the sync engine as the `_hlc` value on every row, replacing the
///  fragile numeric `_mod` (epoch millis) last-write-wins comparison.
///
///  The JS module was a singleton with module-level state; the Dart port wraps
///  the state in a class (testable, resettable) and exposes a default global
///  instance [hlc] to mirror the original import style. The static comparators
///  [isNewer] / [hlcMillis] are pure functions, identical to the JS exports.
library;

import 'dart:async';

typedef HlcState = ({int ms, int counter});
typedef HlcPersister = void Function(HlcState state);

/// م77 — سقف الانحراف المقبول للساعة الواردة: 24 ساعة أمام الزمن الجداري.
///
///  لماذا حدٌّ أصلاً
///  ───────────────
///  كان [Hlc.receive] يتبنّى **أي** زمن وارد بلا شرط. فصفٌّ واحد يحمل ساعةً
///  لعام 2099 — من لوح ضُبط تاريخه خطأً أو صفٍّ فاسد — يُثبّت ساعة الجهاز
///  في المستقبل **إلى الأبد**: تُحفَظ على القرص فتصمد عبر إعادة التشغيل،
///  وكل كتابة لاحقة من ذلك الجهاز تهزم كتابات كل الأجهزة الأخرى في كل
///  تعارض. والأسوأ أنها **مُعدية**: الجهاز المسموم يدفع ساعته، وكل قرين
///  يستقبلها فيتبنّاها، فيتقارب الحساب كلّه على الساعة المكسورة.
///
///  لماذا أربع وعشرون ساعة تحديداً
///  ──────────────────────────────
///  الحدّ يجب أن يستوعب كل انحراف **مشروع**: فارق المناطق الزمنية (نحو 14
///  ساعة بين أقصى طرفين)، وتأخّر مزامنة NTP، وساعة عتاد منحرفة بدقائق.
///  و24 ساعة تغطّيها جميعاً بهامش، وهي في الوقت نفسه أصغر بمراتب من قفزة
///  السنوات التي تُنتج الاختطاف الدائم — وهي الفئة الوحيدة المستهدَفة.
const int kMaxClockDriftMs = 24 * 60 * 60 * 1000;

class Hlc {
  Hlc({this.maxDriftMs = kMaxClockDriftMs});

  /// قابل للحقن ليُفحص الحدّ في الاختبارات بلا انتظار ساعات حقيقية.
  final int maxDriftMs;

  int _lastMs = 0;
  int _counter = 0;

  // ── م77 — تشخيص الانحراف بلا تسجيل نصّي ───────────────────────────────
  // قاعدة هذا المشروع صفرُ `print`/`debugPrint` (تحقّقنا: صفر في 39 ألف
  // سطر)، فلا تُكسر لأجل تحذير. تُعرَض عدّادات بدلاً من ذلك يقرأها من
  // يشاء — شاشة الحالة أو اختبار — بلا فرض قناة تسجيل على الطبقة الأساس.

  /// عدد الساعات الواردة التي رُفض **زمنها** لتجاوزه الحدّ.
  int driftRejections = 0;

  /// آخر ساعة مرفوضة — للتشخيص فقط.
  String? lastRejectedHlc;

  /// عدد مرات إصلاح ساعة محفوظة مسمومة عند الإقلاع.
  int driftRepairs = 0;

  // ── Phase 4.3 — HLC persistence hook ──────────────────────────────────────
  // The clock lives in memory, so a process restart resets `_lastMs` to 0. If
  // the device wall clock has since moved backwards the regenerated HLCs could
  // compare OLDER than rows already written, corrupting last-writer-wins
  // ordering. The clock is therefore persisted and restore()d on boot so it
  // only ever moves FORWARD across restarts. `_persist` is an injected,
  // debounced sink; the core stays dependency-free and testable.
  HlcPersister? _persist;
  bool _persistScheduled = false;

  /// Register a sink that durably stores the clock state (debounced).
  void setPersister(HlcPersister? fn) => _persist = fn;

  void _schedulePersist() {
    if (_persist == null || _persistScheduled) return;
    _persistScheduled = true;
    // Coalesce bursts of ticks into one write on the next macrotask.
    Timer.run(() {
      _persistScheduled = false;
      try {
        _persist?.call((ms: _lastMs, counter: _counter));
      } catch (_) {/* best-effort */}
    });
  }

  /// Current clock state (for persistence).
  HlcState getState() => (ms: _lastMs, counter: _counter);

  /// Seed the clock from a persisted state on boot. Only ever advances the
  /// clock (never moves it backwards), so restoring a stale snapshot is
  /// harmless and a fresh install with no snapshot is a no-op.
  void restore(HlcState? state) {
    if (state == null) return;
    var ms = state.ms;
    var counter = state.counter;

    // م77 — إصلاح لمرة واحدة لساعة محفوظة مسمومة. جهاز سُمّم قبل هذه
    // النسخة يحمل ساعته المستقبلية على القرص، فيستعيدها عند كل إقلاع
    // ويظل يهزم الجميع حتى بعد وصول الحدّ إلى [receive]. الحدّ يمنع
    // العدوى الجديدة؛ هذا يشفي ما وقع.
    //
    // **آمن على جهاز سليم**: الشرط لا يتحقق أصلاً فلا يفعل شيئاً — ولهذا
    // يُشحن وقائياً بلا انتظار دليل إصابة.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (ms > now + maxDriftMs) {
      driftRepairs += 1;
      ms = now;
      counter = 0;
    }

    if (ms > _lastMs) {
      _lastMs = ms;
      _counter = counter;
    } else if (ms == _lastMs) {
      _counter = _counter > counter ? _counter : counter;
    }
  }

  /// Generate a new HLC for a local event.
  String tick(String? deviceId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now > _lastMs) {
      _lastMs = now;
      _counter = 0;
    } else {
      _counter += 1;
    }
    _schedulePersist();
    return '$_lastMs:$_counter:${(deviceId == null || deviceId.isEmpty) ? 'local' : deviceId}';
  }

  /// Advance the clock on receiving a remote HLC (call before merging).
  void receive(String? remoteHlc) {
    if (remoteHlc == null || remoteHlc.isEmpty) return;
    final parts = remoteHlc.split(':');
    final rawMs = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final rawC = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // م77 — حدّ الانحراف. **يُرفض الزمن لا الصف**: [receive] وظيفتها تقديم
    // الساعة فقط، والصف يُدمج بمحتواه كاملاً في مساره المعتاد. أثر الرفض
    // محصور في أن هذه الساعة لا تُسهم في تقدّم ساعتنا — فلا فقد بيانات
    // ولا تعطيل مزامنة، وهو الفارق بين حارس وحاجز.
    final trusted = rawMs <= now + maxDriftMs;
    if (!trusted) {
      driftRejections += 1;
      lastRejectedHlc = remoteHlc;
    }
    // صفرٌ يُخرج الوارد من حساب الحدّ الأعلى ومن مطابقات الحالات الأربع
    // أدناه دفعةً واحدة، فيؤول المنطق إلى «ساعتنا أو الزمن الجداري» — وهو
    // بالضبط السلوك المطلوب حيال ساعة لا نثق بها.
    final rMs = trusted ? rawMs : 0;
    final rC = trusted ? rawC : 0;

    final prevMs = _lastMs;
    _lastMs = [_lastMs, rMs, now].reduce((a, b) => a > b ? a : b);
    // دفعة صفر/ب — الفرع الرابع الناقص من خوارزمية HLC القياسية.
    //
    // كانت الحالات ثلاثاً فقط، و`else` تبتلع حالتين مختلفتين تماماً:
    //   • l' == now  (الزمن الفيزيائي تقدّم فعلاً) ⇒ العدّاد = 0  صحيح
    //   • l' == prevMs != rMs  (زمننا المنطقي هو الأكبر) ⇒ يجب += 1
    // الحالة الثانية هي **الغالبة عند كل سحب** لصفٍّ كُتب قبل آخر حدث محلي،
    // وتصفيرُ العدّاد فيها يكسر الرتابة: يصير حدثٌ لاحق أقدمَ من سابقه،
    // وتُعاد سلسلة HLC مستهلَكة حرفياً — و op_id = entity:id:hlc، فيقرّها
    // الخادم بلا تطبيق ويُمسح _dirty فتُفقد الكتابة بصمت (أُثبت باختبار).
    //
    // القاعدة القياسية: c = (l'==l_old ? max(c,rC[إن l'==rMs]) : ...)+1.
    // نصوغها صريحة بالحالات الأربع:
    if (_lastMs == rMs && _lastMs == prevMs) {
      // الزمن المنطقي ثابت والوارد يساويه ⇒ أكبر العدّادين + 1
      _counter = (_counter > rC ? _counter : rC) + 1;
    } else if (_lastMs == rMs) {
      // الوارد هو الأكبر ⇒ عدّاده + 1
      _counter = rC + 1;
    } else if (_lastMs == prevMs) {
      // زمننا المنطقي هو الأكبر (الحالة المفقودة) ⇒ عدّادنا + 1
      _counter = _counter + 1;
    } else {
      // الزمن الفيزيائي now تجاوز الكل ⇒ بداية جديدة
      _counter = 0;
    }
    _schedulePersist();
  }

  /// Test/support helper — reset to a pristine clock (no JS equivalent needed
  /// there because each test got a fresh module instance).
  void resetForTest() {
    _lastMs = 0;
    _counter = 0;
    _persist = null;
    _persistScheduled = false;
    driftRejections = 0;
    lastRejectedHlc = null;
    driftRepairs = 0;
  }
}

/// Default global clock instance (mirrors the JS module singleton).
final Hlc hlc = Hlc();

int _numOr0(String? s) => int.tryParse(s ?? '') ?? 0;

/// Returns true if HLC [a] is strictly newer than [b] (total order).
bool isNewer(String? a, String? b) {
  if (b == null || b.isEmpty) return true;
  if (a == null || a.isEmpty) return false;
  final ap = a.split(':');
  final bp = b.split(':');
  final am = _numOr0(ap.isNotEmpty ? ap[0] : null);
  final bm = _numOr0(bp.isNotEmpty ? bp[0] : null);
  if (am != bm) return am > bm;
  final ac = _numOr0(ap.length > 1 ? ap[1] : null);
  final bc = _numOr0(bp.length > 1 ? bp[1] : null);
  if (ac != bc) return ac > bc;
  final ad = ap.length > 2 ? ap[2] : '';
  final bd = bp.length > 2 ? bp[2] : '';
  return ad.compareTo(bd) > 0;
}

/// Parse the wall-clock millis component (for fast ORDER BY / display).
int hlcMillis(String? hlcValue) =>
    _numOr0((hlcValue ?? '').split(':').firstOrNull);

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
