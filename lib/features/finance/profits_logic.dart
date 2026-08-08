/// منطق الأرباح — نقل حرفي لـ reports.service.getMonthlyReport وحسابات
/// ProfitsTab.vue السنوية:
///   • getMonthlyReport: استثناءات السجلات النقدية نفسها، كاش يشمل مرادفات
///     «نقد/نقدي»، حصة طبيب السجلات لقطةً-أولاً لكل سجل (recordDoctorShare)
///     ثم **تقريب المجموع لصحيح** (docRecords = round) وحصة العيادة
///     بالطرح، وحصص التركيبات من صفوفها المجمّدة + دفعات ديونها.
///   • صفوف أرباح الشهر بالعيادة (monthlyClinicRows) والإجمالي العام.
///   • السنة: كاش/تحويل، حصة طبيب التركيبات (كاش/تحويل)، الإجمالي، خريطة
///     مجاميع الأشهر (للتفاصيل الشهرية ومخطط آخر 6 أشهر).
library;

import '../../core/money.dart' show sumMoney, toCents, fromCents;
import '../../core/utils/js_compat.dart';
import '../archive/month_stats.dart'
    show getMonthPdPays, getMonthPros, getMonthRecs, getMonthRegDebtPays,
        isProsDebtPay, prosDocEarnings;
import '../print/treatment_tables.dart' show effectiveDoctorPct;
import 'treasury_logic.dart' show prosPayClin, prosPayLab, prosTotalPaid;

typedef JMap = Map<String, Object?>;

const arMonths = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

bool _isCash(Object? p) => p == 'كاش' || p == 'نقد' || p == 'نقدي';

// م85 — الجمع بالقروش الصحيحة: كان `fold` على `double` يراكم غبار التقريب
// عبر صفوف الشهر؛ و`sumMoney` يجمع القروش الصحيحة فلا ينجرف. السلوك مكافئ
// للقيم المضبوطة على القرش (وهي كلها بعد م85).
num _sum(Iterable<JMap> arr, String key) => sumMoney(arr, key);

/// recordDoctorShare — لقطة أولاً ثم النسبة الحية للقديم.
num recordDoctorShare(JMap r, num fallbackPct) =>
    jsNumOr0(r['amount']) * (effectiveDoctorPct(r, fallbackPct) / 100);

class MonthlyReport {
  const MonthlyReport({
    required this.recCount,
    required this.recCash,
    required this.recXfer,
    required this.recTotal,
    required this.recDoctor,
    required this.recClinic,
    required this.prosCount,
    required this.prosRevenue,
    required this.prosLabCost,
    required this.prosProfit,
    required this.prosDoctor,
    required this.prosClinic,
    required this.doctorTotal,
    required this.clinicTotal,
    required this.grandTotal,
  });

  final int recCount;
  final num recCash;
  final num recXfer;
  final num recTotal;
  final num recDoctor;
  final num recClinic;
  final int prosCount;
  final num prosRevenue;
  final num prosLabCost;
  final num prosProfit;
  final num prosDoctor;
  final num prosClinic;
  final num doctorTotal;
  final num clinicTotal;
  final num grandTotal;
}

/// getMonthlyReport حرفياً.
MonthlyReport getMonthlyReport(
  List<JMap> records,
  List<JMap> prosthetics,
  List<JMap> debts,
  String month,
  num doctorPct,
) {
  final monthRecs = getMonthRecs(records, debts, month);
  final monthDebtPays = getMonthRegDebtPays(records, debts, month);
  final monthPros = getMonthPros(prosthetics, month);
  final monthPdPays = getMonthPdPays(records, debts, month);

  final allRecs = [...monthRecs, ...monthDebtPays];
  final cash = _sum(allRecs.where((r) => _isCash(r['payment'])), 'amount');
  final xfer = _sum(allRecs.where((r) => !_isCash(r['payment'])), 'amount');
  final totalRecords = cash + xfer;

  final totalDocPros = prosDocEarnings(monthPros, monthPdPays).pDoc;

  // م112 — قرار المالك (2026-08-04): **الإيراد بأساس القبض حصراً** —
  // «الدين غير المدفوع قيمة وهمية لا تدخل الأرباح حتى تُدفع، ودفعة
  // الدين تُحسب في شهر قبضها». فالتركيبات تدخل بما قُبض فعلاً في
  // الشهر: غير الدَّينية بكاملها (تُدفع بشهرها) + دفعات ديون التركيبات
  // الواقعة في الشهر (ولو لديونِ شهورٍ سابقة) — وبهذا يطابق إجمالي
  // إيرادات الأرباح محصَّلَ الخزينة حرفياً. (كانت المعادلة استحقاقية:
  // كامل قيمة تركيبات الشهر بما فيها غير المسدد — بلاغ 19,320/23,120.)
  // م85 — تراكمٌ بالقروش الصحيحة ثم تحويلٌ للعرض. لا انجراف عبر الصفوف.
  var prosRevenueC = 0, labCostC = 0, clinicProsC = 0;
  for (final p in monthPros) {
    if (!jsTruthy(p['isDebt'])) {
      prosRevenueC += toCents(p['total']);
      labCostC += toCents(p['labValue']);
      // v35 — حصة العيادة بشهر الدفع مرآةً لحصة الطبيب.
      clinicProsC += toCents(p['clinicShare']);
    }
  }
  // دفعات ديون التركيبات الواقعة في الشهر: الإيراد بمبلغ الدفعة،
  // والمعمل والعيادة بحصتَي الدفعة (بنفس قاعدة الخزينة حرفياً).
  for (final r in monthPdPays) {
    prosRevenueC += toCents(jsOr(r['_fullAmount'], r['amount']));
    labCostC += toCents(prosPayLab(r, doctorPct));
    clinicProsC += toCents(prosPayClin(r, doctorPct));
  }
  final prosRevenue = fromCents(prosRevenueC);
  final labCost = fromCents(labCostC);
  final clinicPros = fromCents(clinicProsC);

  // حصة طبيب السجلات: تُجمع حصص الصفوف بالقروش، ثم — كالأصل حرفياً —
  // **تُقرَّب لأقرب دينار صحيح** (سلوك getMonthlyReport في Vue)، وحصةُ
  // العيادة بالطرح فيستحيل ألّا يطابق المجموعُ الإجماليَّ.
  var docRecordsRawC = 0;
  for (final r in allRecs) {
    docRecordsRawC += toCents(recordDoctorShare(r, doctorPct));
  }
  final docRecords = (docRecordsRawC / 100).round();
  final clinicRecords = totalRecords - docRecords;

  return MonthlyReport(
    recCount: monthRecs.length,
    recCash: cash,
    recXfer: xfer,
    recTotal: totalRecords,
    recDoctor: docRecords,
    recClinic: clinicRecords,
    prosCount: monthPros.length,
    prosRevenue: prosRevenue,
    prosLabCost: labCost,
    prosProfit: prosRevenue - labCost,
    prosDoctor: totalDocPros,
    prosClinic: clinicPros,
    doctorTotal: docRecords + totalDocPros,
    clinicTotal: clinicRecords + clinicPros,
    grandTotal: totalRecords + prosRevenue,
  );
}

class ClinicProfitRow {
  const ClinicProfitRow(this.name, this.revenue, this.doctor, this.clinicShare);

  final String name;
  final num revenue;
  final num doctor;
  final num clinicShare;
}

/// monthlyClinicRows — صف لكل عيادة لها أرقام، مرتبة بالإيراد تنازلياً.
List<ClinicProfitRow> monthlyClinicRows(
  String month, {
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
  required List<String> clinics,
  required num doctorPct,
}) {
  final recsM = [
    for (final r in records)
      if ('${r['date'] ?? ''}'.startsWith(month)) r,
  ];
  final prosM = [
    for (final p in prosthetics)
      if ('${p['date'] ?? ''}'.startsWith(month)) p,
  ];
  final names = <String>{
    ...clinics,
    ...recsM.map((r) => '${r['clinic'] ?? ''}'),
    ...prosM.map((p) => '${p['clinic'] ?? ''}'),
  }..remove('');
  final rows = <ClinicProfitRow>[];
  for (final name in names) {
    final rep = getMonthlyReport(
      [...recsM.where((r) => r['clinic'] == name)],
      [...prosM.where((p) => p['clinic'] == name)],
      debts,
      month,
      doctorPct,
    );
    if (rep.grandTotal != 0 || rep.doctorTotal != 0 || rep.clinicTotal != 0) {
      rows.add(ClinicProfitRow(
          name, rep.grandTotal, rep.doctorTotal, rep.clinicTotal));
    }
  }
  rows.sort((a, b) => b.revenue.compareTo(a.revenue));
  return rows;
}

class YearTotals {
  const YearTotals({
    required this.cash,
    required this.xfer,
    required this.prosDoc,
    required this.prosCash,
    required this.prosXfer,
    required this.prosPaid,
  });

  final num cash;
  final num xfer;
  final num prosDoc;
  final num prosCash;
  final num prosXfer;

  /// م112 — مقبوض التركيبات كاملاً (لا حصة الطبيب) لإجمالي القبض.
  final num prosPaid;

  num get grand => cash + xfer + prosPaid;
}

/// إجماليات السنة — yearCash/yearXfer/prosDocEarnings.
YearTotals yearTotals(
  String year, {
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
}) {
  final yrRecs = [
    for (final r in records)
      // نظام «التحاليل» — معزولة عن إجمالي السنة (لا تدخل الأرباح).
      if ('${r['date'] ?? ''}'.startsWith(year) &&
          !jsTruthy(r['isAnalysis']) &&
          !jsTruthy(r['isDebt']) &&
          !jsTruthy(r['isPros']) &&
          !jsTruthy(r['isDebtPayment']) &&
          r['payment'] != 'دين' &&
          !isProsDebtPay(r, debts))
        r,
  ];
  final yrPros = [
    for (final p in prosthetics)
      if ('${p['date'] ?? ''}'.startsWith(year)) p,
  ];
  final yrPd = [
    for (final r in records)
      if ('${r['date'] ?? ''}'.startsWith(year) && isProsDebtPay(r, debts)) r,
  ];
  final yrRdp = [
    for (final r in records)
      if ('${r['date'] ?? ''}'.startsWith(year) &&
          jsTruthy(r['isDebtPayment']) &&
          !isProsDebtPay(r, debts))
        r,
  ];
  final cash = _sum(yrRecs.where((r) => r['payment'] == 'كاش'), 'amount') +
      _sum(yrRdp.where((r) => r['payment'] == 'كاش'), 'amount');
  final xfer = _sum(yrRecs.where((r) => r['payment'] != 'كاش'), 'amount') +
      _sum(yrRdp.where((r) => r['payment'] != 'كاش'), 'amount');
  final earn = prosDocEarnings(yrPros, yrPd);
  return YearTotals(
    cash: cash,
    xfer: xfer,
    prosDoc: earn.pDoc,
    prosCash: earn.pCash,
    prosXfer: earn.pXfer,
    // م112 — أساس القبض: غير الدَّينية بكاملها + دفعات ديون التركيبات.
    prosPaid: prosTotalPaid(yrPros, yrPd),
  );
}

/// مجموع شهرٍ للمخطط/التفاصيل — م112: كاش + تحويل + مقبوض التركيبات
/// كاملاً (أساس القبض — كان بحصة طبيب التركيبات فقط).
num monthGrandFor(
  String month, {
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
}) {
  final recs = getMonthRecs(records, debts, month);
  final rdp = getMonthRegDebtPays(records, debts, month);
  final pros = getMonthPros(prosthetics, month);
  final pd = getMonthPdPays(records, debts, month);
  final cash = _sum([...recs, ...rdp].where((r) => r['payment'] == 'كاش'),
      'amount');
  final xfer = _sum([...recs, ...rdp].where((r) => r['payment'] != 'كاش'),
      'amount');
  return cash + xfer + prosTotalPaid(pros, pd);
}

/// سنوات البيانات — كما في ProfitsTab (تشمل السنة الحالية دوماً).
List<String> profitYears(List<JMap> records, List<JMap> prosthetics) {
  final ys = <String>{
    for (final r in records)
      if ('${r['date'] ?? ''}'.length >= 4) '${r['date']}'.substring(0, 4),
    for (final p in prosthetics)
      if ('${p['date'] ?? ''}'.length >= 4) '${p['date']}'.substring(0, 4),
    '${DateTime.now().year}',
  };
  return ys.toList()..sort((a, b) => b.compareTo(a));
}
