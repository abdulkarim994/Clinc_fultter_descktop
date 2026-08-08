/// ============================================================================
///  Shadow (baseline) store — literal port of sync/merge/shadowStore.js
/// ============================================================================
///
///  The 3-way merge needs a BASE: the last value this device knew the server
///  had for a row. Stored in the EXISTING `sync_meta` key/value store (zero
///  schema migration, fully additive):
///    key  = `shadow:<entity>:<id>`
///    value= JSON of the row's DOMAIN fields only.
library;

import 'dart:convert';

import '../../db/local_db.dart';
import '../db_sync.dart';
import 'merge_engine.dart' show missing;

String _keyFor(String entity, String id) => 'shadow:$entity:$id';

/// Read the baseline domain snapshot for a row, or null if none yet.
Map<String, Object?>? getShadow(LocalDb db, String entity, String? id) {
  if (entity.isEmpty || id == null || id.isEmpty) return null;
  final v = getMetaValue(db, _keyFor(entity, id));
  if (v is! String || v.isEmpty) return null;
  try {
    final parsed = jsonDecode(v);
    return parsed is Map ? Map<String, Object?>.from(parsed) : null;
  } catch (_) {
    return null;
  }
}

/// Write/replace the baseline domain snapshot for a row.
void setShadow(LocalDb db, String entity, String id, Object? domain) {
  if (entity.isEmpty || id.isEmpty || domain == null) return;
  setMetaValue(db, _keyFor(entity, id), jsonEncode(domain));
}

/// Clear the baseline (row deleted / tombstoned) to keep the store bounded.
void clearShadow(LocalDb db, String entity, String id) {
  try {
    setMetaValue(db, _keyFor(entity, id), null);
  } catch (_) {/* best-effort */}
}

/// Apply a planner's shadow instruction:
///   [missing] → leave untouched · null → clear · map → set.
void applyShadowPlan(LocalDb db, String entity, String id, Object? baseline) {
  if (identical(baseline, missing)) return;
  if (baseline == null) {
    clearShadow(db, entity, id);
    return;
  }
  setShadow(db, entity, id, baseline);
}
