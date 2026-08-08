/// ============================================================================
///  Field-merge planner — literal port of sync/merge/fieldMerge.js
/// ============================================================================
///
///  PURE decision layer: (local, remote, shadow) → a concrete plan for the
///  pull/merge path. NO I/O — the conflict layer supplies rows, comparator and
///  a tick generator, then applies the returned plan.
///
///  Plan:
///    status    : inserted | updated | merged | kept-local | noop
///    row       : the row to upsert (null = write nothing)
///    needsPush : merged value differs from server → push (fresh newer HLC)
///    baseline  : shadow instruction — map (set) | null (clear) |
///                [missing] (leave untouched)
library;

import '../../../core/utils/js_compat.dart';
import 'descriptors.dart';
import 'merge_engine.dart';
import 'config_fmeta.dart' show kConfigFMetaKey;
import 'row_fmeta.dart' show mergeRowFMeta, readRowFMeta;
import 'recompute.dart';

typedef SyncRow = Map<String, Object?>;

class FieldMergePlan {
  const FieldMergePlan({
    required this.status,
    required this.row,
    required this.needsPush,
    required this.baseline,
  });

  final String status;
  final SyncRow? row;
  final bool needsPush;

  /// Map (set) | null (clear) | [missing] (leave untouched).
  final Object? baseline;
}

bool _isDel(Object? row) => row is Map && jsNumber(row['_deleted']) == 1;

SyncRow _serverRow(SyncRow remote, Map<String, Object?> domain) {
  return {
    ...domain,
    'id': remote['id'],
    if (remote.containsKey('clinic_id')) 'clinic_id': remote['clinic_id'],
    '_hlc': remote['_hlc'],
    '_deleted': _isDel(remote) ? 1 : 0,
    '_dirty': 0,
    if (remote.containsKey('_origin')) '_origin': remote['_origin'],
    if (remote.containsKey('server_seq')) 'server_seq': remote['server_seq'],
  };
}

/// Compute the merge plan (see module header for the plan shape).
FieldMergePlan planFieldMerge({
  required String entity,
  String? settingKey,
  SyncRow? local,
  required SyncRow remote,
  Map<String, Object?>? shadow,
  bool Function(String?, String?)? isNewer,
  String Function(String?)? tick,
  String? deviceId,
}) {
  final cmp = isNewer ?? defaultIsNewer;
  final strategy = entity == 'settings'
      ? strategyForSettingKey(settingKey)
      : strategyForEntity(entity);

  final rDom = splitSyncColumns(remote).domain;
  final lDom = local != null ? splitSyncColumns(local).domain : null;
  final bDom = shadow; // shadow is stored as the domain snapshot already

  // 1) No local row → take the server record verbatim.
  if (local == null) {
    return FieldMergePlan(
      status: 'inserted',
      row: _serverRow(remote, rDom),
      needsPush: false,
      baseline: _isDel(remote) ? null : rDom,
    );
  }

  // 2) Deletes resolve by row-HLC LWW, never field-merged. A tombstone on
  //    either side collapses the whole row.
  //    v31 — **الحذف يفوز على تعديل متزامن**: كان تعديلٌ محلي أحدث ساعةً
  //    يُبقي الصف فيُبعث المحذوف عند الجهاز الحاذف بعد دفعنا. الحذف قرار
  //    مقصود ونهائي (نفس قاعدة أقساط الدين وشواهد الإعدادات).
  if (_isDel(remote) && !_isDel(local)) {
    return FieldMergePlan(
      status: 'updated',
      row: _serverRow(remote, rDom),
      needsPush: false,
      baseline: null,
    );
  }
  // v32 — والاتجاه المعاكس أيضاً: شاهد قبر محلي لا يُبعث بتعديل وارد
  // أحدث ساعةً (كشفه الفحص العشوائي). وإن كان الشاهد قد دُفع سابقاً ثم
  // أعاد جهازٌ لم يرَ الحذف كتابة الصف حياً على الخادم — **يُعاد تعليم
  // الشاهد قذراً بساعة جديدة فيطارد البعثَ** حتى يستوعبه الجميع.
  if (_isDel(local) && !_isDel(remote)) {
    final wasDirty = jsNumber(local['_dirty']) == 1;
    if (wasDirty) {
      return FieldMergePlan(
        status: 'kept-local',
        row: null,
        needsPush: false,
        baseline: missing,
      );
    }
    final reassert = Map<String, Object?>.from(local);
    reassert['_deleted'] = 1;
    reassert['_dirty'] = 1;
    reassert['_hlc'] = tick != null
        ? tick(deviceId)
        : local['_hlc'];
    if (deviceId != null) reassert['_origin'] = deviceId;
    return FieldMergePlan(
      status: 'kept-local',
      row: reassert,
      needsPush: true,
      baseline: missing,
    );
  }
  if (_isDel(remote) || _isDel(local)) {
    if (cmp(remote['_hlc'] as String?, local['_hlc'] as String?)) {
      return FieldMergePlan(
        status: 'updated',
        row: _serverRow(remote, rDom),
        needsPush: false,
        baseline: _isDel(remote) ? null : rDom,
      );
    }
    // local (possibly a local delete) is newer/equal → keep local; push if dirty.
    return FieldMergePlan(
      status: jsNumber(local['_dirty']) == 1 ? 'kept-local' : 'noop',
      row: null,
      needsPush: false,
      baseline: missing,
    );
  }

  // 3) Field-level 3-way structural merge of the domain.
  // م81 — ساعات الحقول: تُقرأ من الجانبين وتُحقَن في سياق الدمج، فيُحسم
  // كل حقل بساعة الجهاز الذي لمسه لا بساعة الصف. صفٌّ قديم بلا `_fmeta`
  // يُنتج خريطة فارغة ⇒ leafDecision تعود صفراً ⇒ **المسار القديم حرفياً**.
  final lMeta = readRowFMeta(lDom);
  final rMeta = readRowFMeta(rDom);
  final mergedMeta = mergeRowFMeta(lMeta, rMeta, cmp);

  final mergedRaw = mergeRecordValues(
    strategy: strategy,
    base: bDom ?? missing,
    local: lDom ?? missing,
    remote: rDom,
    localHlc: local['_hlc'] as String?,
    remoteHlc: remote['_hlc'] as String?,
    isNewer: cmp,
    localMeta: lMeta,
    remoteMeta: rMeta,
  );
  // الخريطة المدموجة تُحمَل مع الناتج: بلا ذلك تُفقد الختمات عند أول مزج
  // فيعود الصف إلى حسم بساعة الصف في الدورة التالية.
  if (mergedMeta.isNotEmpty) mergedRaw[kConfigFMetaKey] = mergedMeta;

  // 3b) Recompute-after-merge: re-derive entity-specific derived fields from
  //     the just-merged inputs so multi-input derived values can never tear.
  final merged = applyRecompute(entity, mergedRaw);

  final equalsRemote = deepEqual(merged, rDom);
  final equalsLocal = deepEqual(merged, lDom);

  if (equalsLocal && equalsRemote) {
    return FieldMergePlan(
        status: 'noop', row: null, needsPush: false, baseline: rDom);
  }
  if (equalsLocal) {
    // Remote carried nothing new for us; do not rewrite/re-stamp (idempotent).
    return FieldMergePlan(
      status: jsNumber(local['_dirty']) == 1 ? 'kept-local' : 'noop',
      row: null,
      needsPush: false,
      baseline: rDom,
    );
  }
  if (equalsRemote) {
    // Fully accept the server value.
    return FieldMergePlan(
      status: 'updated',
      row: _serverRow(remote, rDom),
      needsPush: false,
      baseline: rDom,
    );
  }
  // Genuine blend of both sides → write merged, stamp a FRESH newer HLC, push.
  final fresh = tick != null
      ? tick(deviceId)
      : _newestHlc(remote['_hlc'] as String?, local['_hlc'] as String?);
  return FieldMergePlan(
    status: 'merged',
    row: {
      ...merged,
      'id': remote['id'],
      'clinic_id': remote['clinic_id'] ?? local['clinic_id'],
      '_hlc': fresh,
      '_deleted': 0,
      '_dirty': 1,
      '_origin': jsOr(deviceId, local['_origin']),
      'server_seq': remote['server_seq'],
    },
    needsPush: true,
    baseline: rDom, // server still holds rDom until our merged push lands
  );
}

String? _newestHlc(String? a, String? b) => defaultIsNewer(a, b) ? a : b;

/// Legacy row-LWW decision, used by verify/dual-run to compare (no I/O).
({String status, Map<String, Object?> domain}) legacyDecision(
  SyncRow? local,
  SyncRow remote, [
  bool Function(String?, String?)? isNewer,
]) {
  final cmp = isNewer ?? defaultIsNewer;
  if (local == null) {
    return (status: 'inserted', domain: splitSyncColumns(remote).domain);
  }
  if (jsNumber(local['_dirty']) == 1 &&
      !cmp(remote['_hlc'] as String?, local['_hlc'] as String?)) {
    return (status: 'kept-local', domain: splitSyncColumns(local).domain);
  }
  if (cmp(remote['_hlc'] as String?, local['_hlc'] as String?)) {
    return (status: 'updated', domain: splitSyncColumns(remote).domain);
  }
  return (status: 'noop', domain: splitSyncColumns(local).domain);
}

/// Effective domain a plan would leave in place (for verify comparison).
Map<String, Object?>? planEffectiveDomain(FieldMergePlan? plan, SyncRow? local) {
  if (plan?.row != null) return splitSyncColumns(plan!.row).domain;
  return local != null ? splitSyncColumns(local).domain : null;
}
