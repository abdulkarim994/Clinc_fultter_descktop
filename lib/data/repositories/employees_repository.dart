/// ============================================================================
///  Employees Repository — موظفو العيادة (تمريض/إداريون) ورواتبهم.
/// ============================================================================
///
///  كيان متزامن جديد (دفعة المصروفات). لا جدول جديد على الخادم: يتدفّق عبر
///  `sync_rows` العام كبقية الكيانات (تحقّقنا أن `apply_changes` بلا قائمة
///  كيانات مسموحة، والمفتاح (user_id, entity, id) نصّي حر).
///
///  لكل موظف راتبٌ أساسي شهري (`base_salary`) قابل للتخصيص فردياً. المتبقّي
///  في شهرٍ ما يُحسب من سحوباته في جدول `expenses` (category =
///  `salary_withdrawal`) — لا يُخزَّن عمودُ متبقٍّ حتى لا ينحرف.
library;

import '../db/local_db.dart';
import 'base_repository.dart';

const _columns = [
  'id', 'clinic_id', 'name', 'role', 'base_salary', 'active', 'sort', 'note',
  'created_at', 'updated_at',
  '_mod', '_hlc', '_deleted', '_dirty', '_origin', 'server_seq', 'owner_uid',
  'data',
];

class EmployeesRepository extends BaseRepository {
  EmployeesRepository(LocalDb db) : super(db, 'employees', _columns);

  /// كل الموظفين غير المحذوفين، مرتّبين حسب الترتيب اليدوي ثم الاسم.
  List<Row> getAllSorted() {
    final oc = db.ownerClause();
    final rows = db.query(
      'SELECT * FROM employees WHERE _deleted = 0${oc.sql} '
      'ORDER BY sort ASC, name ASC',
      oc.params,
    );
    return [for (final r in rows) parseRowData(r)!];
  }
}
