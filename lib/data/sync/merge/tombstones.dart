/// ============================================================================
///  Item-tombstone lifecycle — literal port of sync/merge/tombstones.js
/// ============================================================================
///
///  1. DISPLAY    - [activeItems] hides `_deleted:1` items from the user while
///                  the tombstone stays in the persisted row for sync.
///  2. STAMPING   - [stampTombstoneSeqs] records on each tombstone the global
///                  `server_seq` at which the delete was applied. Idempotent.
///  3. COMPACTION - [compactRowDomain] physically removes a tombstone ONLY when
///                  provably safe on every device:
///                    prune ⇔ stamped birth seq S ≤ horizon H
///                  (H = lower bound of every device's applied server_seq).
///                  Fail-safe: no horizon (0) or unstamped tombstone (∞) → keep.
///
///  Pure & deterministic: no I/O, no clocks.
library;

import 'descriptors.dart';

const String defaultTombKey = '_deleted';
const String compactionHorizonKey = 'sync.compaction.horizon';
const String tombstoneSeqKey = '_seq';

num _numOf(Object? v) {
  if (v is num) return v;
  if (v is bool) return v ? 1 : 0;
  if (v is String) return num.tryParse(v) ?? double.nan;
  return double.nan;
}

/// Is this array element a tombstone (soft-deleted)?
bool isItemDeleted(Object? el, [String tombKey = defaultTombKey]) =>
    el is Map && _numOf(el[tombKey]) == 1;

/// The user-visible view of an id-array: everything that is NOT a tombstone.
/// RENDER time only — the stored array keeps the tombstones for sync.
List<Object?> activeItems(Object? arr, [String tombKey = defaultTombKey]) {
  if (arr is! List) return const [];
  return [
    for (final el in arr)
      if (!isItemDeleted(el, tombKey)) el,
  ];
}

/// Birth seq of a tombstone, or +∞ when it has not been stamped yet.
double _birthSeq(Object? el) {
  final s = el is Map ? el[tombstoneSeqKey] : null;
  if (s == null) return double.infinity;
  final n = _numOf(s);
  return n.isNaN ? double.infinity : n.toDouble();
}

// ── STAMPING ────────────────────────────────────────────────────────────────

Object? _stampNode(
    MergeStrategy? strategy, Object? value, num seq, String tombKey) {
  if (strategy == null || value == null) return value;
  if (strategy.kind == 'arrayById') {
    if (value is! List) return value;
    final tomb = strategy.tombstoneKey;
    final elem = strategy.element;
    return [
      for (final el in value)
        if (isItemDeleted(el, tomb))
          // Only stamp a tombstone that has no birth seq yet (idempotent).
          ((el as Map)[tombstoneSeqKey] == null
              ? (Map<String, Object?>.from(el)..[tombstoneSeqKey] = seq)
              : el)
        else
          _stampNode(elem, el, seq, tombKey), // recurse into nested arrays
    ];
  }
  if (strategy.kind == 'object' && value is Map) {
    final out = Map<String, Object?>.from(value);
    for (final k in out.keys.toList()) {
      out[k] = _stampNode(
          strategy.fields[k] ?? strategy.defaultStrategy, out[k], seq, tombKey);
    }
    return out;
  }
  return value;
}

/// Stamp every not-yet-stamped item tombstone in a row's DOMAIN with the given
/// server_seq. Call when persisting a merged, server-originated row.
Object? stampTombstoneSeqs(String entity, Object? domain, Object? seq,
    [String tombKey = defaultTombKey]) {
  if (domain == null || seq == null) return domain;
  final n = _numOf(seq);
  if (n.isNaN) return domain;
  return _stampNode(strategyForEntity(entity), domain, n, tombKey);
}

// ── COMPACTION ───────────────────────────────────────────────────────────────

Object? _compactNode(
    MergeStrategy? strategy, Object? value, num horizon, String tombKey) {
  if (strategy == null || value == null) return value;
  if (strategy.kind == 'arrayById') {
    if (value is! List) return value;
    final tomb = strategy.tombstoneKey;
    final elem = strategy.element;
    final out = <Object?>[];
    for (final el in value) {
      if (isItemDeleted(el, tomb)) {
        // Prune ONLY when provably applied everywhere: stamped AND ≤ horizon.
        if (_birthSeq(el) <= horizon) continue; // safe to drop
        out.add(el); // keep: unstamped (∞) or seq > horizon
      } else {
        out.add(_compactNode(elem, el, horizon, tombKey));
      }
    }
    return out;
  }
  if (strategy.kind == 'object' && value is Map) {
    final out = Map<String, Object?>.from(value);
    for (final k in out.keys.toList()) {
      out[k] = _compactNode(
          strategy.fields[k] ?? strategy.defaultStrategy, out[k], horizon, tombKey);
    }
    return out;
  }
  return value;
}

/// Copy of [domain] with every item tombstone that is safe at [horizon]
/// physically removed. Horizon 0/invalid → SAME reference (nothing pruned).
Object? compactRowDomain(String entity, Object? domain,
    [num horizon = 0, String tombKey = defaultTombKey]) {
  if (domain == null) return domain;
  final h = _numOf(horizon);
  if (h.isNaN || h <= 0) return domain; // fail-safe: no horizon → keep all
  return _compactNode(strategyForEntity(entity), domain, h, tombKey);
}
