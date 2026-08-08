/// عزل كامل لبيانات المريض حسب العيادة — **قرار مالك v12** (يتجاوز الأصل):
/// نفس الاسم في عيادتين = مريضان مستقلان، بلا مشاركة أي بيانات طبية.
///
/// البطاقة الطبية (config.patientMedical) والخطة العلاجية
/// (config.treatmentPlans) كانتا بمفتاح الاسم فقط (كما في Vue) — فتتشاركان
/// بين العيادتين. المفاتيح الجديدة مركّبة «اسم|عيادة» مع **قراءة متدرجة
/// آمنة**: مفتاح العيادة أولاً وإلا المدخل القديم بالاسم (بيانات ما قبل
/// الفصل تبقى ظاهرة)، وأي **كتابة** تذهب لمفتاح العيادة وحده
/// (نسخ-عند-الكتابة — لا فقدان ولا خلط جديد).
///
/// تنبيه موثق: تطبيق Vue يقرأ بمفتاح الاسم فقط — المدخلات الجديدة بمفتاح
/// «اسم|عيادة» لا تظهر فيه (قرار مالك مسجل في التقرير).
library;

typedef JMap = Map<String, Object?>;

/// مفتاح النطاق المركب — «اسم|عيادة» (وبلا عيادة يبقى الاسم للتوافق).
String clinicScopedKey(String name, String clinic) {
  final n = name.trim(), c = clinic.trim();
  return c.isEmpty ? n : '$n|$c';
}

/// قراءة متدرجة: مفتاح العيادة أولاً ← وإلا المدخل القديم بالاسم.
Object? clinicScopedRead(Object? map, String name, String clinic) {
  if (map is! Map) return null;
  final k = clinicScopedKey(name, clinic);
  if (map.containsKey(k)) return map[k];
  return map[name.trim()];
}

/// كتابة لمفتاح العيادة وحده (نسخ-عند-الكتابة).
Map<String, Object?> clinicScopedWrite(
  Object? map,
  String name,
  String clinic,
  Object? value,
) {
  final out = map is Map
      ? Map<String, Object?>.from(map)
      : <String, Object?>{};
  out[clinicScopedKey(name, clinic)] = value;
  return out;
}

/// إزالة مدخل العيادة، و«الإرث» بالاسم فقط إذا كانت آخر نسخة
/// ([removeLegacy] يقرره المستدعي بعدّ بقايا الاسم في العيادات الأخرى).
/// م96 — تشمل الإزالة مفاتيح الهوية الهاتفية «اسم|عيادة|هاتف…» أيضاً.
Map<String, Object?> clinicScopedRemove(
  Object? map,
  String name,
  String clinic, {
  required bool removeLegacy,
}) {
  final out = map is Map
      ? Map<String, Object?>.from(map)
      : <String, Object?>{};
  final base = clinicScopedKey(name, clinic);
  out.removeWhere((k, _) => k == base || k.startsWith('$base|'));
  if (removeLegacy) out.remove(name.trim());
  return out;
}

/// هجرة إعادة التسمية داخل عيادة: «قديم|عيادة» ← «جديد|عيادة»؛ والمدخل
/// القديم بالاسم فقط يُنسخ لمفتاح العيادة الجديد ثم يُحذف فقط إن لم يعد
/// ثمة مريض آخر بالاسم القديم ([othersStillUseLegacy]).
/// م96 — تُعاد تسمية مفاتيح الهوية الهاتفية «قديم|عيادة|هاتف…» أيضاً
/// بإبقاء لاحقة الهاتف كما هي.
Map<String, Object?> clinicScopedRename(
  Object? map,
  String oldName,
  String newName,
  String clinic, {
  required bool othersStillUseLegacy,
}) {
  final out = map is Map
      ? Map<String, Object?>.from(map)
      : <String, Object?>{};
  final oldScoped = clinicScopedKey(oldName, clinic);
  final newScoped = clinicScopedKey(newName, clinic);
  var movedAny = false;
  for (final k in out.keys.toList()) {
    if (k == oldScoped) {
      out[newScoped] = out.remove(k);
      movedAny = true;
    } else if (k.startsWith('$oldScoped|')) {
      out['$newScoped${k.substring(oldScoped.length)}'] = out.remove(k);
      movedAny = true;
    }
  }
  if (!movedAny && out.containsKey(oldName.trim())) {
    out[newScoped] = out[oldName.trim()];
    if (!othersStillUseLegacy) out.remove(oldName.trim());
  }
  return out;
}

// ═════════════════════════ م96 — عزل المعلومات الطبية ═════════════════════════
// قرار المالك: ممنوع تشارك المعلومات الطبية بين مشابهي الاسم — لا بين
// العيادات ولا داخل العيادة الواحدة. المفتاح يرتقي إلى «اسم|عيادة|أرقام
// الهاتف» متى عُرف هاتف، والقراءة العارية بالاسم فقط أُلغيت نهائياً من
// مسارات المعلومات الطبية (تبقى للهجرة فقط).

/// أرقام الهاتف فقط (تطبيع للمقارنة والمفاتيح).
String phoneDigits(Object? phone) =>
    '${phone ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');

/// مفتاح المعلومات الطبية: «اسم|عيادة|أرقام» متى وُجد هاتف (سياقاً أو
/// من صف المريض)، وإلا «اسم|عيادة».
String medicalScopedKey(String name, String clinic, Object? phone) {
  final d = phoneDigits(phone);
  final base = clinicScopedKey(name, clinic);
  return d.isEmpty ? base : '$base|$d';
}

/// قراءة المعلومات الطبية — **بلا** قراءة عارية بالاسم (ممنوع الربط):
///  1) مفتاح الهاتف (هاتف السياق وإلا هاتف صف المريض [rowPhone]).
///  2) إن تعارض هاتفُ السياق مع هاتف الصف ⇒ لا شيء (توأمٌ آخر — عزل).
///  3) وإلا مفتاح «اسم|عيادة» (بيانات ما قبل ترقية الهاتف).
Object? medicalScopedRead(
  Object? map,
  String name,
  String clinic,
  Object? phone, {
  Object? rowPhone,
}) {
  if (map is! Map) return null;
  final d = phoneDigits(phone);
  final rd = phoneDigits(rowPhone);
  final keyDigits = d.isNotEmpty ? d : rd;
  if (keyDigits.isNotEmpty) {
    final k2 = '${clinicScopedKey(name, clinic)}|$keyDigits';
    if (map.containsKey(k2)) return map[k2];
    if (d.isNotEmpty && rd.isNotEmpty && rd != d) return null;
  }
  return map[clinicScopedKey(name, clinic)];
}

/// كتابة المعلومات الطبية لمفتاح الهوية وحده (هاتف السياق وإلا هاتف
/// الصف وإلا مفتاح العيادة).
Map<String, Object?> medicalScopedWrite(
  Object? map,
  String name,
  String clinic,
  Object? phone,
  Object? value, {
  Object? rowPhone,
}) {
  final out = map is Map
      ? Map<String, Object?>.from(map)
      : <String, Object?>{};
  final d = phoneDigits(phone);
  final key = medicalScopedKey(
      name, clinic, d.isNotEmpty ? d : phoneDigits(rowPhone));
  out[key] = value;
  return out;
}

/// هجرة مفاتيح المعلومات الطبية — تُشغَّل عند الإقلاع (عديمة الأثر حين
/// لا شيء يُهاجَر، فتعيد null):
///  1) مدخل عارٍ بالاسم ← مفتاح عيادة **أحدث نشاط** لذلك الاسم (نقلاً لا
///     نسخاً — منعاً لإلصاق معلومات مريض بمشابه اسمه)، والاسم بلا أي
///     نشاط يبقى مدخله خاملاً (لا يقرؤه أحد بعد اليوم).
///  2) «اسم|عيادة» ← «اسم|عيادة|هاتف الصف» متى كان للمريض هاتف مخزن.
///  الموجود مسبقاً في الهدف يبقى (كُتب بعد العزل فهو الأحدث) ويُسقط المصدر.
Map<String, Object?>? migrateMedicalKeys(
  Object? medical, {
  required String? Function(String name) latestClinicOf,
  required String Function(String name) rowPhoneOf,
  bool upgradePhones = true,
}) {
  if (medical is! Map) return null;
  final out = Map<String, Object?>.from(medical);
  var changed = false;
  // 1) العاري بالاسم ← عيادة أحدث نشاط (+ هاتف الصف إن وُجد).
  for (final k in out.keys.toList()) {
    if (k.contains('|')) continue;
    final clinic = (latestClinicOf(k) ?? '').trim();
    if (clinic.isEmpty) continue; // بلا نشاط — يبقى خاملاً.
    final target = medicalScopedKey(
        k, clinic, upgradePhones ? rowPhoneOf(k) : '');
    if (!out.containsKey(target)) out[target] = out[k];
    out.remove(k);
    changed = true;
  }
  // 2) «اسم|عيادة» ← مفتاح الهاتف متى عُرف هاتف الصف. (م97: كتلة خطة
  //    العلاج القديمة تُهاجَر بالعيادة فقط [upgradePhones=false] — ترقية
  //    الهاتف لصفوفها تجري في مخزن الصفوف نفسه عند القراءة.)
  if (upgradePhones) {
    for (final k in out.keys.toList()) {
      final parts = k.split('|');
      if (parts.length != 2) continue;
      final d = phoneDigits(rowPhoneOf(parts[0]));
      if (d.isEmpty) continue;
      final target = '$k|$d';
      if (!out.containsKey(target)) out[target] = out[k];
      out.remove(k);
      changed = true;
    }
  }
  return changed ? out : null;
}
