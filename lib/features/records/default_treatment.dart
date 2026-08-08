/// المعالجة الافتراضية في نموذج الرئيسية — التوأم الحرفي لمنطق Vue
/// (AddRecord.defaultService + dc.lastTreatment):
///   الأولوية: آخر اختيار للمستخدم (تفضيل محلي على الجهاز، لا يُزامن)
///   ← ثم المعالجة الافتراضية المُعدّة (config.defaultTreatment)
///   ← ثم أول عنصر في القائمة.
/// تحصين ذاتي: قيمة محفوظة لم تعد في القائمة (أعيدت تسميتها/حُذفت)
/// تُتجاهل فلا يعلق النموذج على خيار بائد.
///
/// v57 — عدالة زمنية: ضبط «المعالجة الافتراضية» صراحةً من الإعدادات
/// يفوز على «آخر اختيار» الأقدم منه (كان آخر الاختيار يفوز دائماً
/// فيبدو الإعداد معطلاً) — يُخزَّن ختم الضبط defaultTreatmentAt في
/// الإعدادات المتزامنة، ويفوز آخر الاختيار فقط إن كان أحدث منه.
library;

import '../../data/db/local_db.dart';

const _lastTreatmentKey = 'dc.lastTreatment';

/// آخر معالجة اختارها المستخدم — localStorage['dc.lastTreatment'] حرفياً
/// (هنا metadata على الجهاز).
String lastTreatment(LocalDb db) {
  try {
    final row = db.queryFirst(
        'SELECT value FROM metadata WHERE key = ?',
        const [_lastTreatmentKey]);
    return '${row?['value'] ?? ''}';
  } catch (_) {
    return '';
  }
}

/// حفظ آخر اختيار فور حفظ سجل — rememberTreatment حرفياً.
void rememberTreatment(LocalDb db, String service) {
  if (service.trim().isEmpty) return;
  try {
    db.execute(
        "INSERT OR REPLACE INTO metadata(key, value, updated_at) "
        "VALUES (?, ?, datetime('now'))",
        [_lastTreatmentKey, service.trim()]);
  } catch (_) {/* التخزين غير متاح — غير حرج */}
}

/// v57 — زمن آخر اختيار (updated_at بصيغة UTC «YYYY-MM-DD HH:MM:SS»).
String lastTreatmentAt(LocalDb db) {
  try {
    final row = db.queryFirst(
        'SELECT updated_at FROM metadata WHERE key = ?',
        const [_lastTreatmentKey]);
    return '${row?['updated_at'] ?? ''}';
  } catch (_) {
    return '';
  }
}

/// v57 — مسح آخر اختيار محلياً (يُستدعى عند ضبط الافتراضية صراحةً
/// من الإعدادات فيسري الضبط لحظياً على هذا الجهاز).
void clearLastTreatment(LocalDb db) {
  try {
    db.execute('DELETE FROM metadata WHERE key = ?',
        const [_lastTreatmentKey]);
  } catch (_) {/* غير حرج */}
}

/// defaultService() — سلسلة الأولوية مع التحصين + عدالة v57 الزمنية:
/// آخر الاختيار يفوز فقط إن كان أحدث من آخر ضبط صريح للإعداد.
String defaultServiceFor(
  LocalDb db,
  Map<String, Object?> config,
  List<String> services,
) {
  final last = lastTreatment(db);
  final pref = '${config['defaultTreatment'] ?? ''}';
  // الطوابع UTC بصيغ قابلة للمقارنة نصياً (التطبيع: T ← فراغ).
  final lastAt = lastTreatmentAt(db).replaceAll('T', ' ');
  final prefAt =
      '${config['defaultTreatmentAt'] ?? ''}'.replaceAll('T', ' ');
  final lastFresh = prefAt.isEmpty ||
      (lastAt.isNotEmpty && lastAt.compareTo(prefAt) > 0);
  if (lastFresh && last.isNotEmpty && services.contains(last)) {
    return last;
  }
  if (pref.isNotEmpty && services.contains(pref)) return pref;
  // تحصين: إعداد بائد (خدمة حُذفت) وآخر اختيار صالح ← آخر الاختيار.
  if (last.isNotEmpty && services.contains(last)) return last;
  return services.isNotEmpty ? services.first : '';
}
