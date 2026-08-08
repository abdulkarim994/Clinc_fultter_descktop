/// سجل التعديلات (م64/م65) — التوأم الحرفي لـ utils/audit.js:
/// قيود تُخزَّن على الصف نفسه في مصفوفة `_audit` فتسافر مع المزامنة
/// وتنجو أوفلاين بلا جدول منفصل. كل قيد: {field, label, old, new, at}
/// والسقف 50 قيداً (الأحدث يبقى).
library;

typedef JMap = Map<String, Object?>;

const int _auditCap = 50;

/// وسوم عربية للحقول — AUDIT_FIELD_LABELS (+ «نوع المعالجة» للخدمة
/// كما في قيود Vue الصريحة).
const Map<String, String> auditFieldLabels = {
  'name': 'اسم المريض',
  'phone': 'رقم الهاتف',
  'phone2': 'رقم هاتف إضافي',
  'amount': 'القيمة',
  'total': 'القيمة',
  'labValue': 'قيمة المختبر',
  'date': 'التاريخ',
  'payment': 'طريقة الدفع',
  'service': 'نوع المعالجة',
  'notes': 'ملاحظات',
  'report': 'تحديد الأسنان',
};

String _fmt(Object? v) {
  if (v == null || '$v'.isEmpty) return '—';
  return '$v';
}

/// يبني قيود الفروق (الحقول المتغيرة فعلاً فقط) ويضيفها لمصفوفة الصف
/// القائمة بسقف 50. [valueOverrides] لقيم معروضة جاهزة (مثل عدّ الأسنان
/// «N سن ← M سن») — يتخطى القيد إن تساوت old/new.
List<JMap> appendAudit(
  JMap old,
  Map<String, Object?> changes, {
  int? at,
  Map<String, ({String old, String new_})> valueOverrides = const {},
}) {
  final ts = at ?? DateTime.now().millisecondsSinceEpoch;
  final existing = old['_audit'];
  final out = <JMap>[
    for (final a in (existing is List ? existing : const []))
      if (a is Map) Map<String, Object?>.from(a),
  ];
  changes.forEach((field, newVal) {
    final ov = valueOverrides[field];
    if (ov != null) {
      if (ov.old == ov.new_) return;
      out.add({
        'field': field,
        'label': auditFieldLabels[field] ?? field,
        'old': ov.old,
        'new': ov.new_,
        'at': ts,
      });
      return;
    }
    final oldVal = old[field];
    if ('${oldVal ?? ''}' == '${newVal ?? ''}') return;
    out.add({
      'field': field,
      'label': auditFieldLabels[field] ?? field,
      'old': _fmt(oldVal),
      'new': _fmt(newVal),
      'at': ts,
    });
  });
  if (out.length > _auditCap) {
    out.sort((a, b) =>
        (a['at'] as num? ?? 0).compareTo(b['at'] as num? ?? 0));
    return out.sublist(out.length - _auditCap);
  }
  return out;
}

/// هل للصف قيود تعديل؟ (يظهر «معدل» أيضاً لمن عُدلت بياناته الاسمية
/// بلا علم _edited — سلوك Vue مع تعديل بيانات المريض).
bool hasAudit(JMap e) {
  final a = e['_audit'];
  return a is List && a.isNotEmpty;
}
