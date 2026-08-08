/// ============================================================================
///  Debts Repository — port of repositories/debts.repository.js
/// ============================================================================
library;

import '../../core/utils/js_compat.dart';
import '../db/local_db.dart';
import 'base_repository.dart';

const _columns = [
  'id', 'patient_name', 'total_amount', 'paid_amount', 'remaining',
  'status', 'created_at', 'updated_at', '_mod', '_deleted', 'data', 'owner_uid',
  '_hlc', '_dirty', '_origin', 'server_seq', 'clinic_id',
  'patient_id',
];

class DebtsMonthlyTotals {
  const DebtsMonthlyTotals({required this.count, required this.remaining});

  final int count;
  final double remaining;
}

class DebtsRepository extends BaseRepository {
  DebtsRepository(LocalDb db) : super(db, 'debts', _columns);

  List<Row> getUnpaidDebts() {
    final oc = db.ownerClause();
    final rows = db.query(
      "SELECT * FROM debts WHERE _deleted = 0 AND status != 'paid'${oc.sql} "
      'ORDER BY updated_at DESC',
      oc.params,
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  List<Row> getDebtsByPatient(String patientName) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM debts WHERE _deleted = 0 AND patient_name = ?${oc.sql} '
      'ORDER BY updated_at DESC',
      [patientName, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// Phase 3.2b — indexed monthly debt totals (unpaid debts whose blob `date`
  /// falls in `month`, summing `remaining`). Ported verbatim.
  DebtsMonthlyTotals? getMonthlyTotals(String? month) {
    if (month == null || month.isEmpty) return null;
    final oc = db.ownerClause('AND');
    final rows = db.query(
      '''SELECT
         COUNT(*) AS cnt,
         ROUND(SUM(COALESCE(remaining, json_extract(data,'\$.remaining'), 0)), 2) AS rem
       FROM debts
       WHERE _deleted = 0 AND status != 'paid'
         AND IFNULL(json_extract(data,'\$.date'), '') LIKE ?${oc.sql}''',
      ['$month%', ...oc.params],
    );
    final row = rows.isNotEmpty ? rows.first : const <String, Object?>{};
    return DebtsMonthlyTotals(
      count: jsNumOr0(row['cnt']).toInt(),
      remaining: jsNumOr0(row['rem']),
    );
  }

  Row? markAsPaid(String id) {
    final debt = getById(id);
    if (debt == null) return null;
    final updated = {...debt, 'id': id, 'status': 'paid', '_mod': jsNow()};
    upsert(updated);
    return updated;
  }

  /// Add a payment — literal port INCLUDING the JS `||` coercion quirks
  /// (`Number(debt.paidAmount || debt.paid_amount) || 0`): a 0 value falls
  /// through to the snake_case column, exactly like the original.
  Row? addPayment(String id, num amount) {
    final debt = getById(id);
    if (debt == null) return null;
    final paidAmount =
        jsNumOr0(jsOr(debt['paidAmount'], debt['paid_amount'])) +
            jsNumber(amount);
    final remaining =
        jsNumOr0(jsOr(jsOr(debt['totalAmount'], debt['total_amount']),
                debt['total'])) -
            paidAmount;
    final updated = <String, Object?>{
      ...debt,
      'id': id,
      'paidAmount': paidAmount,
      'paid_amount': paidAmount,
      'remaining': remaining > 0 ? remaining : 0,
      '_mod': jsNow(),
    };
    if (remaining <= 0) updated['status'] = 'paid';
    upsert(updated);
    return updated;
  }
}
