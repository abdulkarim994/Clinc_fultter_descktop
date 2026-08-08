/// ============================================================================
///  Appointments Repository — port of repositories/appointments.repository.js
/// ============================================================================
library;

import 'dart:convert';

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';
import 'base_repository.dart';
import 'patients_repository.dart';

const _columns = [
  'id', 'patient_name', 'date', 'time', 'service', 'clinic',
  'notes', 'status', 'created_at', 'updated_at', '_mod', '_deleted', 'data',
  'owner_uid',
  '_hlc', '_dirty', '_origin', 'server_seq', 'clinic_id',
  'patient_id',
];

class AppointmentsRepository extends BaseRepository {
  AppointmentsRepository(LocalDb db) : super(db, 'appointments', _columns);

  /// Appointments for a specific date, ordered by time.
  List<Row> getByDate(String date) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM appointments WHERE _deleted = 0 AND date = ?${oc.sql} '
      'ORDER BY time ASC',
      [date, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Appointments within a date range (inclusive).
  List<Row> getByDateRange(String startDate, String endDate) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM appointments WHERE _deleted = 0 '
      'AND date >= ? AND date <= ?${oc.sql} ORDER BY date ASC, time ASC',
      [startDate, endDate, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Appointments for a specific patient (by display name).
  List<Row> getByPatient(String patientName) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM appointments WHERE _deleted = 0 '
      'AND patient_name = ?${oc.sql} ORDER BY date DESC',
      [patientName, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Phase H — one clinic's appointments on one date, isolated by the stable
  /// `clinic_id`, with a self-healing fallback to the legacy `clinic` NAME so
  /// pre-migration rows are never hidden. Empty clinic → global day list.
  List<Row> getByClinicDate(String? clinicId, String date) {
    final cid = clinicKeyFor(clinicId);
    if (cid.isEmpty) return getByDate(date);
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM appointments WHERE _deleted = 0 AND date = ? '
      "AND (clinic_id = ? OR (IFNULL(clinic_id,'') = '' AND IFNULL(clinic,'') = ?))${oc.sql} "
      'ORDER BY time ASC',
      [date, cid, cid, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Phase H — appointments for a stable patient link key, with a
  /// `patient_name` fallback for pre-migration rows.
  List<Row> getByPatientId(String? patientId) {
    final pid = (patientId ?? '').trim();
    if (pid.isEmpty) return const [];
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM appointments WHERE _deleted = 0 '
      "AND (patient_id = ? OR (IFNULL(patient_id,'') = '' AND TRIM(IFNULL(patient_name,'')) = ?))${oc.sql} "
      'ORDER BY date DESC',
      [pid, pid, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Upcoming appointments (today and future).
  List<Row> getUpcoming([int limit = 50]) {
    final today = getCurrentDate();
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM appointments WHERE _deleted = 0 AND date >= ?${oc.sql} '
      'ORDER BY date ASC, time ASC LIMIT ?',
      [today, ...oc.params, limit],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Cache appointments from the cloud — maps the server shape to repository
  /// storage, stamping the stable link keys and preserving the full original
  /// object in the `data` blob (no data loss).
  void cacheFromSupabase(List<Row>? appointments) {
    if (appointments == null || appointments.isEmpty) return;

    final mapped = <Row>[
      for (final a in appointments)
        () {
          final patientName = jsOr(a['name'], a['patient_name']);
          final clinic = a['clinic'];
          return <String, Object?>{
            'id': a['id'],
            'patient_name': patientName,
            'date': a['date'],
            'time': a['time'],
            'service': a['service'],
            'clinic': clinic,
            'notes': a['notes'],
            'status': jsOr(a['status'], 'pending'),
            'clinic_id':
                jsOr(a['clinic_id'], clinicKeyFor(clinic as String?)),
            'patient_id': jsOr(
                  a['patient_id'],
                  patientKeyFor(
                    name: patientName as String?,
                    phone: a['phone'] as String?,
                  ),
                ) ??
                '',
            '_mod': jsOr(a['_mod'], jsNow()),
            // store the full original object so no data is lost
            'data': jsonEncode(a),
          };
        }(),
    ];

    bulkUpsert(mapped);
  }

  /// Count appointments for a date.
  int countByDate(String date) {
    final oc = db.ownerClause();
    final result = db.queryFirst(
      'SELECT COUNT(*) as cnt FROM appointments '
      'WHERE _deleted = 0 AND date = ?${oc.sql}',
      [date, ...oc.params],
    );
    return (result?['cnt'] as int?) ?? 0;
  }
}
