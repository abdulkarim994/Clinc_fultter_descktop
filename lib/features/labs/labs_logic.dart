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
