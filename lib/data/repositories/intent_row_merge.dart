/// ============================================================================
///  كتابة صف مطابقة لنيّة المستخدم — v31
/// ============================================================================
///
///  الواجهة تقرأ الصف ثم تعرض نافذة التعديل ثم تحفظ **الصف كاملاً**. إذا
///  وصل تعديل جهاز آخر لحقلٍ ثانٍ بين القراءة والحفظ، فالحفظ الكامل يعيد
///  ذلك الحقل لقيمته القديمة ويختمه بساعة جديدة ⇒ يمسح تعديل الجهاز الآخر.
///
///  الحل: نطبّق **ما تغيّر فعلاً** بين لقطة الواجهة والقيمة المحفوظة فوق
///  الصف المخزّن الآن. والقوائم التي عناصرها كائنات بمعرّفات (أقساط الدين
///  مثلاً) تُدمج عنصراً بعنصر: ما أضافه المستخدم يُضاف، وما حذفه يُحذف،
///  وما لم يلمسه يبقى كما وصل من الجهاز الآخر.
library;

bool _eq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_eq(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_eq(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

bool _identified(Object? v) {
  if (v is! List) return false;
  final seen = <Object?>{};
  for (final el in v) {
    if (el is! Map) return false;
    final id = el['id'];
    if (id == null || '$id'.isEmpty) return false;
    if (!seen.add(id)) return false;
  }
  return true;
}

List<Object?> _mergeIdList(
    List<Object?> stored, List<Object?> base, List<Object?> incoming) {
  Map<String, Map<String, Object?>> index(List<Object?> l) => {
        for (final el in l.whereType<Map>())
          '${el['id']}': Map<String, Object?>.from(el),
      };
  final st = index(stored);
  final bs = index(base);
  final inc = index(incoming);
  final out = Map<String, Map<String, Object?>>.from(st);
  // ما أضافه/عدّله المستخدم (مقارنةً بلقطته) يُطبَّق.
  for (final e in inc.entries) {
    final b = bs[e.key];
    if (b == null || !_eq(b, e.value)) out[e.key] = e.value;
  }
  // ما حذفه المستخدم (كان في لقطته وغاب عن حفظه) يُحذف.
  for (final k in bs.keys) {
    if (!inc.containsKey(k)) out.remove(k);
  }
  // ترتيب حتمي: ترتيب حفظ المستخدم أولاً ثم الباقي بالمعرّف.
  final ordered = <Map<String, Object?>>[];
  for (final el in incoming.whereType<Map>()) {
    final k = '${el['id']}';
    if (out.containsKey(k)) ordered.add(out.remove(k)!);
  }
  final rest = out.keys.toList()..sort();
  for (final k in rest) {
    ordered.add(out[k]!);
  }
  return ordered;
}

/// يبني الصف الذي سيُكتب: الصف المخزّن + ما غيّره المستخدم فعلاً.
Map<String, Object?> mergeIntentRow({
  required Map<String, Object?> stored,
  required Map<String, Object?> base,
  required Map<String, Object?> incoming,
}) {
  final out = Map<String, Object?>.from(stored);
  for (final e in incoming.entries) {
    final k = e.key;
    final inc = e.value;
    final bs = base[k];
    if (_eq(bs, inc)) continue; // لم يلمسه المستخدم ⇒ نُبقي المخزّن
    if (_identified(inc) && _identified(bs) && _identified(stored[k])) {
      out[k] = _mergeIdList(
          stored[k] as List<Object?>, bs as List<Object?>, inc as List<Object?>);
      continue;
    }
    out[k] = inc;
  }
  // حقول أزالها المستخدم من الكائن (نادر) تبقى كما هي في المخزّن.
  return out;
}
