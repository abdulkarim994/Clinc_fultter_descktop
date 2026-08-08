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

double _clampPct(Object? v, [double fallback = 50]) {
  final n = jsNumber(v);
  if (n.isFinite) return n.clamp(0, 100).toDouble();
  return fallback.clamp(0, 100);
}

/// نسبة الطبيب الفعالة لعملية (نقل resolveDoctorPct).
double resolveDoctorPct(
  Map<String, Object?> config, {
  String? clinic,
  String? service,
  bool isPros = false,
}) {
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
