/// ============================================================================
///  Prosthetics Repository — port of repositories/prosthetics.repository.js
/// ============================================================================
library;

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';
import 'base_repository.dart';

const _columns = [
  'id', 'patient_name', 'date', 'type', 'amount',
  'created_at', 'updated_at', '_mod', '_deleted', 'data',
  'clinic_id', '_hlc', '_dirty', '_origin', 'server_seq', 'owner_uid',
  'patient_id',
];

class ProstheticsMonthlyTotals {
  const ProstheticsMonthlyTotals({
    required this.count,
    required this.revenue,
    required this.labCost,
    required this.profit,
    required this.doctorShare,
    required this.clinicShare,
    required this.pCash,
    required this.pXfer,
  });

  final int count;
  final double revenue;
  final double labCost;
  final double profit;
  final double doctorShare;
  final double clinicShare;
  final double pCash;
  final double pXfer;
}

class ProstheticsRepository extends BaseRepository {
  ProstheticsRepository(LocalDb db) : super(db, 'prosthetics', _columns);

  List<Row> getByMonth(String month) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM prosthetics WHERE _deleted = 0 AND date LIKE ?${oc.sql} '
      'ORDER BY date DESC',
      ['$month%', ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Phase 3.2b — monthly prosthetics totals + the doctor cash/transfer split,
  /// two-part query ported verbatim (prosthetics table + prosthetic-debt-
  /// payment rows on records). The prosthetics cash test is ONLY 'كاش'.
  ProstheticsMonthlyTotals? getMonthlyTotals(String? month) {
    if (month == null || month.isEmpty) return null;
    final oc = db.ownerClause('AND');
    // Part A — the prosthetics table.
    final pRows = db.query(
      '''SELECT
         COUNT(*) AS cnt,
         ROUND(SUM(COALESCE(json_extract(data,'\$.total'), 0)), 2) AS revenue,
         ROUND(SUM(COALESCE(json_extract(data,'\$.labValue'), 0)), 2) AS labCost,
         ROUND(SUM(COALESCE(json_extract(data,'\$.clinicShare'), 0)), 2) AS clinicShare,
         ROUND(SUM(CASE WHEN COALESCE(json_extract(data,'\$.isDebt'),0)=0
                         AND json_extract(data,'\$.payment')='كاش'
                    THEN COALESCE(json_extract(data,'\$.doctorShare'),0) ELSE 0 END), 2) AS pCashPros,
         ROUND(SUM(CASE WHEN COALESCE(json_extract(data,'\$.isDebt'),0)=0
                         AND IFNULL(json_extract(data,'\$.payment'),'')<>'كاش'
                    THEN COALESCE(json_extract(data,'\$.doctorShare'),0) ELSE 0 END), 2) AS pXferPros
       FROM prosthetics
       WHERE _deleted = 0 AND date LIKE ?${oc.sql}''',
      ['$month%', ...oc.params],
    );
    // Part B — prosthetic-debt-payment rows on the records table.
    final dRows = db.query(
      '''WITH pd AS (
         SELECT json_extract(rec.data,'\$.payment') AS payment,
           COALESCE(json_extract(rec.data,'\$._docAmount'), rec.amount, 0) AS docAmt
         FROM records rec
         JOIN debts d ON d.id = rec.debtId AND d._deleted = 0
         WHERE rec._deleted = 0 AND rec.date LIKE ?
           AND COALESCE(rec.isDebtPayment,0) = 1
           AND json_extract(d.data,'\$.type') = 'prosthetic'
       )
       SELECT
         ROUND(SUM(CASE WHEN payment='كاش' THEN docAmt ELSE 0 END), 2) AS pCashPay,
         ROUND(SUM(CASE WHEN IFNULL(payment,'')<>'كاش' THEN docAmt ELSE 0 END), 2) AS pXferPay
       FROM pd''',
      ['$month%'],
    );
    final p = pRows.isNotEmpty ? pRows.first : const <String, Object?>{};
    final d = dRows.isNotEmpty ? dRows.first : const <String, Object?>{};
    final revenue = jsNumOr0(p['revenue']);
    final labCost = jsNumOr0(p['labCost']);
    final clinicShare = jsNumOr0(p['clinicShare']);
    final pCash = jsNumOr0(p['pCashPros']) + jsNumOr0(d['pCashPay']);
    final pXfer = jsNumOr0(p['pXferPros']) + jsNumOr0(d['pXferPay']);
    return ProstheticsMonthlyTotals(
      count: jsNumOr0(p['cnt']).toInt(),
      revenue: revenue,
      labCost: labCost,
      profit: round2(revenue - labCost),
      doctorShare: round2(pCash + pXfer),
      clinicShare: clinicShare,
      pCash: round2(pCash),
      pXfer: round2(pXfer),
    );
  }
}
