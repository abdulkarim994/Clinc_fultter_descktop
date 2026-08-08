/// ============================================================================
///  Records (treatments) Repository — port of records.repository.js
/// ============================================================================
library;

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';
import 'base_repository.dart';

const _columns = [
  'id', 'patient_name', 'date', 'service', 'amount', 'clinic',
  'created_at', 'updated_at', '_mod', '_deleted', 'data',
  'clinic_id', '_hlc', '_dirty', '_origin', 'server_seq', 'owner_uid',
  // Phase 2a hot financial columns (names match the record keys exactly so
  // prepareForStorage routes them to columns, not the blob).
  'payment', 'isDebt', 'isPros', 'isDebtPayment', 'debtId',
  'patient_id',
];

/// Monthly financial totals — mirror of getMonthlyTotals()'s return shape.
class RecordsMonthlyTotals {
  const RecordsMonthlyTotals({
    required this.count,
    required this.cash,
    required this.xfer,
    required this.total,
    required this.doctorShare,
    required this.clinicShare,
  });

  final int count;
  final double cash;
  final double xfer;
  final double total;
  final int doctorShare;
  final double clinicShare;
}

class RecordsRepository extends BaseRepository {
  RecordsRepository(LocalDb db) : super(db, 'records', _columns);

  List<Row> getByMonth(String month) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM records WHERE _deleted = 0 AND date LIKE ?${oc.sql} '
      'ORDER BY date DESC',
      ['$month%', ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// One keyset page of treatment records, newest first, excluding
  /// prosthetics (`isPros = 0`) to match the flat records list.
  PageResult getRecordsPage({
    int limit = 50,
    PageCursor? cursor,
    bool includePros = false,
  }) =>
      getPage(
        orderBy: 'date',
        dir: 'DESC',
        limit: limit,
        cursor: cursor,
        where: includePros ? '' : 'COALESCE(isPros,0) = 0',
      );

  /// Phase 4.1 — records by the stable `patient_id` link key (indexed).
  List<Row> getByPatientId(String? patientId) {
    if (patientId == null || patientId.isEmpty) return const [];
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM records WHERE _deleted = 0 AND patient_id = ?${oc.sql} '
      'ORDER BY date DESC',
      [patientId, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  List<Row> getByPatient(String patientName) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM records WHERE _deleted = 0 AND patient_name = ?${oc.sql} '
      'ORDER BY date DESC',
      [patientName, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Phase 2a — indexed monthly financial totals computed in SQL, proven 1:1
  /// at cent precision against the JS aggregate. Ported verbatim, including
  /// the per-row frozen `_rateSnapshot` doctor split and the prosthetic-debt-
  /// payment exclusion.
  RecordsMonthlyTotals? getMonthlyTotals(String? month, [num doctorPct = 50]) {
    if (month == null || month.isEmpty) return null;
    final oc = db.ownerClause('AND');
    final rows = db.query(
      '''WITH rec AS (
         SELECT amount, payment,
           COALESCE(isDebt,0) AS isDebt, COALESCE(isPros,0) AS isPros,
           COALESCE(isDebtPayment,0) AS isDebtPayment, debtId,
           COALESCE(json_extract(data,'\$.isAnalysis'),0) AS isAnalysis,
           json_extract(data,'\$._rateSnapshot.doctorPct') AS snapPct
         FROM records
         WHERE _deleted = 0 AND date LIKE ?${oc.sql}
       ),
       r AS (
         SELECT rec.*,
           CASE WHEN json_extract(d.data,'\$.type') = 'prosthetic' THEN 1 ELSE 0 END AS isProsDebtPay
         FROM rec LEFT JOIN debts d ON d.id = rec.debtId AND d._deleted = 0
       ),
       inc AS (
         -- نظام «التحاليل» — استبعاد صفوف التحاليل احترازاً (معزولة مالياً).
         SELECT * FROM r WHERE isProsDebtPay = 0 AND COALESCE(isAnalysis,0) = 0 AND (
           (isDebt = 0 AND isPros = 0 AND isDebtPayment = 0 AND IFNULL(payment,'') <> 'دين')
           OR isDebtPayment = 1)
       )
       SELECT
         SUM(CASE WHEN isDebtPayment = 0 THEN 1 ELSE 0 END) AS cnt,
         ROUND(SUM(CASE WHEN payment IN ('كاش','نقد','نقدي') THEN amount ELSE 0 END), 2) AS cash,
         ROUND(SUM(amount), 2) AS total,
         SUM(amount * (COALESCE(snapPct, ?) / 100.0)) AS docShareRaw
       FROM inc''',
      ['$month%', ...oc.params, doctorPct],
    );
    final row = rows.isNotEmpty ? rows.first : const <String, Object?>{};
    final cash = jsNumOr0(row['cash']);
    final total = jsNumOr0(row['total']);
    // Per-row split using each operation's frozen `_rateSnapshot` (COALESCE to
    // the live doctorPct only for legacy rows) — byte-parity with the JS sum.
    final doctorShare = jsRound(jsNumOr0(row['docShareRaw']));
    return RecordsMonthlyTotals(
      count: jsNumOr0(row['cnt']).toInt(),
      cash: cash,
      xfer: round2(total - cash),
      total: total,
      doctorShare: doctorShare,
      clinicShare: round2(total - doctorShare),
    );
  }
}
