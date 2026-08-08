/// حسابات الأرشيف الشهري — نقل حرفي لدوال utils/helpers.js وArchiveTab.vue:
/// استثناءات getMonthRecs (لا دين/تركيبة/دفعة/طريقة «دين»/دفعة تركيبة)،
/// دفعات الديون العادية تدخل كاش/تحويل الشهر، prosTotal = مجموع التركيبات
/// غير الدين + دفعات ديون التركيبات (إصلاح FIX الموثق في الأصل)، وحصة
/// طبيب التركيبات من pdDocAmt (_docAmount عند حضوره وإلا amount).
/// الترتيب byNewestFirst: مفتاح النشاط (_activityAt وإلا التاريخ) ثم المعرف.
library;

import '../../core/utils/js_compat.dart';

typedef JMap = Map<String, Object?>;

/// _activityKey — حرفياً: _activityAt المنتهي > 0، وإلا زمن التاريخ.
num activityKey(JMap? r) {
  final a = jsNumber(r?['_activityAt']);
  if (a.isFinite && a > 0) return a;
  final dateStr = '${r?['date'] ?? ''}';
  if (r?['date'] == null || dateStr.isEmpty) return 0;
  final d = DateTime.tryParse(dateStr);
  return d?.millisecondsSinceEpoch ?? 0;
}

/// byNewestFirst — الأحدث أولاً، وتعادل المفتاح يُحسم بالمعرف تنازلياً.
int byNewestFirst(JMap a, JMap b) {
  final ak = activityKey(a), bk = activityKey(b);
  if (ak != bk) return bk.compareTo(ak);
  final ai = '${a['id'] ?? ''}', bi = '${b['id'] ?? ''}';
  return ai.compareTo(bi) < 0 ? 1 : (ai.compareTo(bi) > 0 ? -1 : 0);
}

List<JMap> sortByNewest(List<JMap> arr) => [...arr]..sort(byNewestFirst);

/// م113 — قرار المالك: قوائم التاريخ تُرتَّب **بالتاريخ أولاً** (الأحدث
/// أعلى)، وعند تساوي اليوم بالأحدث نشاطاً (وقت التسجيل) ثم المعرف —
/// فسجلٌ مؤرَّخ غداً يعلو سجلات اليوم ولو سُجِّل قبلها (كان الترتيب
/// بمفتاح النشاط وحده فيخلط التواريخ).
num dateKeyOf(JMap? r) {
  final s = '${r?['date'] ?? ''}';
  if (s.isEmpty) return 0;
  final d = DateTime.tryParse(s);
  return d?.millisecondsSinceEpoch ?? 0;
}

int byDateNewestFirst(JMap a, JMap b) {
  final ad = dateKeyOf(a), bd = dateKeyOf(b);
  if (ad != bd) return bd.compareTo(ad);
  return byNewestFirst(a, b);
}

List<JMap> sortByDateNewest(List<JMap> arr) =>
    [...arr]..sort(byDateNewestFirst);

/// isProsDebtPay — دفعة دين تركيبة (دينها المرتبط type=prosthetic).
bool isProsDebtPay(JMap r, List<JMap> debts) {
  if (!jsTruthy(r['isDebtPayment']) || !jsTruthy(r['debtId'])) return false;
  for (final d in debts) {
    if (d['id'] == r['debtId']) return d['type'] == 'prosthetic';
  }
  return false;
}

/// pdDocAmt — _docAmount عند حضور المفتاح (كما في `!== undefined`) وإلا amount.
num pdDocAmt(JMap r) => r.containsKey('_docAmount')
    ? jsNumOr0(r['_docAmount'])
    : jsNumOr0(r['amount']);

num _sum(Iterable<JMap> arr, String key) =>
    arr.fold<num>(0, (s, item) => s + jsNumOr0(item[key]));

/// prosDocEarnings — كاش/تحويل حصة طبيب التركيبات (غير الدين) + دفعات ديونها.
({num pCash, num pXfer, num pDoc}) prosDocEarnings(
    List<JMap> cp, List<JMap> pdPays) {
  final nonDebt = [...cp.where((p) => !jsTruthy(p['isDebt']))];
  final pCash = _sum(nonDebt.where((p) => p['payment'] == 'كاش'),
          'doctorShare') +
      pdPays
          .where((r) => r['payment'] == 'كاش')
          .fold<num>(0, (s, r) => s + pdDocAmt(r));
  final pXfer = _sum(nonDebt.where((p) => p['payment'] != 'كاش'),
          'doctorShare') +
      pdPays
          .where((r) => r['payment'] != 'كاش')
          .fold<num>(0, (s, r) => s + pdDocAmt(r));
  return (pCash: pCash, pXfer: pXfer, pDoc: pCash + pXfer);
}

bool _inMonth(JMap r, String m) => '${r['date'] ?? ''}'.startsWith(m);

/// getMonthRecs — سجلات الشهر النقدية الصافية (كل الاستثناءات حرفياً).
/// نظام «التحاليل» — صفوف التحاليل (isAnalysis) معزولة مالياً بالكامل:
/// تُستبعد من أخطر حارسٍ (يغذي الأرباح + الأرشيف + الخزينة) فلا تدخل أي
/// إجمالي دخلٍ أبداً.
List<JMap> getMonthRecs(List<JMap> records, List<JMap> debts, String m) => [
      for (final r in records)
        if (_inMonth(r, m) &&
            !jsTruthy(r['isAnalysis']) &&
            !jsTruthy(r['isDebt']) &&
            !jsTruthy(r['isPros']) &&
            !jsTruthy(r['isDebtPayment']) &&
            r['payment'] != 'دين' &&
            !isProsDebtPay(r, debts))
          r,
    ];

/// getMonthRegDebtPays — دفعات الديون العادية.
List<JMap> getMonthRegDebtPays(
        List<JMap> records, List<JMap> debts, String m) =>
    [
      for (final r in records)
        if (_inMonth(r, m) &&
            jsTruthy(r['isDebtPayment']) &&
            !isProsDebtPay(r, debts))
          r,
    ];

List<JMap> getMonthPros(List<JMap> prosthetics, String m) =>
    [for (final p in prosthetics) if (_inMonth(p, m)) p];

/// getMonthPdPays — دفعات ديون التركيبات.
List<JMap> getMonthPdPays(List<JMap> records, List<JMap> debts, String m) => [
      for (final r in records)
        if (_inMonth(r, m) && isProsDebtPay(r, debts)) r,
    ];

class MonthData {
  const MonthData({
    required this.inMem,
    required this.cash,
    required this.xfer,
    required this.prosDoc,
    required this.prosTotal,
    required this.total,
  });

  final bool inMem;
  final num cash;
  final num xfer;
  final num prosDoc;
  final num prosTotal;
  final num total;
}

/// monthData — حرفياً (بما فيه إصلاح prosTotal الموثق في الأصل).
MonthData monthData(
  String m, {
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
}) {
  final mr = getMonthRecs(records, debts, m);
  final rdp = getMonthRegDebtPays(records, debts, m);
  final mp = getMonthPros(prosthetics, m);
  final pd = getMonthPdPays(records, debts, m);
  final inMem =
      mr.isNotEmpty || mp.isNotEmpty || pd.isNotEmpty || rdp.isNotEmpty;
  final cash = _sum(mr.where((r) => r['payment'] == 'كاش'), 'amount') +
      _sum(rdp.where((r) => r['payment'] == 'كاش'), 'amount');
  final xfer = _sum(mr.where((r) => r['payment'] != 'كاش'), 'amount') +
      _sum(rdp.where((r) => r['payment'] != 'كاش'), 'amount');
  final prosDoc = prosDocEarnings(mp, pd).pDoc;
  final prosTotal =
      _sum(mp.where((p) => !jsTruthy(p['isDebt'])), 'total') +
          _sum(pd, 'amount');
  return MonthData(
    inMem: inMem,
    cash: cash,
    xfer: xfer,
    prosDoc: prosDoc,
    prosTotal: prosTotal,
    total: cash + xfer + prosTotal,
  );
}

/// أشهر البيانات الموجودة تنازلياً — months computed (بدون getKnownMonths
/// السحابية؛ القاعدة المحلية هي مصدر الحقيقة الكامل هنا).
List<String> monthsOf(List<JMap> records, List<JMap> prosthetics) {
  final set = <String>{};
  for (final r in [...records, ...prosthetics]) {
    final d = '${r['date'] ?? ''}';
    if (d.length >= 7) set.add(d.substring(0, 7));
  }
  return set.toList()..sort((a, b) => b.compareTo(a));
}

/// سجلات تفصيل الشهر — detailRecords (نقدية + دفعات عادية + تركيبات غير
/// الدين + دفعات التركيبات) مرتبة بالأحدث.
List<JMap> detailRecords(
  String m, {
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
}) {
  final mr = getMonthRecs(records, debts, m);
  final rdp = getMonthRegDebtPays(records, debts, m);
  final mp = [
    for (final p in getMonthPros(prosthetics, m))
      if (!jsTruthy(p['isDebt'])) p,
  ];
  final pd = getMonthPdPays(records, debts, m);
  return sortByNewest([...mr, ...rdp, ...mp, ...pd]);
}
