/// ============================================================================
///  م100 — وحدة عرض ترقيم الأسنان (طبقةُ عرضٍ نقيّة فوق التخزين المحايد)
/// ============================================================================
///
///  المبدأ (مطابقٌ لممارسة Open Dental وغيرها، وموثَّق في تقرير المرحلة 1):
///  التخزين يبقى محايداً حرفياً — كلُّ سنٍّ `{q, n}` حيث q رُبعٌ
///  (UR/UL/LR/LL) وn موضعُه من الخط المتوسط (1..8 دائم، 1..5 لبني)، وهي
///  **بنية ISO 3950 نفسها**. أنظمةُ الترقيم (Palmer / FDI) وطقمُ الأسنان
///  (دائم/لبني) مجرّدُ **عرضٍ** فوق هذا التخزين: التبديل لا يمسّ بايتاً
///  واحداً مخزّناً، والبيانات القديمة تعمل فوراً (غيابُ وسم اللبني = دائم).
///
///  التصميم قابلٌ للتوسّع: إضافة Universal أو نظام لبنيٍّ آخر مستقبلاً =
///  فرعٌ واحد في [toothLabel] بلا إعادة كتابة المنظومة (طلب المالك).
///
///  المراجع: ISO 3950:2016 (FDI الثنائي)، ADA (Universal)، ورموز Palmer —
///  انظر «تقرير المرحلة الأولى — أنظمة ترقيم الأسنان (م100)».
library;

/// نظام الترقيم المعروض. الغياب/الافتراض = Palmer (توافق النسخ السابقة —
/// انظر [notationSystemFromConfig]).
enum NotationSystem { palmer, fdi }

/// طقم الأسنان. الغياب في التخزين = [adult] (توافق البيانات القديمة).
enum Dentition { adult, primary }

const _kQuadrants = ['UR', 'UL', 'LR', 'LL'];

/// الرقم الأول في FDI (الربع): يفرّق الدائم عن اللبني — ISO 3950 §4-a.
const Map<Dentition, Map<String, int>> _fdiQuadrantDigit = {
  Dentition.adult: {'UR': 1, 'UL': 2, 'LL': 3, 'LR': 4},
  Dentition.primary: {'UR': 5, 'UL': 6, 'LL': 7, 'LR': 8},
};

/// حرف Palmer اللبني: 1→A .. 5→E (طلب المالك: A→E).
String _primaryLetter(int n) => String.fromCharCode('A'.codeUnitAt(0) + n - 1);

/// أقصى عددٍ للأسنان في الربع حسب الطقم (8 دائم، 5 لبني).
int teethPerQuadrant(Dentition d) => d == Dentition.adult ? 8 : 5;

/// نصُّ نظامٍ لواجهة الإعدادات.
String notationSystemLabel(NotationSystem s) =>
    s == NotationSystem.palmer ? 'Palmer' : 'FDI (ISO 3950)';

/// قراءة تفضيل النظام من قيمةٍ مخزَّنة (app.config، مُزامَن).
///
/// **الغياب/المجهول = Palmer**: هو ما تعرضه النسخُ السابقة فعلاً (الرقم
/// المحايد بلا زاوية الربع)، فإبقاؤه افتراضاً يحفظ تجربة المستخدمين
/// الحاليين حرفياً (الرقم نفسه، تُضاف إليه زاويةُ الربع الصحيحة)، وFDI
/// خيارٌ يُفعّله من يريده.
NotationSystem notationSystemFromConfig(Object? v) =>
    '${v ?? ''}' == 'fdi' ? NotationSystem.fdi : NotationSystem.palmer;

String notationSystemToConfig(NotationSystem s) =>
    s == NotationSystem.palmer ? 'palmer' : 'fdi';

/// طقمُ سنٍّ من عنصر التخزين: الوسم `d == 'P'` ⇒ لبني، وإلا دائم
/// (توافقٌ تامٌّ مع الصفوف القديمة التي لا تحمل الوسم).
Dentition dentitionOfTooth(Map tooth) =>
    '${tooth['d'] ?? ''}' == 'P' ? Dentition.primary : Dentition.adult;

// ── مفاتيح الأسنان النصية (م100/7) ─────────────────────────────────────────
//
//  مفتاح واجهةِ الاختيار: `q:n` للدائم (كما كان حرفياً منذ البداية) و
//  `q:n:P` للّبني — **لاحقة إضافية بحتة**: كلُّ مستهلكٍ قديم يفكّك بالنقطتين
//  يقرأ q وn الصحيحين، والبيانات القديمة لا تنتج اللاحقة أصلاً.

/// توليد مفتاح السن.
String toothKey(String q, int n, {Dentition dentition = Dentition.adult}) =>
    dentition == Dentition.primary ? '$q:$n:P' : '$q:$n';

/// مفتاحُ عنصرِ تخزينٍ `{q,n,d?}` (يقرأ وسم الطقم).
String toothKeyOfTooth(Map t) => toothKey(
      '${t['q'] ?? 'UR'}',
      (num.tryParse('${t['n'] ?? 1}') ?? 1).toInt(),
      dentition: dentitionOfTooth(t),
    );

/// تفكيك مفتاحٍ — يتقبّل الشكلين (القديم بلا لاحقة والجديد بها) بأمان،
/// ويسقط إلى UR:1 دائم عند أي تلف بدل الرمي.
({String q, int n, Dentition dentition}) parseToothKey(String key) {
  final parts = key.split(':');
  final q =
      parts.isNotEmpty && _kQuadrants.contains(parts[0]) ? parts[0] : 'UR';
  final n = parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : 1;
  final d = parts.length > 2 && parts[2] == 'P'
      ? Dentition.primary
      : Dentition.adult;
  return (q: q, n: n, dentition: d);
}

/// عنصرُ تخزينٍ من مفتاح: `{q,n}` للدائم و`{q,n,d:'P'}` للّبني.
///
/// **قرار التوافق (المعتمَد)**: الوسم يُكتب **للّبني فقط** — صفوف الدائم
/// تبقى بالبنية القديمة بايتاً ببايت، فلا يتغيّر أي صفٍّ قائم ولا تتأثر
/// المزامنة أو النسخ الأقدم التي تتجاهل الحقول الزائدة أصلاً.
Map<String, Object?> toothFromKey(String key) {
  final p = parseToothKey(key);
  return {
    'q': p.q,
    'n': p.n,
    if (p.dentition == Dentition.primary) 'd': 'P',
  };
}

/// نتيجةُ العرض: النصُّ الظاهر + الربع + أنَعرِض إطارَ Palmer الربعي؟
class ToothLabel {
  const ToothLabel(this.text, this.quadrant, {this.palmerBorder = false});

  /// الرمز المعروض: «6» أو «16» أو «A» أو «55».
  final String text;

  /// الربع (UR/UL/LR/LL) — يقود إطار Palmer.
  final String quadrant;

  /// هل يُرسَم إطار Palmer الربعي حول النص؟ (Palmer نعم، FDI لا).
  final bool palmerBorder;
}

/// **قلب الوحدة**: يحوّل السنَّ المحايد (ربع q، موضع n، طقم) إلى عرضٍ
/// حسب النظام المختار. نقيٌّ بالكامل — قابلٌ للاختبار الوحدوي.
///
///   • **Palmer**: النصُّ هو الموضع نفسه (دائم 1..8)، وللّبني حرفٌ A..E؛
///     مع إطارٍ ربعيٍّ (رمز Zsigmondy–Palmer). يطابق مرجع Vue حرفياً.
///   • **FDI (ISO 3950)**: رقمان — الأول للربع (دائم 1..4 / لبني 5..8)
///     والثاني الموضع؛ بلا إطار. مثال UR:6 دائم ⇒ «16»، UR:5 لبني ⇒ «55».
ToothLabel toothLabel(
  String q,
  int n, {
  required NotationSystem system,
  Dentition dentition = Dentition.adult,
}) {
  final quad = _kQuadrants.contains(q) ? q : 'UR';
  switch (system) {
    case NotationSystem.palmer:
      final text =
          dentition == Dentition.primary ? _primaryLetter(n) : '$n';
      return ToothLabel(text, quad, palmerBorder: true);
    case NotationSystem.fdi:
      final first = _fdiQuadrantDigit[dentition]![quad]!;
      return ToothLabel('$first$n', quad);
  }
}

/// مساعدٌ من المفتاح النصي `q:n` أو `q:n:P` — لاحقةُ اللبني في المفتاح
/// **تتقدّم** على معامل [dentition] (المفتاح يحمل حقيقة السن نفسه).
ToothLabel toothLabelFromKey(
  String key, {
  required NotationSystem system,
  Dentition dentition = Dentition.adult,
}) {
  final p = parseToothKey(key);
  final d = p.dentition == Dentition.primary ? Dentition.primary : dentition;
  return toothLabel(p.q, p.n, system: system, dentition: d);
}

/// عرضُ سنٍّ من عنصر التخزين مباشرةً (يقرأ الطقم من الوسم `d`).
ToothLabel toothLabelFromTooth(Map tooth, {required NotationSystem system}) {
  final q = '${tooth['q'] ?? 'UR'}';
  final n = (num.tryParse('${tooth['n'] ?? 1}') ?? 1).toInt();
  return toothLabel(q, n,
      system: system, dentition: dentitionOfTooth(tooth));
}
