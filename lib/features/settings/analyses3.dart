// نظام «التحاليل الثلاثية» — مواصفة المالك (2026-08-08، بديل قائمة التحاليل
// المتعددة): تحليلٌ واحدٌ ثابتُ الاسم، بسعرٍ افتراضيٍّ قابلٍ للتعديل من
// الإعدادات وزرِّ تفعيلٍ واحدٍ يتحكم بظهور خيار التحليل في نموذجَي الإضافة.
//
// القراءة هنا مركزيةٌ كي تتطابق الشاشات كلها (الإعدادات / شاشة الإضافة /
// الورقة السريعة) على تفسيرٍ واحدٍ للإعداد. التخزين في app.config تحت
// المفتاح [kTriAnalysesCfgKey] كخريطة {price, enabled} — يكتبها قسم
// الإعدادات عبر مستودع الإعدادات المتزامن (لا كتابة مباشرة هنا).

/// الاسم الثابت للتحليل — يُكتب في `analysisName` لكل صفٍّ يُنشأ، ويظهر
/// في بطاقة الخزينة والطباعة والتلميحات.
const String kTriAnalysesName = 'التحاليل الثلاثية';

/// مفتاح الإعداد داخل app.config.
const String kTriAnalysesCfgKey = 'analyses3';

Map<String, Object?> _tri(Map<String, Object?> cfg) =>
    cfg[kTriAnalysesCfgKey] is Map
        ? Map<String, Object?>.from(cfg[kTriAnalysesCfgKey] as Map)
        : const {};

/// هل الميزة مفعّلة؟ الافتراضي معطّلة حتى يفعّلها المالك من الإعدادات —
/// فلا يظهر الخيار في نموذجَي الإضافة قبل قرارٍ صريح.
bool triAnalysesEnabled(Map<String, Object?> cfg) =>
    _tri(cfg)['enabled'] == true;

/// السعر الافتراضي الثابت. صفرٌ إن لم يُضبط بعد — ومسار الحفظ يرفض
/// أي تحليلٍ بسعرٍ ≤ 0 أصلاً (حارس record_saver القائم)، فلا صفوف شبح.
num triAnalysesPrice(Map<String, Object?> cfg) {
  final v = _tri(cfg)['price'];
  if (v is num) return v;
  return num.tryParse('$v') ?? 0;
}

// ═══ م149 — قاعدة تكرار التحليل ═══════════════════════════════════════════

/// المدة المسموح بها لإعادة التحليل (بالأشهر) — الافتراضي 6 (مواصفة
/// المالك). صفرٌ أو سالبٌ = القاعدة معطّلة (لا حجب إطلاقاً).
num triRepeatMonths(Map<String, Object?> cfg) {
  final v = _tri(cfg)['repeatMonths'];
  if (v is num) return v;
  return num.tryParse('$v') ?? 6;
}

// ═══ م168 — الاختفاء الشامل عند الإيقاف: تاريخ الإيقاف ودوال الرؤية ═══════

/// م168 — تاريخ إيقاف الميزة YYYY-MM-DD: يختمه مفتاح الإعدادات لحظة
/// الانتقال مفعّل→متوقف (عبر [triCfgWrite])، ويُمحى عند إعادة التفعيل.
/// '' = لا تاريخ مسجل (لم تُفعَّل قط، أو إعدادٌ سابق لم168).
String triDisabledOn(Map<String, Object?> cfg) {
  final v = '${_tri(cfg)['disabledOn'] ?? ''}'.trim();
  return v == 'null' ? '' : v;
}

/// م168 — رؤية بيانات التحاليل في واجهات العرض (عمود اليوم/السجلات/
/// المالية) لتاريخ [ymd] بصيغة YYYY-MM-DD (المقارنة المعجمية = الزمنية):
/// • الميزة مفعّلة ⇒ ظاهرة دائماً.
/// • متوقفة بتاريخٍ مسجل ⇒ تظهر للتواريخ ≤ تاريخ الإيقاف حصراً (البيانات
///   التاريخية تبقى ظاهرة — ويوم الإيقاف نفسه آخر يومٍ تاريخي كي لا
///   يختفي ما سُجل صباح ذلك اليوم)، وتختفي كلياً بعده.
/// • متوقفة بلا تاريخ ⇒ مخفية كلياً (الافتراضي الآمن — القيمة 0/الغياب).
/// عناصر التفاعل (إضافة/حذف/نموذج الزيارة/الخيارات) لا تستعمل هذه الدالة
/// — حارسها [triAnalysesEnabled] وحده فتختفي فور الإيقاف.
bool triVisibleOnDate(Map<String, Object?> cfg, String ymd) {
  if (triAnalysesEnabled(cfg)) return true;
  final off = triDisabledOn(cfg);
  if (off.isEmpty || ymd.isEmpty) return false;
  return ymd.compareTo(off) <= 0;
}

/// م168 — رؤية شهرٍ YYYY-MM كامل = رؤية أول أيامه: شهرٌ فيه أي يومٍ
/// تاريخي يبقى ظاهراً بمجاميعه في الخزينة، والأشهر التالية تختفي.
bool triVisibleInMonth(Map<String, Object?> cfg, String month) =>
    triVisibleOnDate(cfg, '$month-01');

/// م168 — هل يوجد تاريخُ تحاليلَ ظاهرٌ؟ (مدخل «سجل التحاليل» في السجلات):
/// مفعّلة ⇒ نعم؛ متوقفة ⇒ فقط إن وُجد صفُّ تحليلٍ بتاريخٍ ≤ تاريخ الإيقاف
/// — فالبيانات القديمة تبقى وصولة للعرض ولا يظهر مدخلٌ فارغ بلا تاريخ.
bool triHasVisibleHistory(
  Map<String, Object?> cfg,
  Iterable<Map<String, Object?>> records,
) {
  if (triAnalysesEnabled(cfg)) return true;
  final off = triDisabledOn(cfg);
  if (off.isEmpty) return false;
  for (final r in records) {
    if (!_isTri(r['isAnalysis'])) continue;
    final d = '${r['date'] ?? ''}'.trim();
    if (d.isNotEmpty && d != 'null' && d.compareTo(off) <= 0) return true;
  }
  return false;
}

/// م168 — بناء كتلة إعداد التحاليل عند أي كتابةٍ من الإعدادات — مصدرٌ
/// واحدٌ يدير disabledOn: التفعيل يمحوه، والانتقال مفعّل→متوقف يختمه
/// بتاريخ اليوم [today]، وأي كتابةٍ أخرى (سعر/مدة) تحافظ عليه كما هو.
Map<String, Object?> triCfgWrite(
  Map<String, Object?> cfg, {
  required num price,
  required bool enabled,
  required num repeatMonths,
  required String today,
}) {
  final next = <String, Object?>{
    ..._tri(cfg),
    'price': price,
    'enabled': enabled,
    'repeatMonths': repeatMonths,
  };
  if (enabled) {
    next.remove('disabledOn');
  } else if (triAnalysesEnabled(cfg)) {
    next['disabledOn'] = today;
  }
  return next;
}

bool _isTri(Object? v) =>
    v == true || v == 1 || v == '1' || v == 'true';

/// م153 — هاتف معرّف الهوية: `p:<هاتف مطبَّع>:<اسم>` ⇐ الهاتف، وإلا ''.
String _pidPhone(String pid) {
  if (!pid.startsWith('p:')) return '';
  final i = pid.indexOf(':', 2);
  return i < 0 ? '' : pid.substring(2, i);
}

/// تاريخ آخر تحليلٍ ثلاثيٍّ للمريض من صفوف السجلات — أو null إن لم يوجد.
///
/// هوية المريض (م152 — قاعدة المالك المؤكدة: «لكل اسم مرة واحدة»):
/// **الاسم المطبَّع أساس المطابقة** ([normalize] — أداة التطبيع العربي
/// القائمة، فتُدرك «إبراهيم» رغم كتابتها «ابراهيم»)، **أو** تطابقُ
/// معرّفَي المريض حين يتوفر الطرفان (يلتقط تغيير الاسم على نفس الهوية).
///
/// م153 (قرارا المالك):
/// • **نطاق العيادة**: [clinic] غير الفارغة تقصر المطابقة على تحاليل
///   العيادة نفسها — «محمد أحمد» في عيادتين حرٌّ في كلٍّ منهما على حدة.
/// • **استثناء السميَّين**: هاتفان مختلفان **صريحان** على الطرفين
///   (من [phone] المطبَّع أو من معرّفَي الهوية `p:هاتف:اسم`) = شخصان
///   مختلفان فلا يتحاجبان. غياب هاتف أي طرفٍ يُبقي الحجب احتياطاً.
///
/// التاريخ نصيٌّ بصيغة YYYY-MM-DD فالمقارنة المعجمية = الزمنية.
String? lastTriAnalysisDate(
  List<Map<String, Object?>> records, {
  String? patientId,
  required String patientName,
  String clinic = '',
  String phone = '',
  required String Function(String) normalize,
}) {
  final pid = (patientId ?? '').trim();
  final wanted = normalize(patientName.trim());
  final wantClinic = clinic.trim();
  // هاتف الطرف الحالي: الممرَّر صراحةً (مطبَّعاً من المنادي) وإلا من معرّفه.
  final qPhone = phone.trim().isNotEmpty ? phone.trim() : _pidPhone(pid);
  String? last;
  for (final r in records) {
    if (!_isTri(r['isAnalysis'])) continue;
    // التحليل الثلاثي حصراً — صفوف التحاليل الحرة من النظام القديم
    // (أسماء متعددة قبل م145) لا تُحتسب، فالقاعدة قاعدةُ «التحليل
    // الثلاثي» نصاً ولا يصح أن تحجب المريض بصفٍّ قديمٍ مختلف.
    if ('${r['analysisName'] ?? ''}' != kTriAnalysesName) continue;
    // م153 — نطاق العيادة: تحاليل نفس العيادة فقط (clinic ثم clinic_id).
    if (wantClinic.isNotEmpty) {
      final rc = '${r['clinic'] ?? ''}'.trim();
      final rowClinic =
          (rc.isNotEmpty && rc != 'null') ? rc : '${r['clinic_id'] ?? ''}'.trim();
      if (rowClinic != wantClinic) continue;
    }
    final rid = '${r['patient_id'] ?? ''}'.trim();
    final sameName = wanted.isNotEmpty &&
        normalize('${r['patient_name'] ?? r['name'] ?? ''}'.trim()) == wanted;
    final sameId = pid.isNotEmpty && rid.isNotEmpty && rid == pid;
    if (!sameName && !sameId) continue;
    // م153 — استثناء السميَّين: هاتفان صريحان مختلفان = شخصان (إلا حين
    // يتطابق المعرّفان — فهو المريض نفسه حتماً).
    if (!sameId) {
      final rPhone = _pidPhone(rid);
      if (qPhone.isNotEmpty && rPhone.isNotEmpty && qPhone != rPhone) {
        continue;
      }
    }
    final d = '${r['date'] ?? ''}'.trim();
    if (d.isEmpty || d == 'null') continue;
    if (last == null || d.compareTo(last) > 0) last = d;
  }
  return last;
}

/// يضيف [months] شهراً تقويمياً إلى تاريخ YYYY-MM-DD (بمعايرة DateTime —
/// نهاية الشهر تفيض للشهر التالي كسلوك التقويم القياسي).
String addMonths(String isoDate, int months) {
  final p = isoDate.split('-');
  final d = DateTime(int.parse(p[0]), int.parse(p[1]) + months, int.parse(p[2]));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// قرار قاعدة التكرار: تعيد **رسالة الحجب** (بصيغة المواصفة النصية) إن كان
/// المريض ممنوعاً من تحليلٍ جديد اليوم، أو null إن كان مسموحاً.
///
/// السماح: لا تحليلَ سابقاً، أو انقضت المدة (تاريخ اليوم ≥ آخر تحليل +
/// [repeatMonths] شهراً تقويمياً)، أو القاعدة معطّلة (repeatMonths ≤ 0).
String? triRepeatBlockMessage({
  required String? lastDate,
  required String today,
  required num repeatMonths,
}) {
  if (lastDate == null || lastDate.isEmpty) return null;
  final months = repeatMonths.toInt();
  if (months <= 0) return null;
  final allowedFrom = addMonths(lastDate, months);
  if (today.compareTo(allowedFrom) >= 0) return null;
  return 'لا يمكن إجراء تحليل ثلاثي جديد لهذا المريض. '
      'آخر تحليل تم بتاريخ $lastDate. '
      'يجب مرور $months أشهر على الأقل.';
}
