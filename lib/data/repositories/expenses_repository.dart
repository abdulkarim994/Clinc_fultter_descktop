/// ============================================================================
///  Expenses Repository — مصروفات العيادة.
/// ============================================================================
///
///  الفئات (`category`):
///    • `salary_withdrawal` — سحب راتب موظف (`employee_id` مضبوط، `date` تاريخ السحب)
///    • `cleaning`          — مواد التنظيف
///    • `dental`            — المواد السنية / مواد العيادة
///    • `other`             — مصروفات أخرى
///
///  كيان متزامن جديد يتدفّق عبر `sync_rows` العام (لا جدول خادم جديد). توحيد
///  السحوبات مع المصروفات في جدولٍ واحد يمنح إجمالياً واحداً واستعلامَ طباعةٍ
///  يومياً واحداً يشمل كل شيء.
library;

import '../db/local_db.dart';
import 'base_repository.dart';

const _columns = [
  'id', 'clinic_id', 'category', 'title', 'amount', 'date', 'employee_id',
  'payment', 'note', 'created_at', 'updated_at',
  '_mod', '_hlc', '_deleted', '_dirty', '_origin', 'server_seq', 'owner_uid',
  'data',
];

class ExpensesRepository extends BaseRepository {
  ExpensesRepository(LocalDb db) : super(db, 'expenses', _columns);

  /// بنود شهرٍ ما (`date` يبدأ بـ `YYYY-MM`)، أحدث أولاً. أساس القوائم
  /// والإجمالي الشهري. مرشّح [category] اختياري لقائمة قسمٍ بعينه.
  List<Row> getByMonth(String month, {String? category}) {
    final oc = db.ownerClause();
    final catSql = category == null ? '' : ' AND category = ?';
    final rows = db.query(
      'SELECT * FROM expenses WHERE _deleted = 0 AND date LIKE ?$catSql${oc.sql} '
      'ORDER BY date DESC, created_at DESC',
      ['$month%', ?category, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// بنود يومٍ بعينه (`date == day`, بصيغة `YYYY-MM-DD`) — أساس طباعة استهلاك
  /// اليوم في الدفعة القادمة.
  List<Row> getByDay(String day) {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM expenses WHERE _deleted = 0 AND date = ?${oc.sql} '
      'ORDER BY created_at DESC',
      [day, ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// مجموع سحوبات موظفٍ في شهر (فئة `salary_withdrawal`). أساس حساب المتبقّي
  /// — يصفّر تلقائياً مطلع كل شهر لأنه يقيّد بـ `date LIKE 'month%'`.
  double salaryWithdrawn(String month, String employeeId) {
    final oc = db.ownerClause();
    final r = db.queryFirst(
      "SELECT COALESCE(SUM(amount),0) AS s FROM expenses "
      "WHERE _deleted = 0 AND category = 'salary_withdrawal' "
      "AND employee_id = ? AND date LIKE ?${oc.sql}",
      [employeeId, '$month%', ...oc.params],
    );
    return ((r?['s'] as num?) ?? 0).toDouble();
  }

  /// سحوبات موظفٍ في شهر، أحدث أولاً (لتفصيل الموظف).
  List<Row> salaryWithdrawals(String month, String employeeId) {
    final oc = db.ownerClause();
    final rows = db.query(
      "SELECT * FROM expenses WHERE _deleted = 0 "
      "AND category = 'salary_withdrawal' AND employee_id = ? AND date LIKE ?"
      "${oc.sql} ORDER BY date DESC, created_at DESC",
      [employeeId, '$month%', ...oc.params],
    );
    return [for (final r in rows) parseRowData(r)!];
  }

  /// مجموع فئةٍ في شهر (للأقسام والإجمالي).
  double categoryTotal(String month, String category) {
    final oc = db.ownerClause();
    final r = db.queryFirst(
      "SELECT COALESCE(SUM(amount),0) AS s FROM expenses "
      "WHERE _deleted = 0 AND category = ? AND date LIKE ?${oc.sql}",
      [category, '$month%', ...oc.params],
    );
    return ((r?['s'] as num?) ?? 0).toDouble();
  }

  /// إجماليات مصروفات شهرٍ مقسّمةً حسب نوع الدفع (لدمجها في الخزينة/الأرباح):
  /// total = كل الفئات؛ cash = كاش/نقد/نقدي؛ xfer = ما عداها. الغياب = كاش.
  ({double total, double cash, double xfer}) monthExpenseTotals(String month) {
    final oc = db.ownerClause();
    final r = db.queryFirst(
      "SELECT COALESCE(SUM(amount),0) AS t, "
      "COALESCE(SUM(CASE WHEN COALESCE(payment,'كاش') IN ('كاش','نقد','نقدي') "
      "THEN amount ELSE 0 END),0) AS c, "
      "COALESCE(SUM(CASE WHEN COALESCE(payment,'كاش') NOT IN ('كاش','نقد','نقدي') "
      "THEN amount ELSE 0 END),0) AS x "
      "FROM expenses WHERE _deleted = 0 AND date LIKE ?${oc.sql}",
      ['$month%', ...oc.params],
    );
    double d(Object? v) => ((v as num?) ?? 0).toDouble();
    return (total: d(r?['t']), cash: d(r?['c']), xfer: d(r?['x']));
  }

  /// المسحوب التراكمي من راتب موظفٍ حتى نهاية [month] شاملاً (كل السحوبات
  /// المؤرّخة قبل أوّل الشهر التالي). أساس سياسة ترحيل الرواتب.
  double salaryWithdrawnThrough(String month, String employeeId) {
    final parts = month.split('-');
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final ny = m == 12 ? y + 1 : y;
    final nm = m == 12 ? 1 : m + 1;
    final boundary =
        '${ny.toString().padLeft(4, '0')}-${nm.toString().padLeft(2, '0')}-01';
    final oc = db.ownerClause();
    final r = db.queryFirst(
      "SELECT COALESCE(SUM(amount),0) AS s FROM expenses "
      "WHERE _deleted = 0 AND category = 'salary_withdrawal' "
      "AND employee_id = ? AND date < ?${oc.sql}",
      [employeeId, boundary, ...oc.params],
    );
    return ((r?['s'] as num?) ?? 0).toDouble();
  }
}
