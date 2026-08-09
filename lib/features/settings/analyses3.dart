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

bool _isTri(Object? v) =>
    v == true || v == 1 || v == '1' || v == 'true';

/// تاريخ آخر تحليلٍ ثلاثيٍّ للمريض من صفوف السجلات — أو null إن لم يوجد.
///
/// هوية المريض (م152 — قاعدة المالك المؤكدة: «لكل اسم مرة واحدة»):
/// **الاسم المطبَّع أساس المطابقة** ([normalize] — أداة التطبيع العربي
/// القائمة، فتُدرك «إبراهيم» رغم كتابتها «ابراهيم»)، **أو** تطابقُ
/// معرّفَي المريض حين يتوفر الطرفان (يلتقط تغيير الاسم على نفس الهوية).
/// كانت المقارنة تقف عند اختلاف المعرّفين ولا تسقط للاسم أبداً — فمرّ
/// التحليل المكرر لنفس الاسم بهاتفٍ مختلف أو بلا هاتف (بلاغ المالك
/// 2026-08-10 من نوافذ الهاتف الثلاث). التاريخ نصيٌّ بصيغة YYYY-MM-DD
/// فالمقارنة المعجمية = الزمنية.
String? lastTriAnalysisDate(
  List<Map<String, Object?>> records, {
  String? patientId,
  required String patientName,
  required String Function(String) normalize,
}) {
  final pid = (patientId ?? '').trim();
  final wanted = normalize(patientName.trim());
  String? last;
  for (final r in records) {
    if (!_isTri(r['isAnalysis'])) continue;
    // التحليل الثلاثي حصراً — صفوف التحاليل الحرة من النظام القديم
    // (أسماء متعددة قبل م145) لا تُحتسب، فالقاعدة قاعدةُ «التحليل
    // الثلاثي» نصاً ولا يصح أن تحجب المريض بصفٍّ قديمٍ مختلف.
    if ('${r['analysisName'] ?? ''}' != kTriAnalysesName) continue;
    final rid = '${r['patient_id'] ?? ''}'.trim();
    final sameName = wanted.isNotEmpty &&
        normalize('${r['patient_name'] ?? r['name'] ?? ''}'.trim()) == wanted;
    final sameId = pid.isNotEmpty && rid.isNotEmpty && rid == pid;
    if (!sameName && !sameId) continue;
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
