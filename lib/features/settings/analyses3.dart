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
