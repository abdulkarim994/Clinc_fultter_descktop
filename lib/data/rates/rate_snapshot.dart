/// ============================================================================
///  لقطة النسب المجمّدة — نقل rates/rate-snapshot.service + clinic-rates
/// ============================================================================
///
///  القاعدة: أي عملية مالية تُنشأ تحمل `_rateSnapshot` غير قابل للتغيير يصف
///  التقسيم لحظة الإنشاء (عيادة ← معالجة ← نسبة)، فلا تُعاد قسمتها أبداً
///  بالنسب الحية. التسلسل: clinicRates.clinics[clinic].treatments[service]
///  (أو .prosthetics للتركيبات) ← config.doctorPct ← 50.
library;

import '../../core/utils/js_compat.dart';

const rateSnapshotVersion = 1;

/// م180 — مفتاح ميزة «نسبة المعالجات» (قرار المالك): **مطفأة افتراضياً**
/// — طبيبٌ وحده لا يحتاجها والإجمالي كله للعيادة.
///
/// الدلالة الثلاثية:
///  • قيمة صريحة (true/false) ⇒ تُحترم حرفياً (مفتاح الإعدادات).
///  • غيابها + إعداداتٌ قديمة ضبطت نسباً صراحةً (doctorPct أو
///    clinicRates) ⇒ **مفعّلة** — دلالة الإرث تحفظ سلوك الحسابات
///    القائمة (قرار المالك: «يبقى مفعلاً تلقائياً») وكلَّ منطقٍ نقي
///    قديم مرّر نسباً بلا علم. ترحيل app_shell يثبّتها قيمةً صريحة.
///  • غيابها بلا أي نسب ⇒ مطفأة (الحسابات الجديدة).
bool ratesFeatureEnabled(Map<String, Object?> config) {
  final v = config['ratesEnabled'];
  if (v != null) return v == true;
  if (config['doctorPct'] != null) return true;
  final rates = config['clinicRates'];
  return rates is Map &&
      rates['clinics'] is Map &&
      (rates['clinics'] as Map).isNotEmpty;
}

double _clampPct(Object? v, [double fallback = 50]) {
  final n = jsNumber(v);
  if (n.isFinite) return n.clamp(0, 100).toDouble();
  return fallback.clamp(0, 100);
}

/// نسبة الطبيب الفعالة لعملية (نقل resolveDoctorPct).
///
/// م180 — **نقطة الخنق المركزية للميزة**: مطفأة ⇒ صفر دائماً، فكل عملية
/// جديدة تُختم بلقطة `doctorPct: 0` — حصتها كلها للعيادة، وتبقى كذلك حتى
/// لو أُعيد التفعيل لاحقاً (معنى «تظهر من نفس اليوم»). السجلات القديمة لا
/// تتأثر: لقطاتها المجمّدة تُقرأ قبل هذه الدالة (effectiveDoctorPct
/// لقطةً-أولاً) — احتفاظٌ كامل بالقيم التاريخية.
double resolveDoctorPct(
  Map<String, Object?> config, {
  String? clinic,
  String? service,
  bool isPros = false,
}) {
  if (!ratesFeatureEnabled(config)) return 0;
  final rates = config['clinicRates'];
  if (rates is Map) {
    final clinics = rates['clinics'];
    if (clinics is Map && clinic != null) {
      final c = clinics[clinic];
      if (c is Map) {
        // حارس الغياب: في JS تعطي المفاتيح الغائبة NaN (undefined) فتسقط
        // للاحتياطي؛ في Dart تعطي null → jsNumber(null)=0 — لذا نتحقق من
        // الوجود صراحةً قبل التحويل.
        if (isPros) {
          final pv = c['prosthetics'];
          if (pv != null) {
            final p = jsNumber(pv);
            if (p.isFinite) return _clampPct(p);
          }
        } else if (service != null) {
          final t = c['treatments'];
          if (t is Map && t[service] != null) {
            final p = jsNumber(t[service]);
            if (p.isFinite) return _clampPct(p);
          }
        }
      }
    }
  }
  // توأم `app.config.doctorPct || 50` (سقوط بالحقيقية الجافاسكربتية).
  return _clampPct(jsOr(config['doctorPct'], 50), 50);
}

/// بناء لقطة مجمّدة لعملية جديدة من الإعدادات الحالية (نقل buildRateSnapshot).
Map<String, Object?> buildRateSnapshot(
  Map<String, Object?> config, {
  String? clinic,
  String? service,
  bool isPros = false,
  String? at,
}) {
  final doctorPct =
      resolveDoctorPct(config, clinic: clinic, service: service, isPros: isPros);
  return {
    'v': rateSnapshotVersion,
    'clinicId': clinic,
    'treatmentId': isPros ? '__prosthetics__' : service,
    'isPros': isPros,
    'doctorPct': doctorPct,
    'clinicPct': _clampPct(100 - doctorPct),
    'at': at ?? jsIsoNow(),
  };
}

/// هل تحمل العملية لقطة صالحة؟ (نقل hasRateSnapshot)
bool hasRateSnapshot(Map<String, Object?>? entity) {
  final s = entity?['_rateSnapshot'];
  return s is Map && s['v'] != null;
}
