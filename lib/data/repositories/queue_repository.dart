/// ============================================================================
///  Queue Repository (نظام الدور) — port of repositories/queue.repository.js
/// ============================================================================
///
///  Fully isolated feature: touches ONLY `queue_patients`, never any other
///  entity. Syncs through the generic delta engine (registered in M2).
library;

import '../db/local_db.dart';
import 'base_repository.dart';

const _columns = [
  'id', 'clinic', 'clinic_id', 'date', 'period', 'seq',
  'patient_name', 'phone', 'status', 'est_time', 'est_manual',
  'notes', 'state', 'archive_seq', 'entered_at',
  'created_at', 'updated_at',
  '_mod', '_hlc', '_deleted', '_dirty', '_origin', 'server_seq', 'owner_uid',
  'data',
];

class QueueRepository extends BaseRepository {
  QueueRepository(LocalDb db) : super(db, 'queue_patients', _columns);

  /// All rows (any state) for a clinic + date, ordered for display.
  List<Row> getByClinicDate(String clinic, String date) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM queue_patients '
      'WHERE _deleted = 0 AND clinic = ? AND date = ?${oc.sql} '
      'ORDER BY period ASC, state ASC, seq ASC',
      [clinic, date, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Distinct future dates (> today) that already have at least one row.
  List<String> getUpcomingDates(String today) {
    final all = getAll();
    final set = <String>{
      for (final r in all)
        if (r['date'] is String &&
            (r['date'] as String).compareTo(today) > 0)
          r['date'] as String,
    };
    return set.toList()..sort();
  }

  /// Retention: soft-delete every queue row dated strictly before
  /// [cutoffDate]. Soft-deletes propagate through the normal sync engine.
  /// Returns the number of rows tombstoned.
  int purgeOlderThan(String cutoffDate) {
    final all = getAll();
    final stale = [
      for (final r in all)
        if (r['date'] is String &&
            (r['date'] as String).compareTo(cutoffDate) < 0)
          r,
    ];
    for (final row in stale) {
      delete(row['id'] as String);
    }
    return stale.length;
  }
}
