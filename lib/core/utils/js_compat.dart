/// ============================================================================
///  JS-semantics compatibility helpers
/// ============================================================================
///
///  The Vue codebase relies on JavaScript coercion quirks in FINANCIAL code
///  paths (e.g. `Number(debt.paidAmount || debt.paid_amount) || 0`). A literal
///  port must reproduce those semantics exactly — silently "fixing" them would
///  change amounts. These helpers centralise the quirks and document them.
library;

/// JS truthiness: null/undefined, 0, NaN, '' and false are falsy.
bool jsTruthy(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0 && !v.isNaN;
  if (v is String) return v.isNotEmpty;
  return true; // objects/arrays are always truthy
}

/// JS `a || b` — first truthy operand (or the last operand).
Object? jsOr(Object? a, Object? b) => jsTruthy(a) ? a : b;

/// JS `Number(v)` — num passthrough, numeric strings parse, '' → 0,
/// null → 0 (JS Number(null) is 0), true/false → 1/0, otherwise NaN.
double jsNumber(Object? v) {
  if (v == null) return 0; // Number(null) === 0
  if (v is num) return v.toDouble();
  if (v is bool) return v ? 1 : 0;
  if (v is String) {
    final t = _foldArabicDigits(v.trim());
    if (t.isEmpty) return 0; // Number('') === 0
    return double.tryParse(t) ?? double.nan;
  }
  return double.nan;
}

/// يطوي الأرقام العربية‑الهندية إلى ASCII قبل التحليل.
///
/// ⚠ إصلاح مالي (م84): كل الواجهة عربية، ولوحةُ مفاتيح رقمية في بيئة عربية
/// تُخرج `٠–٩` (U+0660) أو `۰–۹` الفارسية (U+06F0). و`double.tryParse` لا
/// يفهمها ⇒ NaN ⇒ `jsNumOr0` يعيد صفراً **صامتاً**. فتكلفةُ مختبر تُدخَل
/// `١٥٠٠` تصير 0، فيُحسب صافي الربح ونصيبُ الطبيب على مبلغٍ خاطئ بلا أي
/// خطأ ظاهر. (رُصد بالتشغيل.) الطيّ هنا — نقطةُ الاختناق الوحيدة لكل تحويل
/// رقمي — يعالج المصدرين، والفاصلةَ العشرية العربية `٫` (U+066B)، ويتجاهل
/// فاصل الآلاف `٬` (U+066C). والمدخل ASCII لا يتغيّر بتّةً.
String _foldArabicDigits(String s) {
  if (s.isEmpty) return s;
  var touched = false;
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      out.writeCharCode(0x30 + (r - 0x0660)); // عربي‑هندي
      touched = true;
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      out.writeCharCode(0x30 + (r - 0x06F0)); // عربي‑هندي ممتد (فارسي)
      touched = true;
    } else if (r == 0x066B) {
      out.writeCharCode(0x2E); // الفاصلة العشرية العربية ⇒ نقطة
      touched = true;
    } else if (r == 0x066C || r == 0x060C) {
      touched = true; // فاصل الآلاف/الفاصلة ⇒ يُسقَط
    } else {
      out.writeCharCode(r);
    }
  }
  return touched ? out.toString() : s;
}

/// JS `Number(x) || 0` — the ubiquitous "coerce, defaulting to 0" idiom
/// (also collapses NaN to 0, matching `||`).
double jsNumOr0(Object? v) {
  final n = jsNumber(v);
  return (n.isNaN || n == 0) ? 0 : n;
}

/// JS `Math.round` for the positive amounts used in this app (half away from
/// zero — Dart's `round()` matches for positives).
int jsRound(double v) => v.round();

/// JS `Math.round(x * 100) / 100` — 2-dp rounding used across the money code.
double round2(double v) => (v * 100).roundToDouble() / 100;

/// JS `new Date().toISOString()` — UTC, milliseconds precision, 'Z' suffix.
String jsIsoNow() {
  final d = DateTime.now().toUtc();
  String p2(int n) => n.toString().padLeft(2, '0');
  String p3(int n) => n.toString().padLeft(3, '0');
  return '${d.year.toString().padLeft(4, '0')}-${p2(d.month)}-${p2(d.day)}'
      'T${p2(d.hour)}:${p2(d.minute)}:${p2(d.second)}.${p3(d.millisecond)}Z';
}

/// JS `Date.now()` — epoch milliseconds.
int jsNow() => DateTime.now().millisecondsSinceEpoch;

/// Local ISO date `YYYY-MM-DD` — port of utils/format `getCurrentDate()`
/// (which returns the LOCAL date, not UTC).
String getCurrentDate() {
  final d = DateTime.now();
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
