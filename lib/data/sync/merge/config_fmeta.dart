/// ============================================================================
///  ساعة لكل حقل داخل `app.config` — إضافة v27 (فوق الأصل، بتوافق Vue)
/// ============================================================================
///
///  لماذا؟ الخادم يحسم صف الإعدادات **كاملاً** بالساعة الأحدث (دفع جهاز
///  يكتب فوق دفع الآخر بلا دمج)، والدمج الثلاثي على العميل يحتاج «أساساً
///  مشتركاً» لا يمكن ضمانه: جهاز B يدفع نسخته المبنية على حالة قديمة،
///  فيبدو حقلٌ لم يلمسه أصلاً وكأنه «قيمة B الجديدة» فيمسح تعديل A.
///
///  الحل: لكل **ورقة** داخل الأشجار المتداخلة نحفظ ساعة تغييرها الأخيرة:
///      config['_fmeta']['treatmentPlans/سالم|الصفوة/s2/desc'] = `hlc`
///  فيصير الحسم بين جهازين لكل حقل على حدة (الأحدث فعلياً لهذا الحقل)،
///  لا بساعة الصف كله. الحقول التي لم يلمسها أحد لا تتأثر أبداً.
///
///  توافق Vue: مفتاح إضافي يتجاهله التطبيق المكتبي ويحافظ عليه عند الحفظ؛
///  وأوراق بلا ساعة تعود لسلوك الأصل (حسم بساعة الصف) تلقائياً.
library;

/// مفتاح خريطة ساعات الحقول داخل `app.config`.
const String kConfigFMetaKey = '_fmeta';

/// الأشجار التي تُختم أوراقها (حيث يقع ألم التعديل من جهازين).
const List<String> kStampedConfigKeys = [
  'treatmentPlans',
  'patientMedical',
  'clinicRates',
  'servicePrices',
];

/// ترميز مقطع مسار بأسلوب JSON-Pointer حتى لا يكسر اسمٌ فيه `/` المسار.
String encodeSeg(String s) =>
    s.replaceAll('~', '~0').replaceAll('/', '~1');

String joinPath(List<String> segs) => segs.map(encodeSeg).join('/');

Map<String, Object?> _mapOf(Object? v) =>
    v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};

/// خريطة الساعات المخزّنة داخل الإعدادات.
Map<String, String> readFMeta(Map<String, Object?>? config) {
  final raw = _mapOf(config?[kConfigFMetaKey]);
  final out = <String, String>{};
  for (final e in raw.entries) {
    if (e.value is String) out[e.key] = e.value as String;
  }
  return out;
}

bool _deepEq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_deepEq(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

/// هل القائمة عناصرها كائنات بمعرّفات فريدة (تُدمج عنصراً بعنصر)؟
bool listIsIdentified(Object? v, {String idKey = 'id'}) {
  if (v is! List) return false;
  final seen = <Object?>{};
  for (final el in v) {
    if (el is! Map) return false;
    final id = el[idKey];
    if (id == null || '$id'.isEmpty) return false;
    if (!seen.add(id)) return false;
  }
  return true;
}

void _walk(
  Object? prev,
  Object? next,
  List<String> segs,
  String hlc,
  Map<String, String> meta,
) {
  // ورقة (نص/رقم/منطقي/قائمة بلا معرّفات): اختم عند الاختلاف فقط.
  final bothMaps = next is Map;
  final idList = listIsIdentified(next);
  if (!bothMaps && !idList) {
    if (!_deepEq(prev, next)) meta[joinPath(segs)] = hlc;
    return;
  }
  if (bothMaps) {
    final p = prev is Map ? prev : const {};
    for (final k in next.keys) {
      _walk(p[k], next[k], [...segs, '$k'], hlc, meta);
    }
    return;
  }
  // قائمة بمعرّفات: كل عنصر شجرة فرعية بمساره = المعرّف.
  final pIndex = <Object?, Map>{};
  if (prev is List) {
    for (final el in prev) {
      if (el is Map && el['id'] != null) pIndex[el['id']] = el;
    }
  }
  for (final el in (next as List)) {
    if (el is! Map) continue;
    _walk(pIndex[el['id']], el, [...segs, '${el['id']}'], hlc, meta);
  }
}

/// يختم أوراق الأشجار المتغيّرة بساعة الكتابة الحالية. نقي.
Map<String, Object?> stampChangedLeaves(
  Map<String, Object?>? prev,
  Map<String, Object?> next,
  String hlc,
) {
  final meta = readFMeta(next).isEmpty ? readFMeta(prev) : readFMeta(next);
  final out = Map<String, String>.from(meta);
  for (final key in kStampedConfigKeys) {
    if (!next.containsKey(key)) continue;
    _walk(prev?[key], next[key], [key], hlc, out);
  }
  if (out.isEmpty) return next;
  final cfg = Map<String, Object?>.from(next);
  cfg[kConfigFMetaKey] = out;
  return cfg;
}

/// دمج خريطتي الساعات: لكل مسار **الأحدث** (لا تُفقد ختمة أبداً).
Map<String, String> mergeFMeta(
  Map<String, String> a,
  Map<String, String> b,
  bool Function(String?, String?) isNewer,
) {
  final out = Map<String, String>.from(a);
  for (final e in b.entries) {
    final cur = out[e.key];
    if (cur == null || isNewer(e.value, cur)) out[e.key] = e.value;
  }
  return out;
}
