/// ============================================================================
///  Sync DB helpers — literal port of sync/db.sync.js (single backend)
/// ============================================================================
///
///  Column-tolerant access for the delta engine: rows are read RAW and the
///  `data` blob is merged back so `_dirty/_deleted/_hlc` are always visible
///  regardless of where they are physically stored.
///
///  Invariants honoured (04-sync-conflict-retry-integrity):
///   - reads NEVER filter out `_deleted` rows (tombstones must be pushable)
///   - writes NEVER hard-delete
///
///  Cursor/attempts/quarantine metadata live in the native `sync_meta` table.
library;

import 'dart:convert';

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';
import '../db/schema_sql.dart';

/// Merge the `data` JSON blob into the row WITHOUT dropping sync flags.
Row? mergeRow(Row? row) {
  if (row == null) return null;
  final out = Map<String, Object?>.from(row);
  final data = out['data'];
  if (data is String) {
    try {
      final parsed = jsonDecode(data);
      if (parsed is Map<String, dynamic>) out.addAll(parsed);
    } catch (_) {/* keep raw */}
  }
  return out;
}

/// True iff the merged row is a dirty (un-pushed) local change.
bool isDirty(Row? row) => row != null && jsNumber(row['_dirty']) == 1;

/// True iff the row is a soft-delete tombstone.
bool isTombstone(Row? row) => row != null && jsNumber(row['_deleted']) == 1;

/// Entities whose `_dirty` is a real column usable by the indexed fast path.
///
/// م66/دفعة صفر-د — تصحيح تعليق مضلِّل: `records` و`xrays` عمودهما
/// **مُضاف بـ ALTER لا من المخطط الأساس**، وكان بلا ردم من الكتلة حتى م66
/// (فكانت صفوفهما القديمة لا تُرفع أبداً). الآن يُردَمان عبر
/// `phase1bRestTables` فصار المسار السريع صحيحاً لهما. prosthetics/
/// queue_patients/settings عمودها من المخطط الأساس فعلاً.
const Set<String> _dirtyColumnEntities = {
  'records', 'prosthetics', 'xrays', 'queue_patients', 'settings',
};

/// Entities promoted to real `_dirty` columns in Phase 1b — indexed fast path
/// allowed only after the one-time backfill flag is set.
const Set<String> _dirtyPromotedEntities = {'patients', 'appointments', 'debts'};

bool _canUseDirtyIndex(LocalDb db, String table) {
  if (_dirtyColumnEntities.contains(table)) return true;
  if (_dirtyPromotedEntities.contains(table)) {
    // isSyncColsPromoted() twin: the phase-1b backfill flag in `metadata`.
    try {
      return db
          .query('SELECT 1 FROM metadata WHERE key = ?',
              const [MigrationFlags.phase1b])
          .isNotEmpty;
    } catch (_) {
      return false;
    }
  }
  return false;
}

/// All dirty rows for a table, INCLUDING tombstones (merged rows).
List<Row> getDirtyRows(LocalDb db, String table) {
  List<Row> rows;
  try {
    rows = _canUseDirtyIndex(db, table)
        ? db.query('SELECT * FROM $table WHERE _dirty = 1') // indexed fast path
        : db.query('SELECT * FROM $table'); // blob-backed: scan + merge
  } catch (_) {
    return const [];
  }
  return [
    for (final r in rows)
      if (isDirty(mergeRow(r))) mergeRow(r)!,
  ];
}

/// Count dirty rows across a set of tables (status badge).
int countDirty(LocalDb db, Iterable<String> tables) {
  var n = 0;
  for (final t in tables) {
    n += getDirtyRows(db, t).length;
  }
  return n;
}

/// Read one row raw by id (tombstones included), blob merged back.
Row? getRowRaw(LocalDb db, String table, String? id) {
  if (id == null || id.isEmpty) return null;
  try {
    final row = db.queryFirst('SELECT * FROM $table WHERE id = ?', [id]);
    return mergeRow(row);
  } catch (_) {
    return null;
  }
}

// ── Sync metadata (cursor, attempts, quarantine, lastSyncTs) ────────────────
// Uses the `sync_meta` table (the native path of the original).

Object? getMetaValue(LocalDb db, String key) {
  try {
    final row =
        db.queryFirst('SELECT value FROM sync_meta WHERE key = ?', [key]);
    return row?['value'];
  } catch (_) {
    return null;
  }
}

void setMetaValue(LocalDb db, String key, Object? value,
    [String userId = '']) {
  try {
    db.execute(
      'INSERT OR REPLACE INTO sync_meta(key, value, user_id, updated_at) '
      "VALUES (?, ?, ?, datetime('now'))",
      [key, value is String ? value : value?.toString(), userId],
    );
  } catch (_) {/* best-effort */}
}

T getMetaJson<T>(LocalDb db, String key, T fallback) {
  final v = getMetaValue(db, key);
  if (v == null) return fallback;
  Object? candidate = v;
  if (v is String) {
    try {
      candidate = jsonDecode(v);
    } catch (_) {
      return fallback;
    }
  }
  return candidate is T ? candidate : fallback;
}

void setMetaJson(LocalDb db, String key, Object? obj) =>
    setMetaValue(db, key, jsonEncode(obj));
