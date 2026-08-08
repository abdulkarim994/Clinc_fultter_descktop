/// ============================================================================
///  ترتيب الدور الحتمي — نقل حرفي لـ stores/queue.order.js (التزام Commit 5)
/// ============================================================================
///
///  دوال نقية قابلة للاختبار بلا Flutter/Riverpod. قيود التصميم كما في الأصل:
///   • لا تغيير في المخطط: seq / archive_seq / entered_at كما هي.
///   • الترتيب **كلي** (كاسر تعادل ثابت بالمعرّف id) فتكون إعادة الترقيم
///     idempotent و**تتقارب** لنفس النتيجة على كل جهاز أعطي نفس الصفوف —
///     وهذا ما يوقف تكرار الأرقام وتضارب الترتيب بين جهازين يضيفان معاً.
///   • قائمة الانتظار مرتّبة بيد المستخدم عبر seq؛ الأرشيف مرتّب بوقت
///     الوصول الثابت entered_at (وarchive_seq رقم عرض مشتق فقط).
library;

import '../../core/utils/js_compat.dart';

typedef QOrderRow = Map<String, Object?>;

int _cmpId(Object? a, Object? b) {
  final ia = a == null ? '' : '$a';
  final ib = b == null ? '' : '$b';
  return ia.compareTo(ib);
}

/// ترتيب كلي لقائمة الانتظار: (seq تصاعدياً، ثم id تصاعدياً).
int compareWaiting(QOrderRow a, QOrderRow b) {
  final d = jsNumOr0(a['seq']) - jsNumOr0(b['seq']);
  if (d != 0) return d < 0 ? -1 : 1;
  return _cmpId(a['id'], b['id']);
}

/// ترتيب كلي للأرشيف: (entered_at تصاعدياً، ثم id تصاعدياً).
int compareArchive(QOrderRow a, QOrderRow b) {
  final ea = '${a['entered_at'] ?? ''}';
  final eb = '${b['entered_at'] ?? ''}';
  final d = ea.compareTo(eb);
  if (d != 0) return d;
  return _cmpId(a['id'], b['id']);
}

/// نسخة مرتبة (بلا مساس بالأصل) من صفوف الانتظار.
List<QOrderRow> sortWaiting(Iterable<QOrderRow> rows) =>
    rows.toList()..sort(compareWaiting);

/// نسخة مرتبة (بلا مساس بالأصل) من صفوف الأرشيف.
List<QOrderRow> sortArchive(Iterable<QOrderRow> rows) =>
    rows.toList()..sort(compareArchive);

/// خطة ترقيم حتمية متصلة 1..N لقائمة الانتظار — [(id, seq)] بالترتيب
/// القانوني. نقية: لا تعدّل المدخلات.
List<({String id, int seq})> planWaitingSeq(Iterable<QOrderRow> rows) => [
      for (final (i, r) in sortWaiting(rows).indexed)
        (id: '${r['id']}', seq: i + 1),
    ];

/// خطة ترقيم حتمية متصلة 1..M للأرشيف بترتيب الوصول.
List<({String id, int archiveSeq})> planArchiveSeq(
        Iterable<QOrderRow> rows) =>
    [
      for (final (i, r) in sortArchive(rows).indexed)
        (id: '${r['id']}', archiveSeq: i + 1),
    ];
