/// منطق المختبرات — نقل حرفي لحسابات LabsTab.vue:
/// حالة الحالة المالية من الدين المرتبط (prostheticId): «محصّل» عندما يكون
/// الدين مسدداً أو المتبقي ≤ 0 أو labPaid ≥ labValue (وتاريخها آخر دفعة
/// isDebtPayment لذلك الدين)، وإلا «دين»؛ التركيبة غير الدين «محصّل» بتاريخها.
/// الترتيب: العيادة أولاً ثم التاريخ (أقدم/أحدث)، والمجاميع: وحدات
/// (prosUnits||1) وإجمالي وقيم محصّلة وديون وصافٍ = محصّل − ديون.
library;

import '../../core/utils/js_compat.dart';

typedef JMap = Map<String, Object?>;

class LabCase {
  const LabCase(this.row, this.financialStatus, this.statusDate);

  final JMap row;
  final String financialStatus;
  final String statusDate;
}

/// عدد حالات مختبر — labCasesCount.
int labCasesCount(List<JMap> prosthetics, String lab) =>
    prosthetics.where((p) => p['labName'] == lab).length;

/// حالات مختبر بالحالة المالية والترتيب — labCases computed حرفياً.
List<LabCase> labCases(
  String lab, {
  required List<JMap> prosthetics,
  required List<JMap> debts,
  required List<JMap> records,
  String sortOrder = 'oldest',
}) {
  final cases = <LabCase>[];
  for (final p in prosthetics.where((p) => p['labName'] == lab)) {
    JMap? debt;
    for (final d in debts) {
      if (d['prostheticId'] == p['id']) {
        debt = d;
        break;
      }
    }
    var financialStatus = 'محصّل';
    var statusDate = '${jsOr(p['date'], '')}';
    if (jsTruthy(p['isDebt']) || debt != null) {
      final d = debt;
      final labVal = jsNumOr0(p['labValue']);
      final labPaid = d != null ? jsNumOr0(d['labPaid']) : 0;
      if (d != null &&
          (d['status'] == 'paid' ||
              jsNumOr0(d['remaining']) <= 0 ||
              labPaid >= labVal)) {
        financialStatus = 'محصّل';
        final pays = [
          for (final r in records)
            if (jsTruthy(r['isDebtPayment']) && r['debtId'] == d['id']) r,
        ]..sort((a, b) =>
            '${jsOr(b['date'], '')}'.compareTo('${jsOr(a['date'], '')}'));
        statusDate = '${jsOr(pays.isNotEmpty ? pays.first['date'] : null, jsOr(d['date'], jsOr(p['date'], '')))}';
      } else {
        financialStatus = 'دين';
        statusDate = '${jsOr(d?['date'], jsOr(p['date'], ''))}';
      }
    }
    cases.add(LabCase(p, financialStatus, statusDate));
  }

  cases.sort((a, b) {
    final cCompare = '${jsOr(a.row['clinic'], '')}'
        .compareTo('${jsOr(b.row['clinic'], '')}');
    if (cCompare != 0) return cCompare;
    final dateA = '${jsOr(a.row['date'], '')}';
    final dateB = '${jsOr(b.row['date'], '')}';
    return sortOrder == 'oldest'
        ? dateA.compareTo(dateB)
        : dateB.compareTo(dateA);
  });
  return cases;
}

// ── م161 — إعادة تصميم قسم المختبر: قيمٌ شهرية وصفوف جدول موحّدة ─────────────

/// صفٌّ في جدول المختبر (م161): حالة تركيبٍ لهذا المختبر في الشهر المختار.
/// [value] = قيمة المختبر (labValue) — ما يستحقه المعمل (قرار المالك).
class LabRow {
  const LabRow({
    required this.id,
    required this.date,
    required this.name,
    required this.clinic,
    required this.prosType,
    required this.units,
    required this.value,
  });

  /// معرّف التركيبة — لفتح تفاصيل الحالة من الصف (سطح المكتب).
  final String id;
  final String date;
  final String name;
  final String clinic;
  final String prosType;
  final num units;
  final num value;
}

/// صفوف مختبرٍ في شهرٍ مختار — مرتبةً بالأحدث أولاً دائماً (جدول/طباعة).
/// [month] بصيغة YYYY-MM؛ فارغ = كل الشهور.
List<LabRow> labMonthRows(
  String lab, {
  required List<JMap> prosthetics,
  String month = '',
}) {
  final rows = <LabRow>[
    for (final p in prosthetics)
      if (p['labName'] == lab &&
          (month.isEmpty || '${jsOr(p['date'], '')}'.startsWith(month)))
        LabRow(
          id: '${jsOr(p['id'], '')}',
          date: '${jsOr(p['date'], '')}',
          name: '${jsOr(p['name'], '')}',
          clinic: '${jsOr(p['clinic'], jsOr(p['clinic_id'], ''))}',
          prosType: '${jsOr(p['prosType'], 'تركيبات')}',
          units: _unitsOf(p['prosUnits']),
          value: jsNumOr0(p['labValue']),
        ),
  ];
  rows.sort((a, b) => b.date.compareTo(a.date));
  return rows;
}

/// قيمة المختبر الكلية في شهرٍ مختار (مجموع labValue لحالاته).
num labMonthValue(
  String lab, {
  required List<JMap> prosthetics,
  String month = '',
}) =>
    labMonthRows(lab, prosthetics: prosthetics, month: month)
        .fold<num>(0, (s, r) => s + r.value);

/// بطاقة مختبرٍ في القائمة (م161): الاسم وقيمة الشهر وعدد حالاته.
class LabCard {
  const LabCard(this.name, this.monthValue, this.count);
  final String name;
  final num monthValue;
  final int count;
}

/// بطاقات كل المختبرات لشهرٍ مختار — مرتبةً أبجدياً باسم المختبر.
List<LabCard> labCards(
  List<String> labs, {
  required List<JMap> prosthetics,
  String month = '',
}) {
  final out = [
    for (final lab in labs)
      LabCard(
        lab,
        labMonthValue(lab, prosthetics: prosthetics, month: month),
        labMonthRows(lab, prosthetics: prosthetics, month: month).length,
      ),
  ];
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

/// تجميع صفوف مختبرٍ بالعيادة — لخيار طباعة «كل عيادة على حدة».
Map<String, List<LabRow>> labRowsByClinic(List<LabRow> rows) {
  final map = <String, List<LabRow>>{};
  for (final r in rows) {
    (map[r.clinic.isEmpty ? '—' : r.clinic] ??= []).add(r);
  }
  return map;
}

num labTotalAll(List<LabCase> cases) =>
    cases.fold<num>(0, (s, c) => s + jsNumOr0(c.row['labValue']));

/// Number(prosUnits) || 1 — حرفياً (NaN أو 0 ⇒ 1).
num _unitsOf(Object? v) {
  final n = jsNumber(v);
  return (n.isNaN || n == 0) ? 1 : n;
}

num labTotalUnits(List<LabCase> cases) =>
    cases.fold<num>(0, (s, c) => s + _unitsOf(c.row['prosUnits']));

num labTotalCollected(List<LabCase> cases) => cases
    .where((c) => c.financialStatus == 'محصّل')
    .fold<num>(0, (s, c) => s + jsNumOr0(c.row['labValue']));

num labTotalDebt(List<LabCase> cases) => cases
    .where((c) => c.financialStatus == 'دين')
    .fold<num>(0, (s, c) => s + jsNumOr0(c.row['labValue']));
