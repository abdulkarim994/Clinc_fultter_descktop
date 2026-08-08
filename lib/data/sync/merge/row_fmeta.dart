/// ============================================================================
///  م81 — ساعات الحقول لكيانات الصفوف: الدمج يصير تبادلياً
/// ============================================================================
///
///  العلة: تعديلٌ متزامن يختفي بصمت
///  ────────────────────────────────
///  `planFieldMerge` كان يستدعي `mergeRecordValues` **بلا** خرائط ساعات،
///  فتعود `leafDecision()` صفراً دائماً لكيانات الصفوف، ويسقط كل حقل
///  متباعد إلى `_lwwPick` الذي يقارن ساعة **الصف كلّه** لا ساعة الحقل.
///  ثم يُكتب الصف الممزوج بساعة **جديدة** أحدث من الجميع، فتُمحى المعلومة
///  السببية عن مصدر كل حقل.
///
///  والنتيجة أن الدمج **غير تبادلي**: نفس العمليات بترتيب وصولٍ مختلف
///  تُنتج حالتين مختلفتين. بأساس `{x:0, y:0}` وعمليات A:`x=1` وB:`y=1`
///  وC:`x=2` (وساعة C أحدث من A):
///    • A تصل أولاً ⇒ يمزج B فيأخذ ساعةً جديدة أحدث من C ⇒ يخسر `x=2`
///      ⇒ النتيجة `{x:1, y:1}` — **قيمة أحدث اختفت بلا أثر**.
///    • C تصل أولاً ⇒ النتيجة `{x:2, y:1}`.
///
///  وفي سجلّ طبي قد يكون `x` مبلغاً أو ملاحظة علاجية.
///
///  الحل: ختمُ كل حقل بساعته
///  ────────────────────────
///  خريطة `_fmeta` على الصف: مسار الحقل ← ساعة آخر تعديل له. تُختَم عند
///  الكتابة المحلية، وتُمرَّر إلى الدمج فيُحسم كل حقل **بساعة الجهاز الذي
///  لمسه فعلاً** لا بساعة الصف. وهذه الآلية موجودة ومختبَرة منذ v27 —
///  لكنها كانت موصولة لإعدادات الحساب وحدها.
///
///  التوافق الرجعي — شرطٌ لا خيار
///  ──────────────────────────────
///  صفٌّ بلا `_fmeta` (كل الصفوف القائمة اليوم) يُنتج خريطة فارغة، فتعود
///  `leafDecision()` صفراً ويسلك المنطق **مساره القديم حرفياً**. فلا يتغيّر
///  سلوك أي صفّ حتى يُكتب مرةً بالنسخة الجديدة. لا ترحيل، ولا قفزة سلوك.
library;

import 'config_fmeta.dart' show kConfigFMetaKey, mergeFMeta, readFMeta;

/// الحقول التي تُختَم بساعاتها.
///
/// **قائمة مغلقة عمداً.** ختمُ كل حقل يُضخّم حمولة السلك بلا مقابل: الحقول
/// المشتقّة (`remaining`, `_activityAt`) تُعاد حسابها بعد الدمج على كل حال،
/// وأعمدة المزامنة ليست بيانات. والمذكور هنا هو ما **يكتبه إنسان** ويؤلم
/// فقدُه: مال، وقرار سريري، وهوية، وموعد.
const Set<String> kStampedRowFields = {
  // مال
  'amount', 'total', 'totalAmount', 'paidAmount', 'labValue',
  'doctorShare', 'clinicShare', 'payment', 'prosUnits', 'prosUnitPrice',
  // قرار سريري
  'service', 'notes', 'report', 'labStatus', 'labName', 'prosType',
  // هوية وموعد
  'name', 'patient_name', 'phone', 'phone2', 'date', 'time', 'status',
  'clinic', 'type',
};

/// يقرأ خريطة ساعات الصف — فارغة للصفوف القديمة.
Map<String, String> readRowFMeta(Map<String, Object?>? row) => readFMeta(row);

/// يختم الحقول التي **تغيّرت فعلاً** بساعة الكتابة.
///
/// المقارنة بالقيمة لا بالحضور: كتابةٌ تُعيد القيمة نفسها ليست تعديلاً،
/// وختمُها يجعل جهازاً يفوز بحقلٍ لم يمسّه أحد فيه.
///
/// يُرجع الصف كما هو (بلا نسخ) إن لم يتغيّر شيء — فلا تُضخَّم الحمولة بلا سبب.
Map<String, Object?> stampRowFields(
  Map<String, Object?>? prev,
  Map<String, Object?> next,
  String hlc,
) {
  final out = Map<String, String>.from(readRowFMeta(next).isEmpty
      ? readRowFMeta(prev)
      : readRowFMeta(next));
  var changed = false;

  for (final key in kStampedRowFields) {
    if (!next.containsKey(key)) continue;
    final before = prev?[key];
    final after = next[key];
    if (_sameScalar(before, after)) continue;
    out[key] = hlc;
    changed = true;
  }

  if (!changed) return next;
  return {...next, kConfigFMetaKey: out};
}

/// يدمج خريطتَي الساعات — الأحدث لكل مسار، فلا تُفقد ختمة.
Map<String, String> mergeRowFMeta(
  Map<String, String> local,
  Map<String, String> remote,
  bool Function(String?, String?) isNewer,
) =>
    mergeFMeta(local, remote, isNewer);

/// مقارنة قيمتين قياسيتين. البنى المركّبة تُعدّ «مختلفة» دائماً — تفصيلها
/// شأن محرّك الدمج، والختم هنا على مستوى الحقل لا الورقة الداخلية.
bool _sameScalar(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a is num && b is num) return a == b;
  if (a is Map || a is List || b is Map || b is List) return false;
  return '$a' == '$b';
}
