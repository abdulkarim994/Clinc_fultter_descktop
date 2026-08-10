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
/// - [clinic]: م149 — اسم عيادةٍ للتقييد بها (يطابق clinic ثم clinic_id)؛
///             فارغ = كل العيادات.
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
  String clinic = '',
}) {
  // تطبيع نص البحث مرة واحدة لتجنب التكرار داخل الحلقة
  final normQ = arNorm(query.trim());
  final wantClinic = clinic.trim();

  return [
    for (final r in rows)
      // ── فلتر العيادة (م149) ──────────────────────────────────────────────
      if (wantClinic.isEmpty || _clinicMatch(r, wantClinic))
        // ── فلتر طريقة الدفع ───────────────────────────────────────────────
        if (_modeMatch(r, mode))
          // ── فلتر النص ────────────────────────────────────────────────────
          if (normQ.isEmpty || _textMatch(r, normQ)) r,
  ];
}

/// م149 — هل الصف تابعٌ للعيادة المطلوبة؟ يطابق clinic ثم clinic_id
/// (الكاتبان يخزّنان الاسم في كليهما — الاحتياط للصفوف القديمة).
bool _clinicMatch(Map<String, Object?> r, String clinic) {
  final c = '${r['clinic'] ?? ''}'.trim();
  if (c.isNotEmpty && c != 'null') return c == clinic;
  return '${r['clinic_id'] ?? ''}'.trim() == clinic;
}

/// م149 — صفوف الشهر التقويمي الجاري فقط (بادئة YYYY-MM من [today]).
/// «التصفير التلقائي» أول كل شهر يتحقق ذاتياً: الاستعلام مقيّدٌ بالشهر
/// فلا حاجة لأي حذفٍ أو مؤقّت.
List<Map<String, Object?>> currentMonthRows(
  List<Map<String, Object?>> rows, {
  required String today,
}) {
  final prefix = today.length >= 7 ? today.substring(0, 7) : today;
  return [
    for (final r in rows)
      if ('${r['date'] ?? ''}'.startsWith(prefix)) r,
  ];
}

/// م149 — إجمالي مبالغ صفوف الشهر الجاري (ذيل بطاقة «سجلات التحاليل»).
num currentMonthTotal(
  List<Map<String, Object?>> rows, {
  required String today,
}) {
  num sum = 0;
  for (final r in currentMonthRows(rows, today: today)) {
    final v = r['amount'];
    sum += v is num ? v : (num.tryParse('$v') ?? 0);
  }
  return sum;
}

/// م154 — صفوف تحاليل شهرٍ مختار (YYYY-MM) من صفوف السجلات الخام، بمنع
/// تكرارٍ بالمعرّف الفريد (صفٌّ مكرر بالمزامنة يُحتسب مرة) — مرتبةً
/// الأحدث أولاً. يوم الاحتساب: incomeDate يتقدم على date.
List<Map<String, Object?>> monthAnalysesRows(
  List<Map<String, Object?>> records, {
  required String month,
}) {
  final seen = <String>{};
  final out = <Map<String, Object?>>[];
  for (final r in records) {
    final flag = r['isAnalysis'];
    final isAnal = flag == true || flag == 1 || flag == '1' || flag == 'true';
    if (!isAnal) continue;
    final id = '${r['id'] ?? ''}';
    if (id.isEmpty || id == 'null' || !seen.add(id)) continue;
    final effDay = ('${r['incomeDate'] ?? ''}'.trim().isNotEmpty &&
            '${r['incomeDate']}' != 'null')
        ? '${r['incomeDate']}'
        : '${r['date'] ?? ''}';
    if (!effDay.startsWith(month)) continue;
    out.add(r);
  }
  out.sort((a, b) => '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'));
  return out;
}

/// م154 — إجماليات تحاليل شهرٍ مختار (كاش/تحويل) — الخزينة الجديدة تعرضها
/// بنطاق مبدّل الشهر فتصفر تلقائياً مطلع كل شهر (اصطلاح الخزينة: 'كاش'
/// مقابل أي شيءٍ آخر = تحويل).
({num cash, num transfer}) monthAnalysesTotals(
  List<Map<String, Object?>> records, {
  required String month,
}) {
  num cash = 0, transfer = 0;
  for (final r in monthAnalysesRows(records, month: month)) {
    final v = r['amount'];
    final amt = v is num ? v : (num.tryParse('$v') ?? 0);
    if (r['payment'] == 'كاش') {
      cash += amt;
    } else {
      transfer += amt;
    }
  }
  return (cash: cash, transfer: transfer);
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
