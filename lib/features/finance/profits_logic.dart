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
// م188 — مصدرٌ واحدٌ لصفوف التحاليل: نفس دالة بطاقة السجل (منعُ تكرارٍ
// بالمعرّف ويومُ احتسابٍ incomeDate يتقدم على date) — فلا يختلف رقمان.
import 'analyses_filter.dart' show monthAnalysesRows;
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

/// م188 — إيراد التحاليل لمدةٍ ما: **إيرادٌ خاصٌّ بالعيادة** لا يُقسم مع
/// الطبيب (قرار المالك). قبل م188 كانت صفوف التحاليل مستثناةً من الأرباح
/// كلها نصّاً (شرط `isAnalysis` في [getMonthRecs] وفي [yearTotals]) —
/// فلم تكن تُقسَم خطأً، بل كانت **غائبةً تماماً**؛ وهذا البند يظهرها.
///
/// [period] بادئةُ تاريخ: `YYYY-MM` لشهرٍ أو `YYYY` لسنة (المطابقة
/// بالبادئة فيصحّ الاثنان بدالةٍ واحدة). القواعد مستعارةٌ حرفياً من
/// بطاقة السجل: صفٌّ واحدٌ لكل معرّف (المزامنة قد تُكرّر)، ويومُ
/// الاحتساب `incomeDate` إن وُجد وإلا `date`.
///
/// ⚠️ لا يُلمَس مرشِّح الإيراد ([getMonthRecs]) — فتبقى التحاليل خارج
/// قاعدة النِّسَب أبداً، ولا تتضاعف مع الإجمالي.
num analysesRevenue(List<JMap> records, {required String period}) =>
    _sum(monthAnalysesRows(records, month: period), 'amount');

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
  const ClinicProfitRow(this.name, this.revenue, this.doctor, this.clinicShare,
      [this.lab = 0]);

  final String name;
  final num revenue;
  final num doctor;
  final num clinicShare;

  /// م187 — قيمة المختبرات المخصومة قبل تقسيم النِّسَب. موضعٌ اختياري
  /// بقيمة صفر افتراضاً: **لقطات العيادات المحذوفة المجمّدة (م170) لا
  /// تحمل قيمة معمل**، فتبقى صفراً فيها ولا تنكسر مناديها القدامى.
  final num lab;
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
      // م187 — قيمة المختبرات تُمرَّر مع الصف: الإيراد يحويها والحصتان لا
      // (تُخصم قبل التقسيم) — فبها يصير الجدول متحقِّقاً من نفسه.
      rows.add(ClinicProfitRow(name, rep.grandTotal, rep.doctorTotal,
          rep.clinicTotal, rep.prosLabCost));
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

// ═══════════════════════════════════════════════════════════════════════
// م178 — التقرير السنوي الدقيق (منطق نقي جديد)
//
// القاعدة الذهبية: **السنة = مجموع أشهرها الاثني عشر حرفياً** عبر
// getMonthlyReport نفسها — فلا يمكن أن ينحرف السنوي عن الشهري أبداً
// (نفس ضمانة monthGrandFor للمخطط). أساس القبض م112 محفوظ تلقائياً.
//
// اللقطات المجمدة للعيادات المحذوفة (م170) والمصروفات تصل عبر دالتَي
// حقنٍ اختياريتين — فيبقى المنطق نقياً قابلاً للاختبار بلا Riverpod.
// ═══════════════════════════════════════════════════════════════════════

/// صف شهرٍ واحد في جدول الأرباح والخسائر السنوي.
class MonthProfitRow {
  const MonthProfitRow({
    required this.month,
    required this.idx,
    required this.revenue,
    required this.doctor,
    required this.clinic,
    required this.expenses,
    this.lab = 0,
    this.analyses = 0,
  });

  /// YYYY-MM.
  final String month;

  /// 0..11 (فهرس [arMonths]).
  final int idx;

  final num revenue;
  final num doctor;
  final num clinic;
  final num expenses;

  /// م187 — قيمة المختبرات المخصومة قبل تقسيم النِّسَب.
  final num lab;

  /// م187 — الإيراد بعد خصم المختبرات: **يساوي حتماً** حصة الطبيب +
  /// حصة العيادة (لأن الحصص تُقسم على الصافي بعد المعمل) — فبه يصير
  /// الجدول متحقِّقاً من نفسه بنظرة.
  num get afterLab => revenue - lab;

  /// م188 — إيراد التحاليل الثلاثية للشهر: **يضاف** لصافي العيادة ولا
  /// يمسّ [revenue] ولا [doctor] (خاصٌّ بالعيادة — قرار المالك).
  final num analyses;

  /// صافي ربح العيادة للشهر = حصة العيادة − مصروفاته **+ تحاليله** (م188).
  num get net => clinic - expenses + analyses;

  /// م188 — صافي الشهر حين النِّسَب **مطفأة**: لا حصص، فالكل للعيادة —
  /// الإيراد ناقص المعمل والمصروفات زائد التحاليل. تعبيرٌ واحدٌ ينادونه
  /// كلهم (جدول + مؤشرات) فيستحيل أن يعرض رقمان متخالفان.
  num get netOff => revenue - lab - expenses + analyses;

  bool get isEmpty =>
      revenue == 0 &&
      doctor == 0 &&
      clinic == 0 &&
      expenses == 0 &&
      // م188 — شهرٌ لا فيه إلا تحاليل ليس فارغاً؛ لولا هذا لبقي باهتاً
      // وصافيه ظاهرٌ فيه رقم — تناقضٌ أمام العين.
      analyses == 0;
}

/// التقرير السنوي: إجماليات السنة + تفصيل أشهرها الاثني عشر.
class YearReport {
  const YearReport({
    required this.year,
    required this.revenue,
    required this.doctor,
    required this.clinic,
    required this.expenses,
    required this.months,
    this.lab = 0,
    this.analyses = 0,
  });

  final String year;

  /// إجمالي الإيراد (أساس القبض م112) = مجموع إيرادات الأشهر.
  final num revenue;

  /// إجمالي ربح الطبيب (سجلات + تركيبات).
  final num doctor;

  /// إجمالي ربح العيادة قبل المصروفات.
  final num clinic;

  /// مصروفات السنة كاملة.
  final num expenses;

  /// م187 — قيمة مختبرات السنة (مجموع أشهرها).
  final num lab;

  /// م187 — إيراد السنة بعد خصم المختبرات (= الطبيب + العيادة).
  num get afterLab => revenue - lab;

  /// م188 — إيراد تحاليل السنة (مجموع أشهرها) — خاصٌّ بالعيادة.
  final num analyses;

  /// الأشهر الاثنا عشر بالترتيب (يناير..ديسمبر).
  final List<MonthProfitRow> months;

  /// صافي ربح العيادة السنوي = حصة العيادة − المصروفات **+ التحاليل** (م188).
  num get net => clinic - expenses + analyses;

  /// م188 — صافي السنة حين النِّسَب مطفأة (نظير [MonthProfitRow.netOff]).
  num get netOff => revenue - lab - expenses + analyses;

  /// هامش الصافي % من الإيراد (0 عند غياب الإيراد).
  num get marginPct => revenue == 0 ? 0 : net / revenue * 100;
}

/// م178 — التقرير السنوي: 12 استدعاءً لـ getMonthlyReport (تطابقاً حرفياً
/// مع الشهري) + اللقطات المجمدة والمصروفات المحقونتين. تراكم بالقروش
/// الصحيحة (عقد م85) فلا انجراف عبر الأشهر.
YearReport yearReport(
  String year, {
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
  required num doctorPct,
  num Function(String month)? expensesOf,
  List<ClinicProfitRow> Function(String month)? frozenRowsOf,
}) {
  final months = <MonthProfitRow>[];
  var revC = 0, docC = 0, clinC = 0, expC = 0, labC = 0, anaC = 0;
  for (var i = 0; i < 12; i++) {
    final m = '$year-${'${i + 1}'.padLeft(2, '0')}';
    final rep = getMonthlyReport(records, prosthetics, debts, m, doctorPct);
    var mRevC = toCents(rep.grandTotal);
    var mDocC = toCents(rep.doctorTotal);
    var mClinC = toCents(rep.clinicTotal);
    // م187 — مختبرات الشهر (اللقطات المجمّدة بلا قيمة معمل فلا تزيدها).
    final mLabC = toCents(rep.prosLabCost);
    // م170 — لقطات العيادات المحذوفة تدخل شهرها التاريخي كما في الشهري.
    for (final f in frozenRowsOf?.call(m) ?? const <ClinicProfitRow>[]) {
      mRevC += toCents(f.revenue);
      mDocC += toCents(f.doctor);
      mClinC += toCents(f.clinicShare);
    }
    final mExpC = toCents(expensesOf?.call(m) ?? 0);
    // م188 — تحاليل الشهر تُحسب هنا من الصفوف الخام نفسها (لا معامل من
    // المنادي) فيستحيل أن يختلف السنوي عن الشهري.
    final mAnaC = toCents(analysesRevenue(records, period: m));
    months.add(MonthProfitRow(
      month: m,
      idx: i,
      revenue: fromCents(mRevC),
      doctor: fromCents(mDocC),
      clinic: fromCents(mClinC),
      expenses: fromCents(mExpC),
      lab: fromCents(mLabC),
      analyses: fromCents(mAnaC),
    ));
    revC += mRevC;
    docC += mDocC;
    clinC += mClinC;
    expC += mExpC;
    labC += mLabC;
    anaC += mAnaC;
  }
  return YearReport(
    year: year,
    revenue: fromCents(revC),
    doctor: fromCents(docC),
    clinic: fromCents(clinC),
    expenses: fromCents(expC),
    lab: fromCents(labC),
    analyses: fromCents(anaC),
    months: months,
  );
}

/// م178 — أرباح العيادات سنوياً: تجميع صفوف monthlyClinicRows (واللقطات
/// المجمدة 🔒) عبر أشهر السنة بالاسم — فكل عيادة ترى إيرادها وحصتَيها
/// عن السنة كاملة. الترتيب بالإيراد تنازلياً كالشهري.
List<ClinicProfitRow> yearlyClinicRows(
  String year, {
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
  required List<String> clinics,
  required num doctorPct,
  List<ClinicProfitRow> Function(String month)? frozenRowsOf,
}) {
  // تراكم بالقروش لكل اسم: [إيراد، طبيب، عيادة].
  final acc = <String, List<int>>{};
  void add(String name, num rev, num doc, num clin, [num lab = 0]) {
    final a = acc.putIfAbsent(name, () => [0, 0, 0, 0]);
    a[0] += toCents(rev);
    a[1] += toCents(doc);
    a[2] += toCents(clin);
    a[3] += toCents(lab);
  }

  for (var i = 0; i < 12; i++) {
    final m = '$year-${'${i + 1}'.padLeft(2, '0')}';
    for (final r in monthlyClinicRows(m,
        records: records,
        prosthetics: prosthetics,
        debts: debts,
        clinics: clinics,
        doctorPct: doctorPct)) {
      add(r.name, r.revenue, r.doctor, r.clinicShare, r.lab);
    }
    for (final f in frozenRowsOf?.call(m) ?? const <ClinicProfitRow>[]) {
      // م187 — اللقطات المجمّدة بلا قيمة معمل (f.lab = 0 حتماً).
      add(f.name, f.revenue, f.doctor, f.clinicShare, f.lab);
    }
  }
  final rows = [
    for (final e in acc.entries)
      if (e.value.any((c) => c != 0))
        ClinicProfitRow(e.key, fromCents(e.value[0]), fromCents(e.value[1]),
            fromCents(e.value[2]), fromCents(e.value[3])),
  ]..sort((a, b) => b.revenue.compareTo(a.revenue));
  return rows;
}

/// م178 — نسبة التغير السنوي (YoY) بالمئة، أو null حين لا أساس مقارنة
/// (السنة السابقة صفر أو سالبة فلا معنى للنسبة).
num? yoyPct(num current, num previous) =>
    previous <= 0 ? null : (current - previous) / previous * 100;
