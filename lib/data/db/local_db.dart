/// ============================================================================
///  LocalDb — the native SQL surface (mirror of services/sqlite-native.service)
/// ============================================================================
///
///  The Vue app routed every read/write through a small set of primitives
///  (query / queryFirst / execute / upsertRecord / bulkUpsert / softDelete /
///  ownerClause ...). This class is their literal Dart twin over
///  `package:sqlite3` (synchronous — the same execution model as
///  better-sqlite3 on the desktop build).
///
///  It also owns the cross-cutting state the JS services kept at module level:
///    • the account-isolation owner uid (defense-in-depth scoping)
///    • the persistent device id (metadata table — the JS twin mirrored
///      localStorage into the same metadata store)
///    • the HLC clock instance + its persistence into `metadata`
///    • the row <-> storage converters (parseRowData / prepareForStorage)
///    • the sync kick hook (wired by the sync engine in M2)
library;

import 'dart:convert';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart' as sq;

import '../../core/utils/js_compat.dart';
import '../sync/hlc.dart';
import 'bootstrap.dart';

/// A database row / record travelling through repositories and the sync
/// engine — the Dart twin of the plain JS object.
typedef Row = Map<String, Object?>;

typedef OwnerClause = ({String sql, List<Object?> params});

/// Kick hook — the delta sync engine registers itself here (M2). Mirrors the
/// lazy `import('sync/engine').kickSync()` in base.repository.js.
typedef SyncKick = void Function();

class LocalDb {
  LocalDb._(this.db, this.deviceId);

  /// Open (creating + migrating if needed) the clinic database at [path] and
  /// load the device id + HLC snapshot. Mirrors sqlite-core init order.
  factory LocalDb.open(String path,
      {bool phoneIdentityEnabled = false, String? encryptionKey}) {
    final db = openBootstrappedDb(path,
        phoneIdentityEnabled: phoneIdentityEnabled,
        encryptionKey: encryptionKey);
    final deviceId = _loadOrCreateDeviceId(db);
    final local = LocalDb._(db, deviceId);
    local._restoreHlc();
    return local;
  }

  /// Wrap an already-open (bootstrapped) handle — used by tests.
  factory LocalDb.fromDatabase(sq.Database db) {
    final deviceId = _loadOrCreateDeviceId(db);
    final local = LocalDb._(db, deviceId);
    local._restoreHlc();
    return local;
  }

  final sq.Database db;

  /// Stable per-install device id (suffix of every HLC this device mints).
  final String deviceId;

  /// This database's hybrid logical clock (persisted into `metadata`).
  final Hlc hlc = Hlc();

  SyncKick? _syncKick;

  /// The sync engine registers its kick here (no-op until M2 wires it).
  void setSyncKicker(SyncKick? kick) => _syncKick = kick;

  // دفعة صفر/ج — عمق المعاملة والركلة المؤجَّلة.
  //
  // مسارات المال متعددة الكتابات (حفظ زيارة بدين، دفع قسط، حذف تعاقبي)
  // كانت سلاسل upsert مستقلة بلا معاملة: انهيار في المنتصف يترك حالة نصفية
  // (دين بلا سجل دفعته، دخل شهر مختل) بلا مسار إصلاح. `transaction` تغلّفها
  // ذرّياً عبر SAVEPOINT المتداخلة، وتؤجّل ركلة المزامنة إلى ما بعد الالتزام
  // فتصير ركلةً واحدة للعملية كلها لا ركلةً لكل صف.
  int _txDepth = 0;
  bool _kickPending = false;

  /// Kick the delta sync engine after a local write (best-effort, never throws).
  /// أثناء معاملة: تؤجَّل الركلة إلى الالتزام النهائي.
  void kickSync() {
    if (_txDepth > 0) {
      _kickPending = true;
      return;
    }
    try {
      _syncKick?.call();
    } catch (_) {/* ignore */}
  }

  /// ينفّذ [body] ذرّياً. المعاملات تتداخل بأمان عبر SAVEPOINT، فيمكن أن
  /// يستدعي مسارٌ مغلَّف آخرَ مغلَّفاً (أو bulkUpsert) دون تعارض. الفشل يُرجع
  /// الحالة إلى ما قبل الغلاف الخارجي كاملاً. ركلة المزامنة تُطلق مرة واحدة
  /// بعد نجاح الغلاف الخارجي فقط.
  T transaction<T>(T Function() body) {
    final outer = _txDepth == 0;
    final sp = 'sp_${_txDepth}_${DateTime.now().microsecondsSinceEpoch}';
    if (outer) {
      db.execute('BEGIN');
    } else {
      db.execute('SAVEPOINT $sp');
    }
    _txDepth++;
    try {
      final result = body();
      _txDepth--;
      if (outer) {
        db.execute('COMMIT');
      } else {
        db.execute('RELEASE $sp');
      }
      if (outer && _kickPending) {
        _kickPending = false;
        try {
          _syncKick?.call();
        } catch (_) {/* ignore */}
      }
      return result;
    } catch (e) {
      _txDepth--;
      if (outer) {
        db.execute('ROLLBACK');
        _kickPending = false;
      } else {
        db.execute('ROLLBACK TO $sp');
        db.execute('RELEASE $sp');
      }
      rethrow;
    }
  }

  // ── Account-isolation owner scope (mirror of setOwnerUid/ownerClause) ─────
  String? _ownerUid;

  void setOwnerUid(String? uid) =>
      _ownerUid = (uid == null || uid.isEmpty) ? null : uid;

  String? getOwnerUid() => _ownerUid;

  /// Owner predicate + params. When an owner is active we accept rows that
  /// belong to this uid OR are unstamped legacy rows (owner_uid IS NULL).
  OwnerClause ownerClause([String prefix = 'AND']) {
    if (_ownerUid == null) return (sql: '', params: const []);
    return (
      sql: ' $prefix (owner_uid = ? OR owner_uid IS NULL)',
      params: [_ownerUid],
    );
  }

  // ── Primitives ─────────────────────────────────────────────────────────────

  List<Row> query(String sql, [List<Object?> params = const []]) {
    final rs = db.select(sql, params.map(_bindable).toList());
    return [for (final r in rs) Map<String, Object?>.from(r)];
  }

  Row? queryFirst(String sql, [List<Object?> params = const []]) {
    final rows = query(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  void execute(String sql, [List<Object?> params = const []]) {
    if (params.isEmpty) {
      db.execute(sql);
    } else {
      db.execute(sql, params.map(_bindable).toList());
    }
  }

  /// Insert-or-update one record — literal port of native.upsertRecord():
  /// only columns present on the record participate, and the conflict target
  /// is the `id` primary key.
  void upsertRecord(String table, Row record, List<String> columns) {
    final cols = columns.where(record.containsKey).toList();
    if (cols.isEmpty) return;
    final placeholders = List.filled(cols.length, '?').join(', ');
    final updates =
        cols.where((c) => c != 'id').map((c) => '$c = ?').join(', ');
    final values = [for (final c in cols) record[c]];
    final updateValues = [
      for (final c in cols)
        if (c != 'id') record[c],
    ];
    final sql = 'INSERT INTO $table (${cols.join(', ')}) '
        'VALUES ($placeholders) '
        'ON CONFLICT(id) DO UPDATE SET $updates';
    execute(sql, [...values, ...updateValues]);
  }

  /// Bulk insert-or-update inside one transaction (native.bulkUpsert twin).
  /// يعيد استخدام `transaction` كي يتداخل بأمان إن نُودي من داخل معاملة أكبر.
  void bulkUpsert(String table, List<Row> records, List<String> columns) {
    if (records.isEmpty) return;
    transaction(() {
      for (final r in records) {
        upsertRecord(table, r, columns);
      }
    });
  }

  /// Legacy soft delete (no tombstone stamping — kept only as the fallback the
  /// base repository uses when the row can't be read back).
  void softDelete(String table, String id) {
    final oc = ownerClause();
    execute(
      "UPDATE $table SET _deleted = 1, updated_at = datetime('now') "
      'WHERE id = ?${oc.sql}',
      [id, ...oc.params],
    );
  }

  /// Account-scoped read of one live row by id.
  Row? getById(String table, String id) {
    final oc = ownerClause();
    return queryFirst(
      'SELECT * FROM $table WHERE id = ? AND _deleted = 0${oc.sql}',
      [id, ...oc.params],
    );
  }

  /// Rows modified after [timestamp] (account-scoped; includes tombstones —
  /// identical to the JS original).
  List<Row> getModifiedSince(String table, int timestamp) {
    final oc = ownerClause();
    return query(
      'SELECT * FROM $table WHERE _mod > ?${oc.sql} ORDER BY _mod ASC',
      [timestamp, ...oc.params],
    );
  }

  void close() => db.close();

  // ── HLC persistence into metadata (hlcPersistence.js equivalent) ──────────

  static const _hlcMetaKey = 'hlc_state';

  void _restoreHlc() {
    final row = queryFirst(
        'SELECT value FROM metadata WHERE key = ?', const [_hlcMetaKey]);
    final raw = row?['value'];
    if (raw is String && raw.isNotEmpty) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        hlc.restore((
          ms: (m['ms'] as num?)?.toInt() ?? 0,
          counter: (m['counter'] as num?)?.toInt() ?? 0,
        ));
      } catch (_) {/* fresh install / corrupt snapshot — harmless */}
    }
    hlc.setPersister((s) {
      try {
        execute(
          'INSERT OR REPLACE INTO metadata(key, value, updated_at) '
          "VALUES (?, ?, datetime('now'))",
          [_hlcMetaKey, jsonEncode({'ms': s.ms, 'counter': s.counter})],
        );
      } catch (_) {/* best-effort */}
    });
  }

  // ── Device id (device.service.js equivalent, metadata-backed) ─────────────

  static const _deviceMetaKey = 'device_id';

  static String _loadOrCreateDeviceId(sq.Database db) {
    final rs = db.select(
        'SELECT value FROM metadata WHERE key = ?', const [_deviceMetaKey]);
    if (rs.isNotEmpty) {
      final v = rs.first['value'];
      if (v is String && v.isNotEmpty) return v;
    }
    final rnd = Random();
    final id = 'd${jsNow().toRadixString(36)}'
        '${List.generate(8, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[rnd.nextInt(36)]).join()}';
    db.execute(
      'INSERT OR REPLACE INTO metadata(key, value, updated_at) '
      "VALUES (?, ?, datetime('now'))",
      [_deviceMetaKey, id],
    );
    return id;
  }
}

/// Convert a Dart value into a SQLite-bindable one, matching how the JS bridge
/// stored values: nested objects/arrays are JSON-encoded, booleans become 0/1.
Object? _bindable(Object? v) {
  if (v is bool) return v ? 1 : 0;
  if (v is Map || v is List) return jsonEncode(v);
  return v;
}

// ── Row <-> storage converters (db-adapter.service.js twins) ────────────────

/// Merge the `data` JSON blob back over the columns — literal port of
/// parseRowData(): blob fields OVERWRITE column fields on clash, the raw
/// `data` string is kept, and `_deleted` is stripped from the result.
Row? parseRowData(Row? row) {
  if (row == null) return null;
  final result = Map<String, Object?>.from(row);
  final data = result['data'];
  if (data is String) {
    try {
      final parsed = jsonDecode(data);
      if (parsed is Map<String, dynamic>) {
        result.addAll(parsed);
      }
    } catch (_) {/* keep raw */}
  }
  result.remove('_deleted');
  return result;
}

/// Split a record into known columns + a serialized `data` blob of the rest,
/// stamping `_mod` / `updated_at` — literal port of prepareForStorage().
Row prepareForStorage(Row record, List<String> knownColumns) {
  final row = <String, Object?>{};
  final extra = <String, Object?>{};
  for (final e in record.entries) {
    if (knownColumns.contains(e.key)) {
      row[e.key] = e.value;
    } else {
      extra[e.key] = e.value;
    }
  }
  if (extra.isNotEmpty) {
    row['data'] = jsonEncode(extra);
  }
  row['_mod'] = jsNow();
  row['updated_at'] = jsIsoNow();
  return row;
}
