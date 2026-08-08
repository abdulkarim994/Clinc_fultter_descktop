/// ============================================================================
///  م81 — إظهار التعارضات: ما كان يُهمَل بصمت صار مرئياً
/// ============================================================================
///
///  العلة
///  ─────
///  كل تعارض على كل كيان يُحسَم صامتاً بقاعدة «الأحدث يفوز»، ويُكتب الطرف
///  المهمَل في جدول `conflict_log`. والجدول **بلا قارئ واحد**: لا واجهة،
///  ولا استعلام، ولا تصدير — ذُكر في ثلاثة مواضع فقط هي تعريف المخطّط،
///  وسطر الإدراج، ومسحه عند تبديل الحساب.
///
///  فمبلغٌ أو ملاحظةٌ سريرية أو موعدٌ يكتبه جهازان في وقت متقارب: أحدهما
///  **يختفي بلا أي إشارة**. وفي سجلّ طبي هذا أسوأ من عطل ظاهر.
///
///  لماذا لا يُعرَض كل تعارض
///  ────────────────────────
///  معظم التعارضات حميدة: عدّادات مشتقّة، طوابع نشاط، حقول تُعاد كتابتها
///  بالقيمة نفسها. وإشعارٌ عند كل واحدة يُدرَّب المستخدم على تجاهله خلال
///  أسبوع — فيصير الضجيج غطاءً للتعارض الذي يهمّ فعلاً.
///
///  فالمعروض ما يمسّ **مالاً أو قراراً سريرياً** فقط، وهو ما يستطيع
///  المستخدم أن يفعل حياله شيئاً.
library;

import 'dart:convert';

import '../db/local_db.dart';

/// الحقول التي يعني تعارضُها فقدَ قيمة يهتمّ بها إنسان.
///
/// القائمة مغلقة عمداً: توسيعها بحقول مشتقّة أو تقنية يُعيد الضجيج الذي
/// يُبطل الميزة.
const Set<String> kMaterialConflictFields = {
  // مال
  'amount', 'total', 'totalAmount', 'paidAmount', 'labValue',
  'doctorShare', 'clinicShare', 'payment', 'installments',
  // قرار سريري
  'service', 'notes', 'report', 'labStatus', 'prosType',
  // هوية وموعد
  'name', 'phone', 'date', 'time',
};

class ConflictNotice {
  const ConflictNotice({
    required this.id,
    required this.entity,
    required this.entityId,
    required this.fields,
    required this.at,
  });

  final int id;
  final String entity;
  final String entityId;

  /// الحقول التي اختلفت فعلاً وتهمّ — لا كل الحقول.
  final List<String> fields;
  final String at;
}

/// يستخرج التعارضات **الجوهرية** غير المقروءة.
///
/// يقارن الطرفين حقلاً حقلاً بدل الاكتفاء بوجود قيد: القيد يُكتب عند كل
/// حسم، ومعظم الحسم لا يمسّ شيئاً يهمّ.
List<ConflictNotice> materialConflicts(LocalDb db, {int limit = 20}) {
  final out = <ConflictNotice>[];
  try {
    final rows = db.query(
      'SELECT id, entity, entity_id, local_json, remote_json, created_at '
      'FROM conflict_log WHERE IFNULL(seen,0) = 0 '
      'ORDER BY id DESC LIMIT ?',
      [limit * 5], // نفحص أكثر مما نعرض: معظمها سيُرشَّح
    );
    for (final r in rows) {
      final local = _decode(r['local_json']);
      final remote = _decode(r['remote_json']);
      if (local == null || remote == null) continue;

      final diff = <String>[];
      for (final f in kMaterialConflictFields) {
        if (!local.containsKey(f) && !remote.containsKey(f)) continue;
        if (jsonEncode(local[f]) != jsonEncode(remote[f])) diff.add(f);
      }
      if (diff.isEmpty) continue;

      out.add(ConflictNotice(
        id: (r['id'] as num).toInt(),
        entity: '${r['entity'] ?? ''}',
        entityId: '${r['entity_id'] ?? ''}',
        fields: diff,
        at: '${r['created_at'] ?? ''}',
      ));
      if (out.length >= limit) break;
    }
  } catch (_) {/* أفضل جهد — عمود `seen` قد يغيب على قاعدة قديمة */}
  return out;
}

/// عدد التعارضات الجوهرية غير المقروءة — لشارة الواجهة.
int materialConflictCount(LocalDb db) => materialConflicts(db, limit: 99).length;

/// يعلّم قيوداً مقروءة. **لا حذف**: الطرف المهمَل يبقى قابلاً للاسترجاع،
/// وهو الغرض الأصلي من الجدول.
void markConflictsSeen(LocalDb db, List<int> ids) {
  if (ids.isEmpty) return;
  try {
    final marks = List.filled(ids.length, '?').join(',');
    db.execute('UPDATE conflict_log SET seen = 1 WHERE id IN ($marks)', ids);
  } catch (_) {/* أفضل جهد */}
}

Map<String, Object?>? _decode(Object? raw) {
  final s = '${raw ?? ''}';
  if (s.isEmpty || s == 'null') return null;
  try {
    final j = jsonDecode(s);
    return j is Map ? Map<String, Object?>.from(j) : null;
  } catch (_) {
    return null;
  }
}
