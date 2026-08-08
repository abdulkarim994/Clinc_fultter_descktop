/// ============================================================================
///  Generic, configuration-driven merge engine — port of merge/mergeEngine.js
/// ============================================================================
///
///  Three-way structural merge where a `base` (last-synced shadow) is
///  available; otherwise a safe two-way LWW fallback. PURE + dependency-free:
///  the HLC comparator is injected (defaults to the same total order as
///  hlc.dart), no I/O, deterministic regardless of arrival order.
///
///  For a scalar:
///    - local == remote                    → that value (no conflict)
///    - base known and local == base       → remote changed only → remote
///    - base known and remote == base      → local changed only  → local
///    - otherwise (diverged / no base)     → LWW by row HLC, deterministic tie.
library;

import 'descriptors.dart';

export 'descriptors.dart'
    show MergeStrategy, scalarStrategy, objectStrategy, arrayByIdStrategy;

/// The MISSING sentinel — the Dart twin of the JS `Symbol('missing')` +
/// `undefined` union (Dart has no undefined; this sentinel covers both).
final class Missing {
  const Missing._();
  @override
  String toString() => '<missing>';
}

const missing = Missing._();

bool _has(Object? v) => !identical(v, missing);

/// Default HLC total order — kept identical to hlc.dart `isNewer` (copied, not
/// imported, exactly like the JS original keeps its own copy to stay
/// dependency-free).
bool defaultIsNewer(String? a, String? b) {
  if (b == null || b.isEmpty) return true;
  if (a == null || a.isEmpty) return false;
  final ap = a.split(':');
  final bp = b.split(':');
  int n(List<String> p, int i) =>
      i < p.length ? (int.tryParse(p[i]) ?? 0) : 0;
  if (n(ap, 0) != n(bp, 0)) return n(ap, 0) > n(bp, 0);
  if (n(ap, 1) != n(bp, 1)) return n(ap, 1) > n(bp, 1);
  final ad = ap.length > 2 ? ap[2] : '';
  final bd = bp.length > 2 ? bp[2] : '';
  return ad.compareTo(bd) > 0;
}

/// Structural equality (order-insensitive for plain maps) — deepEqual twin.
bool deepEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k)) return false;
      if (!deepEqual(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List || b is List || a is Map || b is Map) return false;
  return a == b; // scalars (int 1 == double 1.0, mirroring JS ===)
}

/// Merge context — row HLCs + comparator + tie preference.
class MergeCtx {
  const MergeCtx({
    this.localHlc,
    this.remoteHlc,
    required this.isNewer,
    this.preferOnTie = 'local',
    this.localMeta = const {},
    this.remoteMeta = const {},
    this.path = const [],
  });

  final String? localHlc;
  final String? remoteHlc;
  final bool Function(String?, String?) isNewer;
  final String preferOnTie;

  /// v27 — ساعات الحقول (مسار الورقة → HLC) لكل جانب، ومسار العقدة الحالي.
  final Map<String, String> localMeta;
  final Map<String, String> remoteMeta;
  final List<String> path;

  MergeCtx child(String seg) => MergeCtx(
        localHlc: localHlc,
        remoteHlc: remoteHlc,
        isNewer: isNewer,
        preferOnTie: preferOnTie,
        localMeta: localMeta,
        remoteMeta: remoteMeta,
        path: [...path, seg],
      );

  /// حسم ورقة بساعتها الخاصة إن وُجدت على أي جانب: 1 محلي، -1 بعيد، 0 لا
  /// معلومة (فيعود القرار لقاعدة الأصل بساعة الصف).
  int leafDecision() {
    if (path.isEmpty) return 0;
    final key = joinFieldPath(path);
    final l = localMeta[key];
    final r = remoteMeta[key];
    if (l == null && r == null) return 0;
    if (l != null && r == null) return 1;
    if (l == null && r != null) return -1;
    if (l == r) return 0;
    return isNewer(l, r) ? 1 : -1;
  }
}

/// ترميز مسار الورقة (توأم config_fmeta.joinPath — منسوخ ليبقى المحرك نقياً).
String joinFieldPath(List<String> segs) => segs
    .map((s) => s.replaceAll('~', '~0').replaceAll('/', '~1'))
    .join('/');

/// Row-level LWW pick between a local and a remote value. Deterministic tie:
/// keep `preferOnTie` (default 'local' — a background pull never clobbers an
/// equal-clock local edit).
Object? _lwwPick(Object? local, Object? remote, MergeCtx ctx) {
  if (ctx.isNewer(ctx.remoteHlc, ctx.localHlc)) {
    return _has(remote) ? remote : local;
  }
  if (ctx.isNewer(ctx.localHlc, ctx.remoteHlc)) {
    return _has(local) ? local : remote;
  }
  // equal / incomparable clocks
  return (ctx.preferOnTie == 'remote' && _has(remote))
      ? remote
      : (_has(local) ? local : remote);
}

String _jsTypeName(Object? v) {
  if (v is bool) return 'boolean';
  if (v is num) return 'number';
  if (v is String) return 'string';
  return 'object';
}

int _setCompare(Object? a, Object? b) {
  final ta = _jsTypeName(a);
  final tb = _jsTypeName(b);
  if (ta != tb) return ta.compareTo(tb) < 0 ? -1 : 1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
  return 0;
}

List<Object?> _asList(Object? v) => v is List ? v : const [];

Iterable<Object?> _keysOf(Object? v) => v is Map ? v.keys : const [];

Object? _fieldOf(Object? container, Object? key) {
  if (container is Map && container.containsKey(key)) return container[key];
  return missing;
}

/// Core recursive merge for one value node. [base]/[local]/[remote] may be the
/// [missing] sentinel.
Object? mergeNode(
  MergeStrategyLike strategy,
  Object? base,
  Object? local,
  Object? remote,
  MergeCtx ctx,
) {
  final kind = strategy.kind;

  // Presence reconciliation shared by every kind.
  if (!_has(local) && !_has(remote)) return missing;
  if (!_has(local)) return _has(base) ? _lwwPick(base, remote, ctx) : remote;
  if (!_has(remote)) return _has(base) ? _lwwPick(local, base, ctx) : local;

  switch (kind) {
    case 'atomic':
    case 'lww':
      // Whole subtree as one opaque value decided by row HLC.
      if (deepEqual(local, remote)) return local;
      if (_has(base)) {
        if (deepEqual(local, base)) return remote;
        if (deepEqual(remote, base)) return local;
      }
      return _lwwPick(local, remote, ctx);

    case 'set':
      {
        // Order-insensitive union of primitives with 3-way removal awareness.
        final bA = _has(base) ? _asList(base) : const <Object?>[];
        final lA = _asList(local);
        final rA = _asList(remote);
        final inL = Set<Object?>.of(lA);
        final inR = Set<Object?>.of(rA);
        final inB = Set<Object?>.of(bA);
        final out = <Object?>[];
        for (final v in <Object?>{...lA, ...rA}) {
          final removedByLocal = inB.contains(v) && !inL.contains(v);
          final removedByRemote = inB.contains(v) && !inR.contains(v);
          if (removedByLocal || removedByRemote) continue; // honor a delete
          out.add(v);
        }
        out.sort(_setCompare); // deterministic, order-independent output
        return out;
      }

    case 'object':
      {
        final fields = strategy.fields;
        final def = strategy.defaultStrategy ?? scalarStrategy;
        final keys = <Object?>{
          ...(_has(base) ? _keysOf(base) : const []),
          ..._keysOf(local),
          ..._keysOf(remote),
        };
        final out = <String, Object?>{};
        for (final k in keys) {
          final sub = fields[k] ?? def;
          final bv = _has(base) ? _fieldOf(base, k) : missing;
          final lv = _fieldOf(local, k);
          final rv = _fieldOf(remote, k);
          // v27 — المسار يمتد هنا أيضاً حتى تتطابق مفاتيح ساعات الحقول.
          final merged = mergeNode(sub, bv, lv, rv, ctx.child('$k'));
          if (_has(merged)) out[k as String] = merged;
        }
        return out;
      }

    case 'arrayById':
      {
        final idKey = strategy.idKey;
        final tomb = strategy.tombstoneKey;
        final elemStrat = strategy.element ?? objectStrategy();
        Map<Object?, Map> index(Object? arr) {
          final m = <Object?, Map>{};
          if (arr is List) {
            for (final el in arr) {
              if (el is Map && el[idKey] != null) m[el[idKey]] = el;
            }
          }
          return m;
        }

        final bM = _has(base) ? index(base) : <Object?, Map>{};
        final lM = index(local);
        final rM = index(remote);
        bool isTomb(Map? el) => el != null && _numOf(el[tomb]) == 1;
        // A side has DELETED an id when it carries an explicit tombstone OR it
        // had the element in the base and now omits it (the app deletes items
        // by physical removal, so an omission of a base element IS a delete).
        bool deletedBy(Map<Object?, Map> m, Object? id) =>
            m.containsKey(id) ? isTomb(m[id]) : bM.containsKey(id);

        final ids = <Object?>{...bM.keys, ...lM.keys, ...rM.keys};
        final out = <Object?>[];
        for (final id in ids) {
          final b = bM.containsKey(id) ? bM[id] : missing;
          final l = lM.containsKey(id) ? lM[id] : missing;
          final r = rM.containsKey(id) ? rM[id] : missing;
          // ANTI-RESURRECTION: once EITHER side has deleted the element it
          // converges to a DURABLE, canonical tombstone {idKey: id, tomb: 1}.
          // Delete always wins over a concurrent edit; the marker persists so
          // a stale replica or a re-add cannot resurrect it. Deterministic.
          if (deletedBy(lM, id) || deletedBy(rM, id)) {
            // v27 — الأشجار التي تعيش داخل إعدادات الحساب تحذف بالإسقاط
            // (emitTombstones: false) حفاظاً على توافق Vue؛ الحذف يظل
            // محسوماً لأن لقطة الأساس هي مرجع الكشف عند الجهاز الآخر.
            if (strategy.emitTombstones) {
              out.add(<String, Object?>{idKey: id, tomb: 1});
            }
            continue;
          }
          if (_has(l) && _has(r)) {
            final merged = mergeNode(
                elemStrat, b, l, r, ctx.child('$id'));
            if (_has(merged)) out.add(merged);
            continue;
          }
          if (_has(l)) {
            out.add(l); // genuine new local add (not in base)
            continue;
          }
          if (_has(r)) {
            out.add(r); // genuine new remote add
            continue;
          }
        }
        // Stable order by id string — deterministic across devices. (JS used
        // localeCompare; ids are uuids/plain keys where code-unit order agrees.)
        out.sort((x, y) => '${(x as Map)[idKey]}'.compareTo('${(y as Map)[idKey]}'));
        return out;
      }

    // v27 — اتحاد محض للخرائط: لا يفقد مفتاحاً أبداً (خريطة شواهد الحذف
    // `_tombs`؛ فقدان شاهد = بعث عنصر محذوف).
    case 'unionMap':
      {
        if (local is Map || remote is Map) {
          final keys = <Object?>{..._keysOf(local), ..._keysOf(remote)};
          final out = <String, Object?>{};
          for (final k in keys) {
            final lv = _fieldOf(local, k);
            final rv = _fieldOf(remote, k);
            final merged = mergeNode(strategy, missing, lv, rv, ctx);
            if (_has(merged)) out[k as String] = merged;
          }
          return out;
        }
        if (deepEqual(local, remote)) return local;
        return _lwwPick(local, remote, ctx);
      }

    // ── م48/v27 — الدمج البنيوي **العميق** (إضافة موثَّقة فوق الأصل) ──
    // الأصل يفكك المستوى الأول فقط، فقيمة كل مفتاح متداخل (خطة مريض
    // كاملة، بطاقة طبية كاملة، نسب عيادة كاملة) تبقى ورقة تُحسم بالساعة
    // الأحدث ⇒ جهاز يمسح عمل الآخر. هذا النوع يتعمق بالشكل نفسه:
    //   • الخرائط  → تكرار مفتاحاً بمفتاح بلا حد.
    //   • القوائم التي عناصرها كائنات بمعرّفات فريدة → دمج بالمعرّف
    //     (مراحل خطة العلاج تحمل id في Flutter وVue معاً) مع احترام
    //     الحذف **بلا كتابة شواهد قبور** (توافق Vue: لا مراحل شبحية).
    //   • القوائم المعلَنة في setKeys (الأمراض المزمنة) → اتحاد بوعي الحذف.
    //   • ما عدا ذلك (نص/رقم/قائمة بلا معرّفات) → LWW ثلاثي كالأصل.
    case 'deep':
      {
        final anyMap = local is Map || remote is Map;
        if (anyMap) {
          final keys = <Object?>{
            ...(_has(base) ? _keysOf(base) : const []),
            ..._keysOf(local),
            ..._keysOf(remote),
          };
          final out = <String, Object?>{};
          for (final k in keys) {
            final declared = strategy.fields[k];
            final sub = declared ??
                (strategy.setKeys.contains(k)
                    ? const MergeStrategy(kind: 'set')
                    : strategy);
            final bv = _has(base) ? _fieldOf(base, k) : missing;
            final lv = _fieldOf(local, k);
            final rv = _fieldOf(remote, k);
            final merged = mergeNode(sub, bv, lv, rv, ctx.child('$k'));
            if (_has(merged)) out[k as String] = merged;
          }
          return out;
        }
        if (local is List && remote is List) {
          final baseOk = !_has(base) || base is List;
          if (baseOk &&
              _allIdentified(local, strategy.idKey) &&
              _allIdentified(remote, strategy.idKey) &&
              (!_has(base) || _allIdentified(base, strategy.idKey))) {
            final byId = MergeStrategy(
              kind: 'arrayById',
              idKey: strategy.idKey,
              element: strategy, // العناصر تُدمج عميقاً أيضاً
              emitTombstones: false,
            );
            return mergeNode(byId, base, local, remote, ctx);
          }
        }
        // ورقة: أولاً ساعتها الخاصة (v27) — تحسم الجهاز الذي عدّلها فعلاً؛
        // فإن غابت الساعتان عدنا لقاعدة الأصل الثلاثية بساعة الصف.
        if (deepEqual(local, remote)) return local;
        final byField = ctx.leafDecision();
        if (byField > 0) return local;
        if (byField < 0) return remote;
        if (_has(base)) {
          if (deepEqual(local, base)) return remote;
          if (deepEqual(remote, base)) return local;
        }
        return _lwwPick(local, remote, ctx);
      }

    case 'scalar':
    default:
      if (deepEqual(local, remote)) return local;
      if (_has(base)) {
        if (deepEqual(local, base)) return remote; // only remote changed
        if (deepEqual(remote, base)) return local; // only local changed
      }
      return _lwwPick(local, remote, ctx);
  }
}

/// كل عناصر القائمة كائنات بمعرّف [idKey] غير فارغ **وفريد** — شرط الدمج
/// بالمعرّف؛ أي إخلال (عنصر قديم بلا معرّف أو تكرار) يُسقطنا لـ LWW الآمن
/// فلا تُفقد بيانات قديمة أبداً.
bool _allIdentified(Object? list, String idKey) {
  if (list is! List) return false;
  final seen = <Object?>{};
  for (final el in list) {
    if (el is! Map) return false;
    final id = el[idKey];
    if (id == null || (id is String && id.isEmpty)) return false;
    if (!seen.add(id)) return false; // معرّف مكرر
  }
  return true;
}

num _numOf(Object? v) {
  if (v is num) return v;
  if (v is bool) return v ? 1 : 0;
  if (v is String) return num.tryParse(v) ?? double.nan;
  return double.nan;
}

/// Public entry point: merge one record. Pass [missing] (or omit) for an
/// absent base/local/remote. Returns the merged domain map (caller re-stamps
/// sync columns).
Map<String, Object?> mergeRecordValues({
  MergeStrategyLike? strategy,
  Object? base = missing,
  Object? local = missing,
  Object? remote = missing,
  String? localHlc,
  String? remoteHlc,
  bool Function(String?, String?)? isNewer,
  String preferOnTie = 'local',
  Map<String, String> localMeta = const {},
  Map<String, String> remoteMeta = const {},
}) {
  final ctx = MergeCtx(
    localHlc: localHlc,
    remoteHlc: remoteHlc,
    isNewer: isNewer ?? defaultIsNewer,
    preferOnTie: preferOnTie == 'remote' ? 'remote' : 'local',
    localMeta: localMeta,
    remoteMeta: remoteMeta,
  );
  final root = strategy ?? objectStrategy();
  final merged = mergeNode(root, base, local, remote, ctx);
  if (merged is Map<String, Object?>) return merged;
  if (merged is Map) return Map<String, Object?>.from(merged);
  return <String, Object?>{};
}

/// Alias kept for signature readability — engine users need one import.
typedef MergeStrategyLike = MergeStrategy;
