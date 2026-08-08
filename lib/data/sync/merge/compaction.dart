/// ============================================================================
///  Tombstone compaction runner — literal port of sync/merge/compaction.js
/// ============================================================================
///
///  Thin, defensive I/O wrapper around the PURE `compactRowDomain`:
///   - horizon comes from the server as `sync.compaction.horizon` meta
///   - default horizon 0 ⇒ NO-OP (a missing/older server can never trigger an
///     unsafe prune)
///   - only field-merge-enabled entities with id-array strategies are touched
///   - only rows that actually changed are rewritten.
library;

import '../context.dart';
import '../db_sync.dart';
import '../entities.dart';
import '../feature_flags.dart';
import 'descriptors.dart';
import 'merge_engine.dart' show deepEqual;
import 'tombstones.dart';

/// Read the all-devices-safe compaction horizon (0 ⇒ never prune).
int getCompactionHorizon(SyncContext ctx) {
  final v =
      num.tryParse('${getMetaValue(ctx.db, compactionHorizonKey) ?? ''}');
  return (v != null && v.isFinite && v > 0) ? v.toInt() : 0;
}

/// Only entities whose strategy contains id-arrays can hold item tombstones.
Iterable<String> _entitiesWithArrays() =>
    syncEntities.where(entityStrategies.containsKey);

class CompactionReport {
  const CompactionReport(
      {required this.horizon, required this.scanned, required this.compacted});

  final int horizon;
  final int scanned;
  final int compacted;
}

/// Compact all eligible rows. Safe to call after every pull.
CompactionReport runCompaction(SyncContext ctx, {int? horizon}) {
  final h = horizon ?? getCompactionHorizon(ctx);
  if (h <= 0) {
    return const CompactionReport(horizon: 0, scanned: 0, compacted: 0);
  }

  var scanned = 0;
  var compacted = 0;
  for (final entity in _entitiesWithArrays()) {
    if (!isFieldMergeEnabled(entity)) continue; // engine off ⇒ no tombstones
    final repo = repoFor(ctx, entity);
    if (repo == null) continue;
    // Dirty rows suffice: a freshly-merged tombstone row is written through
    // the normal (dirty-tracked) path. Full sweeps intentionally avoided.
    final rows = getDirtyRows(ctx.db, entity);
    for (final row in rows) {
      scanned++;
      final next = compactRowDomain(entity, row, h);
      // compactRowDomain returns the SAME reference when nothing pruned.
      if (!identical(next, row) && !deepEqual(next, row)) {
        try {
          repo.upsert(Map<String, Object?>.from(next as Map));
          compacted++;
        } catch (_) {/* best-effort */}
      }
    }
  }
  return CompactionReport(horizon: h, scanned: scanned, compacted: compacted);
}
