/// ============================================================================
///  فلتر التحاليل — دالة نقية لفلترة بنود التحاليل بالوضع وبالبحث النصي
/// ============================================================================
///
///  تستعمل [arNorm] من lib/core/utils/ar_normalize.dart للمطابقة المقاومة
///  للهمزات والتاء المربوطة (نفس اصطلاح البحث العام في المشروع).
library;

import '../../core/utils/ar_normalize.dart' show arNorm;

/// فلتر بنود التحاليل بالوضع والاستعلام النصي.
///
/// المعاملات:
/// - [rows]  : قائمة صفوف التحاليل (isAnalysis) من TreasurySlice.analyses.
/// - [query] : نص البحث الجزئي — يُطابق اسم المريض أو اسم التحليل؛
///             فارغ = لا تصفية.
/// - [mode]  : وضع الفلتر — أحد: 'all' | 'cash' | 'transfer'.
///             'cash'     → r['payment'] == 'كاش'
///             'transfer' → r['payment'] != 'كاش' (أي تحويل وما شابهه)
///             'all'      → بلا تصفية على طريقة الدفع
///
/// الترتيب لا يتغير — الدالة لا تعيد ترتيب الصفوف.
///
/// مثال:
/// ```dart
/// final visible = filterAnalysesRows(
///   slice.analyses,
///   query: searchCtl.text.trim(),
///   mode: analFilterMode,
/// );
/// ```
List<Map<String, Object?>> filterAnalysesRows(
  List<Map<String, Object?>> rows, {
  required String query,
  required String mode,
}) {
  // تطبيع نص البحث مرة واحدة لتجنب التكرار داخل الحلقة
  final normQ = arNorm(query.trim());

  return [
    for (final r in rows)
      // ── فلتر طريقة الدفع ──────────────────────────────────────────────────
      if (_modeMatch(r, mode))
        // ── فلتر النص ─────────────────────────────────────────────────────
        if (normQ.isEmpty || _textMatch(r, normQ)) r,
  ];
}

/// يتحقق من تطابق الصف مع وضع الدفع المطلوب.
bool _modeMatch(Map<String, Object?> r, String mode) {
  if (mode == 'all') return true;
  // اصطلاح treasury_logic: 'كاش' مقابل أي شيء آخر (تحويل)
  final isCash = r['payment'] == 'كاش';
  if (mode == 'cash') return isCash;
  // mode == 'transfer'
  return !isCash;
}

/// يتحقق من تطابق الصف مع نص البحث المُطبَّع [normQ] على حقلَي الاسم والتحليل.
bool _textMatch(Map<String, Object?> r, String normQ) {
  // اسم المريض — نفس الاصطلاحين المستعمَلين في filteredDetailItems
  final name = arNorm('${r['name'] ?? r['patient_name'] ?? ''}');
  if (name.contains(normQ)) return true;

  // اسم التحليل — الحقلان المستعمَلان في _analDetailTile
  final analysis =
      arNorm('${r['analysisName'] ?? r['service'] ?? ''}');
  return analysis.contains(normQ);
}
