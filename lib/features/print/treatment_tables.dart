/// جداول المعالجات للطباعة — نقل حرفي لحسابات utils/print-tables.js
/// (buildTreatmentTables) + توأمي helpers: effectiveDoctorPct (اللقطة
/// المجمّدة أولاً ثم النسبة الحية للسجلات القديمة فقط) وformatNumber
/// (فواصل الآلاف حتى خانتين عشريتين). البناء هنا **بنيوي** (مجموعات وصفوف
/// وأرقام) — والعرض HTML/PDF شأن قالب الطباعة؛ الأرقام هي العقد المختبَر.
library;

import '../../core/display_prefs.dart' show appDigits;
import '../../core/utils/js_compat.dart';

typedef JMap = Map<String, Object?>;

/// formatNumber — toLocaleString('en-US') بحد أقصى خانتين عشريتين.
String formatNumber(Object? v) {
  final n = jsNumber(v);
  if (v == null || n.isNaN) return '0';
  final neg = n < 0;
  final abs = n.abs();
  // حتى خانتين عشريتين بلا أصفار زائدة.
  var s = abs.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  final parts = s.split('.');
  final intDigits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intDigits.length; i++) {
    if (i > 0 && (intDigits.length - i) % 3 == 0) buf.write(',');
    buf.write(intDigits[i]);
  }
  final out = parts.length > 1 ? '$buf.${parts[1]}' : '$buf';
  // م116 — نظام الأرقام (غربي/هندي) من الإعدادات عبر المحول المركزي.
  return appDigits(neg ? '-$out' : out);
}

/// effectiveDoctorPct — اللقطة المجمّدة `_rateSnapshot` أولاً (Phase 4)،
/// والنسبة الحية للسجلات السابقة للقطات فقط.
num effectiveDoctorPct(JMap? entity, [num fallbackPct = 50]) {
  final s = entity?['_rateSnapshot'];
  if (s is Map) {
    final snap = jsNumber(s['doctorPct']);
    if (snap.isFinite) return snap.clamp(0, 100);
  }
  final f = jsNumber(fallbackPct);
  return f.isFinite ? f.clamp(0, 100) : 50;
}

num _rnd(Object? x) => (jsNumOr0(x) * 100).round() / 100;

class TreatmentRow {
  const TreatmentRow({
    required this.name,
    required this.date,
    required this.amount,
    required this.doctor,
    required this.clinic,
    required this.payment,
  });

  final String name;
  final String date;
  final num amount;
  final num doctor;
  final num clinic;
  final String payment;
}

class TreatmentGroup {
  const TreatmentGroup({
    required this.service,
    required this.effPct,
    required this.zeroPct,
    required this.rows,
    required this.revenue,
    required this.doctor,
    required this.clinic,
  });

  final String service;
  final int effPct;

  /// نسبة المعالجة 0٪ ⇒ تُخفى أعمدة الأرباح وتُعرض الإيرادات فقط.
  final bool zeroPct;
  final List<TreatmentRow> rows;
  final num revenue;
  final num doctor;
  final num clinic;
}

class TreatmentTables {
  const TreatmentTables({
    required this.groups,
    required this.revenue,
    required this.doctor,
    required this.clinic,
  });

  final List<TreatmentGroup> groups;
  final num revenue;
  final num doctor;
  final num clinic;
}

/// buildTreatmentTables — التجميع بالمعالجة، الترتيب بالتاريخ صعوداً داخل
/// المجموعة، الحصص من اللقطة لكل عملية، والنسبة المعروضة هي **الفعلية**
/// (طبيب ÷ إيراد) لا العامة أبداً.
/// م108 — خدمةُ الأساس لصفِّ كشف: **الدفعات جزءٌ من معالجتها** (قرار
/// المالك) فلا تنعزل في جداول مستقلة. بادئتا «دفعة دين — X» و«دفعة
/// تركيبات — X» تُجرَّدان إلى X، والتسميات المجردة (دفعة أولى/دفعة دين
/// بلا اسم) تقرأ خدمة الأساس من لقطة النسب المجمّدة (treatmentId — وهي
/// تحمل خدمة المعالجة الأصلية منذ الإنشاء). التعذّر = التسمية كما هي.
String baseServiceOf(JMap r) {
  final svc = '${jsOr(r['service'], 'أخرى')}';
  const debtPrefix = 'دفعة دين — ';
  const prosPrefix = 'دفعة تركيبات — ';
  if (svc.startsWith(debtPrefix)) return svc.substring(debtPrefix.length);
  if (svc.startsWith(prosPrefix)) return svc.substring(prosPrefix.length);
  const bare = {
    'دفعة أولى (دين)', 'دفعة دين',
    'تركيبات (دفعة أولى)', 'تركيبات (دفعة دين)',
  };
  if (bare.contains(svc)) {
    final snap = r['_rateSnapshot'];
    if (snap is Map) {
      final base = '${snap['treatmentId'] ?? ''}'.trim();
      if (base.isNotEmpty && base != '__prosthetics__') return base;
    }
  }
  return svc;
}

TreatmentTables buildTreatmentTables(List<JMap> items,
    {num fallbackPct = 50}) {
  final groups = <String, List<JMap>>{};
  for (final r in items) {
    // م108 — التجميع بخدمة الأساس: دفعات الدين تهبط داخل جدول معالجتها.
    groups.putIfAbsent(baseServiceOf(r), () => []).add(r);
  }

  final outGroups = <TreatmentGroup>[];
  num gRev = 0, gDoc = 0, gClin = 0;
  for (final entry in groups.entries) {
    final sorted = [...entry.value]..sort(
        (a, b) => '${a['date'] ?? ''}'.compareTo('${b['date'] ?? ''}'));
    num rev = 0, doc = 0;
    final rows = <TreatmentRow>[];
    for (final r in sorted) {
      final amt = jsNumOr0(r['amount']);
      final pct = effectiveDoctorPct(r, fallbackPct);
      final rd = amt * pct / 100;
      rev += amt;
      doc += rd;
      rows.add(TreatmentRow(
        name: '${r['name'] ?? ''}',
        date: '${r['date'] ?? ''}',
        amount: _rnd(amt),
        doctor: _rnd(rd),
        clinic: _rnd(amt - rd),
        payment: '${r['payment'] ?? ''}',
      ));
    }
    final clin = rev - doc;
    gRev += rev;
    gDoc += doc;
    gClin += clin;
    final effPct = rev > 0 ? (doc / rev * 100).round() : 0;
    outGroups.add(TreatmentGroup(
      service: entry.key,
      effPct: effPct,
      zeroPct: _rnd(doc) == 0,
      rows: rows,
      revenue: _rnd(rev),
      doctor: _rnd(doc),
      clinic: _rnd(clin),
    ));
  }
  return TreatmentTables(
    groups: outGroups,
    revenue: _rnd(gRev),
    doctor: _rnd(gDoc),
    clinic: _rnd(gClin),
  );
}
