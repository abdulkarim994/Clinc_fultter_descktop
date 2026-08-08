/// ============================================================================
///  م79 — سجلّ التدقيق: من فعل ماذا بأي سجلّ ومتى
/// ============================================================================
///
///  ما كان ناقصاً
///  ─────────────
///  `audit_log.dart` يسجّل **تغيّر الحقول** على الصف نفسه، وهو مفيد لعرض
///  «معدَّل» للمستخدم. لكنه لا يصلح سجلَّ تدقيق:
///
///    • **بلا فاعل** — يقول «تغيّر المبلغ من 500 إلى 300» ولا يقول من غيّره.
///    • **بلا اطّلاع** — فتحُ ملف مريض لا يُسجَّل، وهو **أكثر ما يُسأل عنه**
///      في تحقيق تسريب بيانات صحية.
///    • **قابل للتزوير** — يعيش على الصف المتزامن، فمن يكتب الصف يعيد كتابة
///      تاريخه.
///    • **يُسقط الأقدم** — سقف خمسين قيداً بلا إشعار.
///
///  ما يفعله هذا الملف
///  ──────────────────
///  قيود **تُضاف ولا تُعدَّل ولا تُحذف**، يحمل كلٌّ منها هوية الفاعل ومعرّف
///  الجهاز، وتُدفع إلى جدول خادمي بسياسة إدراج فقط (المهاجرة 0026).
///
///  ⚠ م82 — نُقل من `features/patients/` إلى هنا. سجلّ التدقيق **بنية
///  تحتية لا ميزة**: يكتب في جدول ويُدفع إلى الخادم، ويستعمله دافعٌ في
///  طبقة البيانات. وبقاؤه في الميزات كان يجعل `data/sync/audit_push.dart`
///  يستورد صعوداً — وهي الدورة نفسها التي كُسرت للمصادقة في هذه المرحلة.
///  (أنشأتُها أنا في م79، وكشفها اختبارُ الطبقات في م82.)
///
///  انضباط الخصوصية — وحدوده هنا
///  ────────────────────────────
///  قاعدة المشروع ألّا تدخل بيانات المرضى السجلّات (صفر `print`، وحاجب في
///  `error_log.dart`). وسجلّ التدقيق **استثناء مقصود من هذه القاعدة**:
///  سجلٌّ يقول «اطّلع أحدٌ على مريضٍ ما» بلا تحديد عديم القيمة، والسؤال
///  الذي وُجد لأجله هو «من اطّلع على ملف فلان؟».
///
///  فالتقسيم صريح:
///    • `entity_id` — **يُخزَّن كما هو**. هو جوهر الميزة لا تسريباً عارضاً.
///    • `detail`    — يمرّ عبر [redactPhi]. حقلٌ حرّ، وما يدخله عرضاً لا
///      يخدم التدقيق، فيُحجب.
///
///  والحماية تأتي من الطبقة الصحيحة لا من الإخفاء: الجدول الخادمي مقيَّد
///  بالمالك في RLS وسياسته **إدراج فقط** — فلا يقرؤه غير صاحبه، ولا يعيد
///  أحد كتابته، ولو كان هو المالك.
library;

import 'dart:convert';

import '../../core/error_log.dart' show redactPhi;
import '../../core/utils/uid.dart';
import '../db/local_db.dart';

/// أنواع الأحداث المسجَّلة. مجموعة مغلقة عمداً: سجلٌّ بأفعال حرّة النصّ
/// يصير غير قابل للاستعلام، وسجلٌّ لا يُستعلَم لا قيمة له.
class AuditAction {
  static const viewPatient = 'view.patient';
  static const viewXray = 'view.xray';
  static const exportPdf = 'export.pdf';
  static const editRecord = 'edit.record';
  static const deleteRecord = 'delete.record';
  static const login = 'auth.login';
  static const logout = 'auth.logout';
  static const unlock = 'auth.unlock';
  static const accountSwitch = 'auth.account_switch';
}

/// ماذا يُسجَّل من الاطّلاع — قرار متعمَّد.
///
/// تسجيل **كل نقرة** يُنتج آلاف الصفوف شهرياً ويُغرق السجلّ فيصير عديم
/// الفائدة عند التحقيق. المسجَّل هو ما يسأل عنه المدقّق فعلاً: فتح ملف
/// مريض، عرض صورة أشعة، تصدير PDF. وهي الأفعال التي **تُخرج** بيانات
/// صحية إلى عين إنسان أو إلى ملف.
const Set<String> kLoggedReadActions = {
  AuditAction.viewPatient,
  AuditAction.viewXray,
  AuditAction.exportPdf,
};

/// م120 — هوية موظف الجلسة الحالية (اسم الدخول اللاتيني) تُختم تلقائياً
/// في كل قيد تحت المفتاح `by`. تضبطها طبقة الواجهة عند الدخول والخروج
/// (applyStaffSession). **اسم الدخول لا الاسم الظاهر عمداً**: حاجب PHI
/// يحجب المقاطع العربية في detail، واللاتيني ينجو فيبقى السجل قابلاً
/// للفلترة بالموظف في شاشة النشاط.
String currentAuditStaff = '';

/// م121 — الاسم الظاهر لموظف الجلسة: يظهر في تذييل كل تقارير PDF
/// («طبعه: فلان») من مولّد الوثيقة المركزي. يعيش هنا (طبقة بيانات نقية)
/// كي لا تستورد الطباعة طبقة الودجات.
String currentAuditStaffDisplay = '';

/// يكتب قيداً. **لا يرمي أبداً**: سجلُّ تدقيق يُسقط شاشة المريض أسوأ من
/// سجلٍّ ناقص — والفشل هنا لا يمنع العمل السريري.
void recordAudit(
  LocalDb db, {
  required String action,
  String? entity,
  String? entityId,
  Map<String, Object?>? detail,
  int? at,
}) {
  try {
    // م120 — ختم هوية الموظف (يتغلب على أي by ممرَّر يدوياً — الجلسة أصدق).
    final d = <String, Object?>{
      ...?detail,
      if (currentAuditStaff.isNotEmpty) 'by': currentAuditStaff,
    };
    final actor = db.getOwnerUid();
    db.execute(
      'INSERT OR IGNORE INTO audit_events '
      '(id, at, actor_uid, device_id, action, entity, entity_id, detail, pushed) '
      'VALUES (?,?,?,?,?,?,?,?,0)',
      [
        genId(),
        at ?? DateTime.now().millisecondsSinceEpoch,
        actor,
        db.deviceId,
        action,
        entity,
        entityId,
        d.isEmpty ? null : jsonEncode(_sanitize(d)),
      ],
    );
  } catch (_) {
    // أفضل جهد — القرص ممتلئ أو الجدول غير موجود بعد على قاعدة قديمة.
  }
}

/// يحجب أي قيمة قد تحمل بيانات مريض. المفاتيح تبقى (أسماء حقول تقنية)،
/// والقيم النصّية تمرّ عبر الحاجب، والأعداد والمنطقيات تمرّ كما هي.
Map<String, Object?> _sanitize(Map<String, Object?> d) => {
      for (final e in d.entries)
        e.key: switch (e.value) {
          String s => redactPhi(s),
          num n => n,
          bool b => b,
          null => null,
          _ => redactPhi('${e.value}'),
        },
    };

/// قراءة القيود لعرضها أو تصديرها — الأحدث أولاً.
List<Row> readAudit(
  LocalDb db, {
  String? entity,
  String? entityId,
  int limit = 200,
}) {
  final where = <String>[];
  final params = <Object?>[];
  if (entity != null) {
    where.add('entity = ?');
    params.add(entity);
  }
  if (entityId != null) {
    where.add('entity_id = ?');
    params.add(entityId);
  }
  params.add(limit);
  return db.query(
    'SELECT * FROM audit_events '
    '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
    'ORDER BY at DESC LIMIT ?',
    params,
  );
}

/// القيود التي لم تُدفع بعد — يقرأها دافع السجلّ.
List<Row> unpushedAudit(LocalDb db, {int limit = 500}) => db.query(
      'SELECT * FROM audit_events WHERE pushed = 0 ORDER BY at ASC LIMIT ?',
      [limit],
    );

/// يعلّم القيود مدفوعةً بعد تأكيد الخادم.
///
/// **لا حذف**: القيد يبقى محلياً بعد دفعه. سجلٌّ يُمحى بعد إرساله يترك
/// الجهاز بلا تاريخ متى تعذّر الوصول إلى الخادم — وهو أسوأ وقتٍ لفقده.
void markAuditPushed(LocalDb db, List<String> ids) {
  if (ids.isEmpty) return;
  final marks = List.filled(ids.length, '?').join(',');
  db.execute('UPDATE audit_events SET pushed = 1 WHERE id IN ($marks)', ids);
}

int unpushedAuditCount(LocalDb db) {
  final r = db.queryFirst('SELECT COUNT(*) AS n FROM audit_events WHERE pushed = 0');
  return (r?['n'] as num? ?? 0).toInt();
}
