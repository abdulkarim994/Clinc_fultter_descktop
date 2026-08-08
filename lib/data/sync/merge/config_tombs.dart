/// ============================================================================
///  شواهد حذف عناصر أشجار الإعدادات — إضافة v27 (فوق الأصل، بتوافق Vue)
/// ============================================================================
///
///  المشكلة: داخل `app.config` تعيش قوائم عناصرها كائنات بمعرّفات (مراحل
///  خطة العلاج). استنتاج الحذف من «غياب العنصر» يحتاج لقطة أساس دقيقة،
///  وهي غير مضمونة لأن الخادم يحسم الصف كاملاً بالساعة الأحدث (دفع جهاز
///  يكتب فوق دفع الآخر بلا دمج). فإذا اعتمدنا الغياب وحده: إما نفقد إضافات
///  الجهاز الآخر (حذف كاذب) أو يعود المحذوف للحياة.
///
///  الحل: **الحذف حقيقة صريحة** تُكتب في مفتاح جانبي داخل الإعدادات:
///      config['_tombs']['treatmentPlans/(مفتاح المريض)'] = { (id): 1 }
///  يُدمج اتحاداً محضاً (لا يفقد شاهداً أبداً)، ويُقلَّم أثر العنصر من
///  القوائم بعد كل دمج — فتبقى القيمة المخزّنة نظيفة حتى في Vue (الذي
///  يتجاهل المفاتيح التي لا يعرفها ويحافظ عليها عند الحفظ).
library;

/// مفتاح خريطة الشواهد داخل `app.config`.
const String kConfigTombsKey = '_tombs';

/// مسار قائمة داخل الإعدادات: `<configKey>/<mapKey>`.
String tombPath(String configKey, String mapKey) => '$configKey/$mapKey';

/// مسار مراحل خطة علاج مريض (مفتاح المريض قد يكون «اسم|عيادة»).
String planTombPath(String patientKey) =>
    tombPath('treatmentPlans', patientKey);

/// v28 — مسار شواهد حذف **مدخل كامل** داخل خريطة إعدادات (حذف مريض أو
/// إعادة تسميته تزيل مفتاحه من treatmentPlans/patientMedical). بدونه لا
/// يمكن تمييز «حذفتُه أنا» عن «أضافه الجهاز الآخر» عند دمج الكتابة.
String mapKeyTombPath(String configKey) => 'map:$configKey';

/// يسجّل حذف مدخل كامل بمفتاحه.
Map<String, Object?> markMapKeyDeleted(
        Map<String, Object?> config, String configKey, String mapKey) =>
    markItemDeleted(config, mapKeyTombPath(configKey), mapKey);

/// إلغاء شاهد حذف مدخل (إعادة إنشائه بعد حذفه على هذا الجهاز).
Map<String, Object?> clearMapKeyTomb(
    Map<String, Object?> config, String configKey, String mapKey) {
  final tombs = _mapOf(config[kConfigTombsKey]);
  final path = mapKeyTombPath(configKey);
  final forPath = _mapOf(tombs[path]);
  if (!forPath.containsKey(mapKey)) return config;
  forPath.remove(mapKey);
  final next = Map<String, Object?>.from(tombs);
  if (forPath.isEmpty) {
    next.remove(path);
  } else {
    next[path] = forPath;
  }
  final cfg = Map<String, Object?>.from(config);
  cfg[kConfigTombsKey] = next;
  return cfg;
}

Map<String, Object?> _mapOf(Object? v) =>
    v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};

/// يسجّل حذف عنصر بمعرّفه داخل نسخة جديدة من الإعدادات (نقي — لا كتابة).
Map<String, Object?> markItemDeleted(
    Map<String, Object?> config, String path, Object? id) {
  if (id == null || '$id'.isEmpty) return config;
  final cfg = Map<String, Object?>.from(config);
  final tombs = _mapOf(cfg[kConfigTombsKey]);
  final forPath = _mapOf(tombs[path])..['$id'] = 1;
  tombs[path] = forPath;
  cfg[kConfigTombsKey] = tombs;
  return cfg;
}

/// هل العنصر محذوف بشاهد صريح؟
bool isItemTombstoned(
    Map<String, Object?> config, String path, Object? id) {
  final tombs = _mapOf(config[kConfigTombsKey]);
  final forPath = _mapOf(tombs[path]);
  return forPath.containsKey('$id');
}

/// يقلّم من قوائم الإعدادات كل عنصر يحمل معرّفاً مشهوداً بالحذف.
/// نقي: يعيد نسخة جديدة (أو الأصل نفسه إن لم يتغير شيء).
Map<String, Object?> pruneTombstoned(Map<String, Object?> config,
    {String idKey = 'id'}) {
  final tombs = _mapOf(config[kConfigTombsKey]);
  if (tombs.isEmpty) return config;
  var changed = false;
  final out = Map<String, Object?>.from(config);
  for (final e in tombs.entries) {
    final ids = _mapOf(e.value);
    if (ids.isEmpty) continue;
    // v28 — شواهد حذف المداخل الكاملة: `map:<configKey>` ⇒ تُزال مفاتيحها.
    if (e.key.startsWith('map:')) {
      final configKey = e.key.substring(4);
      final branch = out[configKey];
      if (branch is! Map) continue;
      final next = Map<String, Object?>.from(branch);
      var dropped = false;
      for (final k in ids.keys) {
        if (next.remove(k) != null) dropped = true;
      }
      if (dropped) {
        out[configKey] = next;
        changed = true;
      }
      continue;
    }
    final parts = e.key.split('/');
    if (parts.length != 2) continue;
    final configKey = parts[0];
    final mapKey = parts[1];
    final branch = out[configKey];
    if (branch is! Map) continue;
    final list = branch[mapKey];
    if (list is! List) continue;
    final kept = [
      for (final el in list)
        if (!(el is Map && ids.containsKey('${el[idKey]}'))) el,
    ];
    if (kept.length != list.length) {
      final nextBranch = Map<String, Object?>.from(branch);
      nextBranch[mapKey] = kept;
      out[configKey] = nextBranch;
      changed = true;
    }
  }
  return changed ? out : config;
}
