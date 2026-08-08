/// ============================================================================
///  app.config field-merge planner — literal port of sync/merge/configMerge.js
/// ============================================================================
///
///  `app.config` is a SINGLE settings key whose value bundles MANY independent
///  settings. Under whole-value LWW, two devices editing DIFFERENT parts
///  (A adds a clinic, B changes the currency) lose one side. This planner
///  3-way merges the config OBJECT itself with the shared structural engine so
///  independent sub-settings converge instead of clobbering. PURE — no I/O.
library;

import 'dart:convert';

import 'config_fmeta.dart';
import 'config_tombs.dart';
import 'descriptors.dart';
import 'merge_engine.dart';

class ConfigMergePlan {
  const ConfigMergePlan({
    required this.status,
    required this.value,
    required this.needsPush,
    this.hlc,
    required this.baseline,
  });

  final String status; // updated | kept-local | noop | merged
  final Map<String, Object?> value;
  final bool needsPush;
  final String? hlc; // fresh HLC on a genuine blend (status == 'merged')
  final Map<String, Object?> baseline; // server config snapshot
}

/// Decode a settings `value` that may be a JSON string (native raw) or map.
Map<String, Object?> decodeConfigValue(Object? v) {
  if (v == null) return {};
  if (v is Map<String, Object?>) return v;
  if (v is Map) return Map<String, Object?>.from(v);
  if (v is String) {
    try {
      final o = jsonDecode(v);
      if (o is Map) return Map<String, Object?>.from(o);
    } catch (_) {/* fall through */}
  }
  return {};
}

/// Compute the merge plan for the `app.config` value object. PURE.
ConfigMergePlan planConfigMerge({
  Map<String, Object?>? local,
  Map<String, Object?>? remote,
  Map<String, Object?>? base,
  String? localHlc,
  String? remoteHlc,
  bool Function(String?, String?)? isNewer,
  String Function(String?)? tick,
  String? deviceId,
}) {
  final cmp = isNewer ?? defaultIsNewer;
  final l = local ?? {};
  final r = remote ?? {};
  final b = base;

  // v27 — بعد الدمج نقلّم كل عنصر يحمل شاهد حذف صريحاً: القيمة المخزّنة
  // تبقى نظيفة (ولا تظهر مرحلة محذوفة في Vue) والحذف يتقارب حتماً.
  // v27 — ساعات الحقول: تُدمج بالأحدث لكل مسار، وتُحقن في سياق الدمج
  // فيُحسم كل حقل بساعته لا بساعة الصف كله.
  final lMeta = readFMeta(l);
  final rMeta = readFMeta(r);
  final mergedMeta = mergeFMeta(lMeta, rMeta, cmp);
  final merged = pruneTombstoned(mergeRecordValues(
    strategy: configStrategy,
    base: b ?? missing,
    local: l,
    remote: r,
    localHlc: localHlc,
    remoteHlc: remoteHlc,
    isNewer: cmp,
    localMeta: lMeta,
    remoteMeta: rMeta,
  ));
  if (mergedMeta.isNotEmpty) merged[kConfigFMetaKey] = mergedMeta;

  final equalsRemote = deepEqual(merged, r);
  final equalsLocal = deepEqual(merged, l);

  // Nothing to do — both sides already agree with the merged result.
  if (equalsRemote && equalsLocal) {
    return ConfigMergePlan(
        status: 'noop', value: r, needsPush: false, baseline: r);
  }
  // The merged result IS the server value → accept the server config.
  if (equalsRemote) {
    return ConfigMergePlan(
        status: 'updated', value: r, needsPush: false, baseline: r);
  }
  // The merged result IS our local value → remote carried nothing new; keep
  // local (idempotent). Shadow still advances to the server snapshot.
  if (equalsLocal) {
    return ConfigMergePlan(
        status: 'kept-local', value: l, needsPush: false, baseline: r);
  }
  // Genuine blend of BOTH sides → persist merged, stamp FRESH HLC, push.
  final fresh = tick != null
      ? tick(deviceId)
      : (cmp(remoteHlc, localHlc) ? remoteHlc : localHlc);
  return ConfigMergePlan(
    status: 'merged',
    value: merged,
    needsPush: true,
    hlc: fresh,
    baseline: r,
  );
}
