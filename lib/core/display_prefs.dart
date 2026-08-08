/// م116 — تفضيلات العرض العامة (قرار المالك): تُضبط من شاشة الإعدادات
/// وتقرؤها المنسقات المركزية في كل التطبيق:
///   • نظام الأرقام: غربي 123 (الافتراضي) أو هندي ١٢٣ — يسري على كل
///     الأرقام المالية والساعات والتواريخ المارة بالمنسقات المركزية.
///   • نظام الوقت: 12 ساعة بصيغة ص/م (الافتراضي) أو 24 ساعة — منسق
///     ساعة واحد [formatClock] لكل عروض الساعة.
///   • فاصل الفترة الصباحية/المسائية لدخل اليوم (الافتراضي 12 ظهراً).
///
/// النمط: متغيرات عامة تضبطها [applyDisplayPrefs] عند كل بناء للصدفة
/// (نفس نمط pdfLogoBytes) — فلا حاجة لتمرير الإعدادات عبر مئات المواضع.
library;

bool kArabicDigits = false;
bool k24Hour = false;
int kPeriodCutoffHour = 12;

const _east = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

/// تحويل أرقام النص إلى الهندية متى فُعّل الإعداد (وإلا يعيده كما هو).
String appDigits(String s) {
  if (!kArabicDigits) return s;
  final b = StringBuffer();
  for (final ch in s.codeUnits) {
    if (ch >= 0x30 && ch <= 0x39) {
      b.write(_east[ch - 0x30]);
    } else {
      b.writeCharCode(ch);
    }
  }
  return b.toString();
}

/// منسق الساعة المركزي الموحد: 12 ساعة (ص/م) أو 24 — بأرقام الإعداد.
String formatClock(num ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  String two(int v) => v.toString().padLeft(2, '0');
  if (k24Hour) return appDigits('${two(d.hour)}:${two(d.minute)}');
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final suf = d.hour < 12 ? 'ص' : 'م';
  return appDigits('$h12:${two(d.minute)} $suf');
}

/// صيغة «ساعة:دقيقة» نصية (HH:mm) بحسب إعداد 12/24 — للمواعيد ونحوها.
String formatClockHm(String hm) {
  final parts = hm.split(':');
  if (parts.length < 2) return appDigits(hm);
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  String two(int v) => v.toString().padLeft(2, '0');
  if (k24Hour) return appDigits('${two(h)}:${two(m)}');
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final suf = h < 12 ? 'ص' : 'م';
  return appDigits('$h12:${two(m)} $suf');
}

/// ضبط التفضيلات من إعدادات التطبيق — تُستدعى عند كل بناء للصدفة.
void applyDisplayPrefs(Map<String, Object?> cfg) {
  kArabicDigits = cfg['digitStyle'] == 'arabic';
  k24Hour = cfg['timeFormat'] == '24';
  final c = cfg['periodCutoffHour'];
  kPeriodCutoffHour = (c is num ? c.toInt() : 12).clamp(1, 23);
}
