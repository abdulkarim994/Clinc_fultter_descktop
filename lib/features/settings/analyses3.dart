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

/// م187 — هاتف الصفّ المخزَّن: من عمود `phone` أولاً ثم من معرّف هويته.
///
/// كان يُقرأ من المعرّف **وحده**، فصفٌّ معرّفه `n:اسم` (مريض بلا هاتف في
/// جدول الهوية) يبدو «بلا هاتف» ولو كان عموده يحمل رقماً — فيُحجب سميُّه
/// ظلماً. مصدران أفضل من واحد.
String _rowPhone(Map<String, Object?> r, String Function(String) normPhoneFn) {
  final col = normPhoneFn('${r['phone'] ?? ''}');
  if (col.isNotEmpty) return col;
  return _pidPhone('${r['patient_id'] ?? ''}'.trim());
}

/// نتيجة فحص قاعدة التكرار: تاريخ آخر تحليل + **درجة تأكّد الهوية**.
///
/// م187 (قرار المالك) — القاعدة الحاكمة: **حجبٌ قاطع حين تكون الهوية
/// مؤكَّدة، وتحذيرٌ قابل للتجاوز حين تكون تخميناً**:
///  • [certain] = true ⇒ تطابقُ هاتفٍ صريح أو تطابقُ معرّفَي هوية ⇒ هو
///    الشخص نفسه يقيناً ⇒ حجب.
///  • [certain] = false ⇒ التطابق بالاسم وحده (أحد الطرفين بلا هاتف) ⇒
///    تحذيرٌ يمضي بموافقة الطبيب («متابعة على مسؤوليتي») بدل رفضٍ يحبسه.
class TriRepeatHit {
  const TriRepeatHit(this.date, {required this.certain});

  final String date;

  /// هل الهوية مؤكَّدة (هاتف/معرّف) أم تخمينٌ بالاسم؟
  final bool certain;
}

/// آخر تحليلٍ ثلاثيٍّ لهذا المريض — أو null إن لم يوجد.
///
/// **هوية المريض (م187 — تحديثٌ لقرارَي م152/م153):**
///  • المميِّز هو **الهاتف** لا الاسم: سميّان بهاتفين مختلفين لا يتحاجبان
///    أبداً (بلاغ المالك: «عند تشابه الأسماء يرفض ويعتبرهم نفس الشخص»).
///  • **النطاق المركز كله** لا العيادة (قرار المالك بعد سؤاله «نفس المريض
///    عند دكتور تاني»): التحليل قيدٌ طبّيٌّ على **الشخص**، فأخذه في عيادةٍ
///    أخرى داخل المدة كان ثغرةً. [clinic] لم تبقَ للترشيح — تُستعمل
///    للرسالة فقط عند اللزوم (وأُبقيت في التوقيع توافقاً مع المنادين).
///  • مريضٌ **بلا هاتف** على أي طرف: يُحتسب تطابقاً **غير مؤكَّد** (بالاسم
///    المطبَّع) فيصير تحذيراً لا حجباً — انظر [TriRepeatHit].
///
/// التاريخ نصيٌّ بصيغة YYYY-MM-DD فالمقارنة المعجمية = الزمنية.
TriRepeatHit? lastTriAnalysisHit(
  List<Map<String, Object?>> records, {
  String? patientId,
  required String patientName,
  String phone = '',
  required String Function(String) normalize,
  required String Function(String) normPhone,
  /// م189 — حلّالُ هاتف الصفّ المخزَّن (اختياري): يُمرَّر من الواجهة
  /// كـ`IdentityIndex.phoneOf` فيرث الصفُّ هاتفَ **زيارته الأصل** عبر
  /// `analysisOf`. بدونه تبقى صفوفُ التحاليل المكتوبة قبل م189 (بلا عمود
  /// هاتف) «مجهولةَ الهوية» فيصير كلُّ تطابقٍ بالاسم تحذيراً — وهو بلاغ
  /// المالك: «مع أن المريض له رقم هاتف». القيمة المعادة قانونية.
  String Function(Map<String, Object?> row)? phoneOfRow,
}) {
  final pid = (patientId ?? '').trim();
  final wanted = normalize(patientName.trim());
  // هاتف الطرف الحالي: الممرَّر صراحةً وإلا من معرّفه.
  final qPhone = normPhone(phone).isNotEmpty
      ? normPhone(phone)
      : _pidPhone(pid);
  TriRepeatHit? best;
  for (final r in records) {
    if (!_isTri(r['isAnalysis'])) continue;
    // التحليل الثلاثي حصراً — صفوف التحاليل الحرة من النظام القديم
    // (أسماء متعددة قبل م145) لا تُحتسب، فالقاعدة قاعدةُ «التحليل
    // الثلاثي» نصاً ولا يصح أن تحجب المريض بصفٍّ قديمٍ مختلف.
    if ('${r['analysisName'] ?? ''}' != kTriAnalysesName) continue;
    final rid = '${r['patient_id'] ?? ''}'.trim();
    // م189 — الحلّال الموروث أولاً (إن مُرِّر) ثم عمودُه فمعرّفه.
    final rPhone = phoneOfRow != null && normPhone(phoneOfRow(r)).isNotEmpty
        ? normPhone(phoneOfRow(r))
        : _rowPhone(r, normPhone);
    final sameName = wanted.isNotEmpty &&
        normalize('${r['patient_name'] ?? r['name'] ?? ''}'.trim()) == wanted;
    final sameId = pid.isNotEmpty && rid.isNotEmpty && rid == pid;
    final samePhone =
        qPhone.isNotEmpty && rPhone.isNotEmpty && qPhone == rPhone;
    // م187 — **معرّفٌ مشتقٌّ من الاسم ليس إثبات هوية**: `n:اسم` (وTRIM(name)
    // حين علم هوية الهاتف مطفأ) يتطابق بين سميَّين حتماً، فتساويه يساوي
    // تساوي الاسم لا أكثر. الهوية المؤكَّدة = هاتفٌ مشترك أو معرّفٌ يحمل
    // هاتفاً (`p:هاتف:اسم`). لولا هذا التمييز لعاد الحجبُ الظالم من بابٍ
    // آخر: سميّان بلا هاتف لهما نفس `n:اسم`.
    final strongId = sameId && pid.startsWith('p:');
    // م187 — هاتفان صريحان مختلفان = شخصان مختلفان قطعاً: لا يتحاجبان
    // ولو تطابق الاسم حرفاً بحرف (إلا أن يتطابق المعرّفان فهو هو).
    if (!sameId &&
        qPhone.isNotEmpty &&
        rPhone.isNotEmpty &&
        qPhone != rPhone) {
      continue;
    }
    if (!sameName && !sameId && !samePhone) continue;
    final d = '${r['date'] ?? ''}'.trim();
    if (d.isEmpty || d == 'null') continue;
    final certain = strongId || samePhone;
    // الأحدث أولاً؛ وعند تساوي التاريخ يفوز المؤكَّد (حجبٌ أدقّ).
    if (best == null ||
        d.compareTo(best.date) > 0 ||
        (d == best.date && certain && !best.certain)) {
      best = TriRepeatHit(d, certain: certain);
    }
  }
  return best;
}

/// توافقٌ خلفي (م149-م153): التاريخ وحده بلا درجة التأكّد.
/// يبقى مستعملاً في المسارات التي لا تفرّق بين الحجب والتحذير.
String? lastTriAnalysisDate(
  List<Map<String, Object?>> records, {
  String? patientId,
  required String patientName,
  String clinic = '',
  String phone = '',
  required String Function(String) normalize,
  String Function(String)? normPhone,
}) =>
    lastTriAnalysisHit(
      records,
      patientId: patientId,
      patientName: patientName,
      phone: phone,
      normalize: normalize,
      // بلا مطبِّع هاتفٍ صريح: الأرقام وحدها (نفس تطبيع normPhone عملياً).
      normPhone: normPhone ??
          ((v) => v.replaceAll(RegExp(r'[^0-9]'), '')),
    )?.date;

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

/// م187 — قرار القاعدة بدرجتيه: حجبٌ قاطع أو تحذيرٌ قابل للتجاوز.
enum TriGateKind {
  /// مسموح — لا تحليلَ سابقاً أو انقضت المدة أو القاعدة معطّلة.
  allowed,

  /// هويةٌ مؤكَّدة (هاتف/معرّف) داخل المدة ⇒ رفضٌ قاطع.
  blocked,

  /// تطابقُ اسمٍ بلا هاتفٍ مميِّز ⇒ تحذيرٌ يمضي بموافقة الطبيب.
  warn,
}

/// قرار القاعدة على مريضٍ ما اليوم: نوعُه ورسالته.
class TriGate {
  const TriGate(this.kind, this.message);

  const TriGate.allowed() : kind = TriGateKind.allowed, message = '';

  final TriGateKind kind;
  final String message;

  bool get isAllowed => kind == TriGateKind.allowed;
  bool get isBlocked => kind == TriGateKind.blocked;
  bool get isWarning => kind == TriGateKind.warn;
}

/// م187 — البوابة الموحّدة: تترجم [TriRepeatHit] إلى قرارٍ برسالته.
///
/// **الحجب** حين الهوية مؤكَّدة (نفس الهاتف أو نفس المعرّف) — ولو كان
/// التحليل في عيادةٍ أخرى بالمركز (قرار المالك: النطاق المركز كله).
/// **التحذير** حين التطابق بالاسم وحده — فلا يُحبس الطبيب أمام سميٍّ.
TriGate triRepeatGate({
  required TriRepeatHit? hit,
  required String today,
  required num repeatMonths,
}) {
  if (hit == null) return const TriGate.allowed();
  final months = repeatMonths.toInt();
  if (months <= 0) return const TriGate.allowed();
  if (today.compareTo(addMonths(hit.date, months)) >= 0) {
    return const TriGate.allowed();
  }
  if (hit.certain) {
    return TriGate(
      TriGateKind.blocked,
      'لا يمكن إجراء تحليل ثلاثي جديد لهذا المريض. '
      'آخر تحليل تم بتاريخ ${hit.date}. '
      'يجب مرور $months أشهر على الأقل.',
    );
  }
  return TriGate(
    TriGateKind.warn,
    'يوجد مريض **بنفس الاسم** له تحليل ثلاثي بتاريخ ${hit.date} '
    '(المدة $months أشهر). لا رقم هاتف يميّز بينهما — '
    'إن كان مريضاً آخر فتابع، وإلا فأضِف رقم هاتفه ليتميّز.',
  );
}
