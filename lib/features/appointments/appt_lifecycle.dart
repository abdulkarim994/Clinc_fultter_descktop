/// م164 — دورة حياة الموعد ونظام العيادات الإلزامي (منطق نقي قابل للاختبار):
///   • كتالوج الحالات الموحّد (قادم/مؤكد/حضر/بالانتظار/داخل المعالجة/مكتمل/
///     ملغى/لم يحضر) بألوان هادئة والاسمُ يظهر دائماً بجانب اللون — القيم
///     القديمة pending/scheduled تُقرأ «قادم» بلا لمس البيانات المخزنة.
///   • الحالات النهائية تُختم بتاريخ الأرشفة (archivedOn) وتنتقل لقسم
///     «أرشيف اليوم»؛ تبقى يومين ثم تُحذف بشواهد قبور تمر بالمزامنة
///     (نفس نمط purgeOldDays في نظام الدور).
///   • الاستراحة ☕ صفٌّ بعلم isBreak: 1 (أرقام لا قيم منطقية) — لا تُحسب
///     مريضاً ولا تدخل القادمة أو العدّادات ولا يمكن الحجز فوقها.
///   • bookingSystemOf: المصدرُ الوحيد لقراءة إعداد نوع الحجز (تقليدي/دور).
///   • شبكة الأوقات من ساعات الدوام (workdayStart/workdayEnd) وكشف تعارض
///     المدد [الوقت، الوقت+المدة) — الافتراضي 30 دقيقة.
library;

import 'dart:ui' show Color;

import '../../core/utils/js_compat.dart';

typedef JMap = Map<String, Object?>;

// ── كتالوج الحالات ───────────────────────────────────────────────────────────

/// الحالات المعتمدة بترتيب سير العمل الطبيعي.
const kApptStatusFlow = [
  'upcoming', 'confirmed', 'arrived', 'waiting', 'in_treatment', 'completed',
];

/// الحالات النهائية — تُؤرشف ولا تظهر في الجدول الحالي ولا القادمة.
const kTerminalStatuses = {'completed', 'cancelled', 'no_show'};

/// توحيد قيمة الحالة — القيم القديمة (pending/scheduled/فارغ) ⇒ «قادم».
String normApptStatus(Object? raw) {
  final s = '${raw ?? ''}';
  return switch (s) {
    'confirmed' || 'arrived' || 'waiting' || 'in_treatment' => s,
    'completed' || 'cancelled' || 'no_show' => s,
    _ => 'upcoming',
  };
}

/// الاسم العربي للحالة — يظهر دائماً بجانب اللون (اللون ليس وحده).
String apptStatusLabel(Object? raw) => switch (normApptStatus(raw)) {
      'confirmed' => 'مؤكد',
      'arrived' => 'حضر',
      'waiting' => 'بالانتظار',
      'in_treatment' => 'داخل المعالجة',
      'completed' => 'مكتمل',
      'cancelled' => 'ملغى',
      'no_show' => 'لم يحضر',
      _ => 'قادم',
    };

/// لون الحالة — درجات هادئة احترافية (لا صارخة).
Color apptStatusColor(Object? raw) => switch (normApptStatus(raw)) {
      'confirmed' => const Color(0xFF0E7490), // سِيان هادئ
      'arrived' => const Color(0xFF7C3AED), // بنفسجي هادئ
      'waiting' => const Color(0xFFB45309), // كهرماني غامق
      'in_treatment' => const Color(0xFF1D4ED8), // أزرق
      'completed' => const Color(0xFF15803D), // أخضر
      'cancelled' => const Color(0xFFB91C1C), // أحمر هادئ
      'no_show' => const Color(0xFF9F1239), // وردي غامق
      _ => const Color(0xFF15604A), // قادم — أخضر العلامة
    };

/// هل الحالة نهائية (تُؤرشف)؟
bool isTerminalStatus(Object? raw) =>
    kTerminalStatuses.contains(normApptStatus(raw));

/// الحالة التالية في سير العمل بنقرة واحدة — null عند النهاية.
String? nextApptStatus(Object? raw) {
  final s = normApptStatus(raw);
  final i = kApptStatusFlow.indexOf(s);
  if (i < 0 || i >= kApptStatusFlow.length - 1) return null;
  return kApptStatusFlow[i + 1];
}

// ── الاستراحة ────────────────────────────────────────────────────────────────

/// هل الصف استراحة؟ (علم رقمي isBreak: 1 — لا قيم منطقية).
bool isBreakRow(JMap a) => jsTruthy(a['isBreak']);

/// مدة الصف بالدقائق — durationMin أو الافتراضي 30.
int apptDurationMin(JMap a) {
  final n = jsNumOr0(a['durationMin']).toInt();
  return n > 0 ? n : 30;
}

// ── الأرشيف ودورة الحياة ─────────────────────────────────────────────────────

/// يوم أرشفة الصف — ختم archivedOn، وللقديم المكتمل بلا ختم: تاريخ الموعد.
String archiveDayOf(JMap a) {
  final on = '${a['archivedOn'] ?? ''}';
  return on.isNotEmpty ? on : '${a['date'] ?? ''}';
}

/// تقسيم صفوف يومٍ إلى (نشِطة، مؤرشفة) — لا ازدواج بين الجدول والأرشيف.
(List<JMap>, List<JMap>) splitDayRows(List<JMap> rows) {
  final active = <JMap>[];
  final archived = <JMap>[];
  for (final a in rows) {
    (isTerminalStatus(a['status']) && a['_src'] != 'rec' ? archived : active)
        .add(a);
  }
  return (active, archived);
}

/// معرّفات الصفوف المؤرشفة الأقدم من يومين — للحذف بشواهد قبور.
/// «يبقى يومين»: يومُ الأرشفة ويومٌ بعده؛ الحذف عندما يمر يومان كاملان.
List<String> archivedIdsToPurge(List<JMap> appts, String today) {
  final t = DateTime.tryParse('${today}T00:00:00');
  if (t == null) return const [];
  final out = <String>[];
  for (final a in appts) {
    if (!isTerminalStatus(a['status'])) continue;
    final day = archiveDayOf(a);
    final d = DateTime.tryParse('${day}T00:00:00');
    if (d == null) continue;
    if (t.difference(d).inDays >= 2) out.add('${a['id']}');
  }
  return out;
}

// ── العيادات ─────────────────────────────────────────────────────────────────

/// قيمة فلتر «المواعيد القديمة بلا عيادة».
const kNoClinic = '__none__';

/// قائمة العيادات من الإعدادات.
List<String> clinicsOf(JMap cfg) => cfg['clinics'] is List
    ? [for (final c in cfg['clinics'] as List) '$c']
    : const [];

/// هل اختيار العيادة إلزامي؟ (أكثر من عيادة ⇒ لا حفظ بلا اختيار،
/// وعيادة واحدة ⇒ تُختار تلقائياً بلا نقرة زائدة — قرار المالك).
bool clinicRequired(JMap cfg) => clinicsOf(cfg).length > 1;

/// عيادة الصف — فارغة للقديم غير المحدد.
String apptClinicOf(JMap a) => '${a['clinic'] ?? ''}';

/// فلترة صفوف بعيادة — [clinic] فارغة = الكل، [kNoClinic] = غير المحددة.
List<JMap> filterByClinic(List<JMap> rows, String clinic) {
  if (clinic.isEmpty) return rows;
  if (clinic == kNoClinic) {
    return [for (final a in rows) if (apptClinicOf(a).isEmpty) a];
  }
  return [for (final a in rows) if (apptClinicOf(a) == clinic) a];
}

/// هل توجد صفوف قديمة بلا عيادة؟ (لإظهار فلتر «غير محددة» فقط عند الحاجة).
bool hasUnassignedClinic(List<JMap> appts) =>
    appts.any((a) => apptClinicOf(a).isEmpty && a['_src'] != 'rec');

// ── نوع الحجز — المصدر الوحيد ────────────────────────────────────────────────

/// قراءة إعداد نوع الحجز: 'queue' (بالدور) أو 'traditional' (جدول زمني).
String bookingSystemOf(JMap cfg) =>
    cfg['bookingSystem'] == 'queue' ? 'queue' : 'traditional';

// ── شبكة الأوقات وكشف التعارض ────────────────────────────────────────────────

/// "HH:MM" ⇒ دقائق منذ منتصف الليل — null للفارغ/غير الصالح.
int? hhmmToMinutes(Object? t) {
  final s = '${t ?? ''}';
  if (s.isEmpty) return null;
  final parts = s.split(':');
  final h = int.tryParse(parts[0]);
  if (h == null) return null;
  final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return h * 60 + m;
}

String minutesToHHMM(int mins) =>
    '${(mins ~/ 60).toString().padLeft(2, '0')}:'
    '${(mins % 60).toString().padLeft(2, '0')}';

/// شبكة أوقات الدوام [start..end) بخطوة [stepMin] — من إعدادات
/// workdayStart/workdayEnd (الافتراضي 09:00–21:00 كما الإعدادات).
List<String> buildTimeSlots(JMap cfg, {int stepMin = 30}) {
  final s = hhmmToMinutes(jsOr(cfg['workdayStart'], '09:00')) ?? 540;
  final e = hhmmToMinutes(jsOr(cfg['workdayEnd'], '21:00')) ?? 1260;
  final out = <String>[];
  for (var m = s; m < e; m += stepMin) {
    out.add(minutesToHHMM(m));
  }
  return out;
}

/// أول صفٍّ يتعارض مدته مع [time]+[durMin] في نفس اليوم والعيادة — null
/// عند الخلو. الاستراحة تَحجب دائماً؛ الموعد يتعارض تحذيراً (قرار المالك:
/// الاستراحة منعٌ قاطع والموعد تحذير قابل للتجاوز). المؤرشف لا يَحجب.
JMap? overlappingRow(
  List<JMap> dayRows,
  String time,
  int durMin, {
  String? exceptId,
}) {
  final start = hhmmToMinutes(time);
  if (start == null) return null;
  final end = start + durMin;
  for (final a in dayRows) {
    if (exceptId != null && '${a['id']}' == exceptId) continue;
    if (isTerminalStatus(a['status']) && !isBreakRow(a)) continue;
    if (a['_src'] == 'rec') continue;
    final s = hhmmToMinutes(a['time']);
    if (s == null) continue;
    final e = s + apptDurationMin(a);
    if (start < e && s < end) return a;
  }
  return null;
}

/// القادمة لعيادةٍ — كالقادمة العامة لكن: تستثني النهائية والاستراحات
/// و«لم يحضر»، وتُفلتر بالعيادة (فارغة = الكل)، حد 12.
List<JMap> upcomingForClinic(
  Map<String, List<JMap>> apptMap,
  String clinic, {
  required String today,
}) {
  final all = [for (final l in apptMap.values) ...l];
  final list = [
    for (final a in filterByClinic(all, clinic))
      if ('${a['date']}'.compareTo(today) >= 0 &&
          !isTerminalStatus(a['status']) &&
          !isBreakRow(a))
        a,
  ]..sort((a, b) {
      final c = '${a['date']}'.compareTo('${b['date']}');
      if (c != 0) return c;
      return '${a['time'] ?? ''}'.compareTo('${b['time'] ?? ''}');
    });
  return list.take(12).toList();
}
