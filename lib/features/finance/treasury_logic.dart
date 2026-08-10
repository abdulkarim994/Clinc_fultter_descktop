/// منطق الخزينة — نقل حرفي لحسابات TreasuryTab.vue:
/// شرائح الشهر (نقدية صافية/تركيبات/دفعات ديون التركيبات/دفعات الديون
/// العادية/ديون الشهر المفتوحة)، مجاميع كل عيادة (كاش/تحويل/مدفوع
/// التركيبات/ديونها)، حصص دفعة التركيبة الثلاث (مخبر/طبيب/عيادة —
/// prosPayLab/Doc/Clin بحقول _labAmount/_docAmount المجمّدة وإلا الاشتقاق
/// المتوافق مع الأرشيف)، تجميع التركيبات بالمريض ببطاقات قابلة للتوسّع،
/// الدفعات العابرة للشهور، والفلاتر (اسم/نطاق تاريخ) وأنماط الفرز الأربعة.
library;

import '../../core/money.dart' show sumMoney, toCents, fromCents;
import '../../core/utils/js_compat.dart';
import '../archive/month_stats.dart' show isProsDebtPay, sortByDateNewest;

typedef JMap = Map<String, Object?>;

const sortModes = ['date-desc', 'date-asc', 'name-asc', 'name-desc'];
const sortLabels = {
  'date-desc': 'التاريخ (الأحدث)',
  'date-asc': 'التاريخ (الأقدم)',
  'name-asc': 'الاسم (أ-ي)',
  'name-desc': 'الاسم (ي-أ)',
};

/// شرائح شهر الخزينة — moRecs/moPros/moPdPays/moRegDebtPays/moDebts.
class TreasurySlice {
  TreasurySlice(
    this.month, {
    required List<JMap> records,
    required List<JMap> prosthetics,
    required List<JMap> debts,
  })  : recs = [
          for (final r in records)
            // نظام «التحاليل» — صفوف التحاليل معزولة عن دخل الخزينة النقدي
            // (لا تدخل grand/كاش/تحويل)؛ قسمها المستقل [analyses] أدناه.
            if ('${r['date'] ?? ''}'.startsWith(month) &&
                !jsTruthy(r['isAnalysis']) &&
                !jsTruthy(r['isDebt']) &&
                !jsTruthy(r['isPros']) &&
                !jsTruthy(r['isDebtPayment']) &&
                r['payment'] != 'دين' &&
                !isProsDebtPay(r, debts))
              r,
        ],
        analyses = [
          // صفوف تحاليل الشهر (العزل المالي): مصدر قسم «التحاليل» وحده.
          for (final r in records)
            if ('${r['date'] ?? ''}'.startsWith(month) &&
                jsTruthy(r['isAnalysis']))
              r,
        ],
        pros = [
          for (final p in prosthetics)
            if ('${p['date'] ?? ''}'.startsWith(month)) p,
        ],
        pdPays = [
          for (final r in records)
            if ('${r['date'] ?? ''}'.startsWith(month) &&
                isProsDebtPay(r, debts))
              r,
        ],
        regDebtPays = [
          for (final r in records)
            if ('${r['date'] ?? ''}'.startsWith(month) &&
                jsTruthy(r['isDebtPayment']) &&
                !isProsDebtPay(r, debts))
              r,
        ],
        openDebts = [
          for (final d in debts)
            if ('${d['date'] ?? ''}'.startsWith(month) &&
                d['status'] != 'paid')
              d,
        ];

  final String month;
  final List<JMap> recs;

  /// نظام «التحاليل» — صفوف تحاليل الشهر (isAnalysis)، معزولة تماماً عن
  /// [recs] والمجاميع (grand). تُغذّي قسم «التحاليل» وحده.
  final List<JMap> analyses;
  final List<JMap> pros;
  final List<JMap> pdPays;
  final List<JMap> regDebtPays;
  final List<JMap> openDebts;
}

// م85 — الجمع بالقروش الصحيحة (انظر core/money.dart). لا انجراف تراكميّ.
num _sum(Iterable<JMap> arr, String key) => sumMoney(arr, key);

/// جمعُ قيمةٍ مشتقّة لكل صفّ بالقروش الصحيحة ثم إعادتها ديناراً.
num _sumBy(Iterable<JMap> arr, num Function(JMap) f) {
  var c = 0;
  for (final r in arr) {
    c += toCents(f(r));
  }
  return fromCents(c);
}

num clinicCash(TreasurySlice s, String cli) =>
    _sum(s.recs.where((r) => r['clinic'] == cli && r['payment'] == 'كاش'),
        'amount') +
    _sum(
        s.regDebtPays
            .where((r) => r['clinic'] == cli && r['payment'] == 'كاش'),
        'amount');

num clinicXfer(TreasurySlice s, String cli) =>
    _sum(s.recs.where((r) => r['clinic'] == cli && r['payment'] != 'كاش'),
        'amount') +
    _sum(
        s.regDebtPays
            .where((r) => r['clinic'] == cli && r['payment'] != 'كاش'),
        'amount');

/// حصة طبيب التركيبات لعيادة — prosDocEarnings.pDoc.
num clinicProsDoc(TreasurySlice s, String cli) {
  final cp = [...s.pros.where((p) => p['clinic'] == cli)];
  final pd = [...s.pdPays.where((r) => r['clinic'] == cli)];
  return _prosDocEarnings(cp, pd);
}

num _pdDocAmt(JMap r) => r.containsKey('_docAmount')
    ? jsNumOr0(r['_docAmount'])
    : jsNumOr0(r['amount']);

num _prosDocEarnings(List<JMap> cp, List<JMap> pd) {
  final nonDebt = cp.where((p) => !jsTruthy(p['isDebt']));
  return _sum(nonDebt, 'doctorShare') + _sumBy(pd, _pdDocAmt);
}

/// المدفوع فعلاً للتركيبات (عرض): غير الدين كاملة + دفعات ديونها.
num prosTotalPaid(List<JMap> cp, List<JMap> pdPays) {
  final nonDebtPaid =
      _sum(cp.where((p) => !jsTruthy(p['isDebt'])), 'total');
  final debtPaid =
      _sumBy(pdPays, (r) => jsNumOr0(jsOr(r['_fullAmount'], r['amount'])));
  return nonDebtPaid + debtPaid;
}

num clinicProsTotalPaid(TreasurySlice s, String cli) => prosTotalPaid(
      [...s.pros.where((p) => p['clinic'] == cli)],
      [...s.pdPays.where((r) => r['clinic'] == cli)],
    );

/// م156 — توزيع «المدفوع للتركيبات» على كاش/تحويل بنفس مقادير
/// [prosTotalPaid] حرفياً (غير الدين بكامل قيمتها + دفعات ديونها
/// بمبلغها الكامل) — فيبقى cash + xfer == prosTotalPaid دائماً.
/// حقل الطريقة موجود على الصفين (اصطلاح المستودع: كاش وإلا فتحويل).
({num cash, num xfer}) prosPaidByMethod(
    List<JMap> cp, List<JMap> pdPays) {
  bool isCash(JMap r) => '${r['payment'] ?? ''}'.trim() == 'كاش';
  num pdAmt(JMap r) => jsNumOr0(jsOr(r['_fullAmount'], r['amount']));
  final nonDebt = [...cp.where((p) => !jsTruthy(p['isDebt']))];
  final cash = _sum(nonDebt.where(isCash), 'total') +
      _sumBy(pdPays.where(isCash), pdAmt);
  final xfer = _sum(nonDebt.where((p) => !isCash(p)), 'total') +
      _sumBy(pdPays.where((r) => !isCash(r)), pdAmt);
  return (cash: cash, xfer: xfer);
}

List<JMap> clinicOpenDebts(TreasurySlice s, String cli) =>
    [...s.openDebts.where((d) => d['clinic'] == cli)];

num clinicDebtRemaining(TreasurySlice s, String cli) =>
    _sum(clinicOpenDebts(s, cli), 'remaining');

// ── نظام «التحاليل» — مجاميع الدخل المخبري المعزول ─────────────────────────

/// تحاليل عيادةٍ للشهر: الإجمالي وتوزيعه كاش/تحويل. معزولٌ عن grand
/// (لا يُجمَع مع دخل الخزينة إطلاقاً) — قرار العزل المالي المثبت.
({num total, num cash, num transfer}) clinicAnalyses(
    TreasurySlice s, String cli) {
  final rows = s.analyses.where((r) => r['clinic'] == cli);
  final cash = _sum(rows.where((r) => r['payment'] == 'كاش'), 'amount');
  final transfer = _sum(rows.where((r) => r['payment'] != 'كاش'), 'amount');
  return (total: cash + transfer, cash: cash, transfer: transfer);
}

/// إجمالي تحاليل الشهر كله (كل العيادات): الإجمالي وكاش/تحويل — منفصلٌ
/// عن grand بالبناء (يُعرض في سطرٍ مستقل بشريط الإجماليات).
({num total, num cash, num transfer}) analysesTotals(TreasurySlice s) {
  final cash = _sum(s.analyses.where((r) => r['payment'] == 'كاش'), 'amount');
  final transfer =
      _sum(s.analyses.where((r) => r['payment'] != 'كاش'), 'amount');
  return (total: cash + transfer, cash: cash, transfer: transfer);
}

/// الإجماليات العليا — totalCash/totalXfer/totalProsDoc/grandTotal/totalDebtRem.
({num cash, num xfer, num prosDoc, num prosPaid, num grand, num debtRem})
    treasuryTotals(TreasurySlice s) {
  final cash = _sum(s.recs.where((r) => r['payment'] == 'كاش'), 'amount') +
      _sum(s.regDebtPays.where((r) => r['payment'] == 'كاش'), 'amount');
  final xfer = _sum(s.recs.where((r) => r['payment'] != 'كاش'), 'amount') +
      _sum(s.regDebtPays.where((r) => r['payment'] != 'كاش'), 'amount');
  final prosDoc = _prosDocEarnings(s.pros, s.pdPays);
  final prosPaid = prosTotalPaid(s.pros, s.pdPays);
  final debtRem = _sum(s.openDebts, 'remaining');
  return (
    cash: cash,
    xfer: xfer,
    prosDoc: prosDoc,
    prosPaid: prosPaid,
    // م111 — قرار المالك (2026-08-03): «المحصّل» = كل المقبوض فعلاً
    // بالشهر = كاش + تحويل + **كامل المدفوع للتركيبات** — فيطابق صفَّ
    // الدخل المعروض فوقه حرفياً. المعادلة الموروثة (كاش + تحويل + حصة
    // الطبيب من التركيبات فقط) كانت خليطاً غير متسق: السجلات بكاملها
    // والتركيبات بحصة الطبيب وحدها، فلا يطابق الرقمُ شيئاً حوله
    // (بلاغ فرق 19,191/19,320 — الفرق 129 = كامل التركيبة − حصة طبيبها).
    grand: cash + xfer + prosPaid,
    debtRem: debtRem,
  );
}

// ── حصص دفعة التركيبة (prosPayLab/Doc/Clin حرفياً) ─────────────────────────

num prosPayLab(JMap r, num doctorPct) {
  if (r.containsKey('_labAmount')) return jsNumOr0(r['_labAmount']);
  final dp = doctorPct;
  final full = jsNumOr0(jsOr(r['_fullAmount'], r['amount']));
  final doc = jsNumOr0(r['_docAmount']);
  if (dp <= 0 || full <= 0 || doc <= 0) {
    return (full - doc * 100 / (dp == 0 ? 1 : dp)).clamp(0, double.infinity);
  }
  return (((full - (doc * 100 / dp)) * 100).round() / 100)
      .clamp(0, double.infinity);
}

num prosPayDoc(JMap r, num doctorPct) {
  if (r.containsKey('_docAmount')) return jsNumOr0(r['_docAmount']);
  final full = jsNumOr0(jsOr(r['_fullAmount'], r['amount']));
  final lab = prosPayLab(r, doctorPct);
  return ((full - lab) * doctorPct / 100 * 100).round() / 100;
}

/// حصة العيادة = ما تبقى من الدفعة بعد المخبر والطبيب — مستقلة عن النسبة
/// الحية بالبناء (توافق الأرشيف الموثق في الأصل).
num prosPayClin(JMap r, num doctorPct) {
  final full = jsNumOr0(jsOr(r['_fullAmount'], r['amount']));
  final lab = prosPayLab(r, doctorPct);
  final doc = prosPayDoc(r, doctorPct);
  return (((full - lab - doc) * 100).round() / 100).clamp(0, double.infinity);
}

// ── عناصر التفصيل والتجميع ──────────────────────────────────────────────────

/// عناصر فئة التفصيل لعيادة — detailItems.
List<JMap> detailItems(TreasurySlice s, String category, String cli) {
  final recs = [...s.recs.where((r) => r['clinic'] == cli)];
  final rdp = [...s.regDebtPays.where((r) => r['clinic'] == cli)];
  final pros = [...s.pros.where((p) => p['clinic'] == cli)];
  final pd = [...s.pdPays.where((r) => r['clinic'] == cli)];
  // نظام «التحاليل» — بنود تحاليل العيادة (معزولة عن باقي الفئات).
  if (category == 'anal') {
    return sortByDateNewest(
        [...s.analyses.where((r) => r['clinic'] == cli)]);
  }
  if (category == 'cash') {
    return sortByDateNewest([
      ...recs.where((r) => r['payment'] == 'كاش'),
      ...rdp.where((r) => r['payment'] == 'كاش'),
    ]);
  }
  if (category == 'xfer') {
    return sortByDateNewest([
      ...recs.where((r) => r['payment'] != 'كاش'),
      ...rdp.where((r) => r['payment'] != 'كاش'),
    ]);
  }
  return sortByDateNewest([
    ...pros.where((p) => !jsTruthy(p['isDebt'])),
    ...pd,
  ]);
}

class ProsGroup {
  ProsGroup(this.name);

  final String name;
  final List<JMap> items = [];
  num total = 0;
  num docTotal = 0;
  num clinTotal = 0;
  num labTotal = 0;
}

/// تجميع تركيبات العيادة بالمريض — prosGrouped حرفياً (التركيبة `_t=p`
/// بمجاميع صفّها إن لم تكن ديناً؛ الدفعة بحصصها الثلاث؛ الترتيب بأقدم
/// تاريخ داخل المجموعة تنازلياً بين المجموعات).
List<ProsGroup> prosGrouped(TreasurySlice s, String cli, num doctorPct) {
  final cp = [...s.pros.where((p) => p['clinic'] == cli)];
  final pd = [...s.pdPays.where((r) => r['clinic'] == cli)];
  final map = <String, ProsGroup>{};
  for (final p in cp) {
    final k = '${jsOr(p['name'], 'بدون اسم')}';
    final g = map.putIfAbsent(k, () => ProsGroup(k));
    g.items.add({...p, '_t': 'p'});
    g.total += jsNumOr0(p['total']);
    if (!jsTruthy(p['isDebt'])) {
      g.labTotal += jsNumOr0(p['labValue']);
      g.docTotal += jsNumOr0(p['doctorShare']);
      g.clinTotal += jsNumOr0(p['clinicShare']);
    }
  }
  for (final r in pd) {
    final k = '${jsOr(r['name'], 'بدون اسم')}';
    final g = map.putIfAbsent(k, () => ProsGroup(k));
    g.items.add(r);
    g.labTotal += prosPayLab(r, doctorPct);
    g.docTotal += prosPayDoc(r, doctorPct);
    g.clinTotal += prosPayClin(r, doctorPct);
  }
  String earliest(ProsGroup g) => g.items.fold<String>('', (d, r) {
        final rd = '${r['date'] ?? ''}';
        return (d.isEmpty || (rd.isNotEmpty && rd.compareTo(d) < 0)) ? rd : d;
      });
  final out = map.values.toList()
    ..sort((a, b) => earliest(b).compareTo(earliest(a)));
  return out;
}

/// الدفعات العابرة للشهور لمجموعة — getCrossMonthPayments: أقساط ديون
/// المجموعة الواقعة خارج شهر العرض.
List<JMap> crossMonthPayments(
    ProsGroup g, List<JMap> records, List<JMap> debts, String month) {
  final out = <JMap>[];
  for (final item in g.items) {
    if (item['_t'] != 'p') continue;
    JMap? debt;
    for (final d in debts) {
      if (d['prostheticId'] == item['id']) {
        debt = d;
        break;
      }
    }
    if (debt == null) continue;
    for (final r in records) {
      if (jsTruthy(r['isDebtPayment']) &&
          r['debtId'] == debt['id'] &&
          !'${r['date'] ?? ''}'.startsWith(month)) {
        out.add(r);
      }
    }
  }
  return out;
}

// ── الفلاتر والفرز ──────────────────────────────────────────────────────────

bool matchDate(String? d, String from, String to) {
  if (d == null || d.isEmpty) return true;
  if (from.isNotEmpty && d.compareTo(from) < 0) return false;
  if (to.isNotEmpty && d.compareTo(to) > 0) return false;
  return true;
}

bool matchName(String? name, String q) =>
    q.isEmpty || (name ?? '').contains(q);

List<JMap> applySorting(List<JMap> arr, String mode) {
  final sorted = [...arr];
  int byDate(JMap a, JMap b) =>
      '${a['date'] ?? ''}'.compareTo('${b['date'] ?? ''}');
  int byName(JMap a, JMap b) =>
      '${a['name'] ?? ''}'.compareTo('${b['name'] ?? ''}');
  switch (mode) {
    case 'date-desc':
      sorted.sort((a, b) => byDate(b, a));
    case 'date-asc':
      sorted.sort(byDate);
    case 'name-asc':
      sorted.sort(byName);
    case 'name-desc':
      sorted.sort((a, b) => byName(b, a));
  }
  return sorted;
}

/// عناصر التفصيل بعد الفلاتر والفرز — filteredDetailItems.
List<JMap> filteredDetailItems(
  TreasurySlice s,
  String category,
  String cli, {
  String name = '',
  String from = '',
  String to = '',
  String sort = 'date-desc',
}) =>
    applySorting(
      [
        for (final r in detailItems(s, category, cli))
          if (matchName('${r['name'] ?? ''}', name) &&
              matchDate(r['date'] as String?, from, to))
            r,
      ],
      sort,
    );

/// مجموع التفصيل — filteredDetailTotal (تركيبات: مجموع حصص الطبيب للمجموعات).
num filteredDetailTotal(List<JMap> items) =>
    items.fold<num>(0, (s, r) => s + jsNumOr0(jsOr(r['amount'], r['doctorShare'])));

// ── م13: ترقيم الدفعات وبنية الحالات (installments.js + TreasuryTab) ────────

/// أقساط الدين الحية (بلا شواهد الحذف) — activeInstallments.
List<JMap> activeInstallments(JMap? debt) => [
      for (final x in [...?(debt?['installments'] as List?)])
        if (x is Map && jsNumOr0(x['_deleted']) != 1)
          Map<String, Object?>.from(x),
    ];

num _toMs(Object? v) {
  final n = num.tryParse('$v');
  if (n != null && n > 0) return n;
  if (v is String && v.isNotEmpty) {
    final t = DateTime.tryParse(v)?.millisecondsSinceEpoch;
    if (t != null) return t;
  }
  return 0;
}

/// مفتاح زمني ثابت للقسط — createdAt ثم نشاط/تعديل سجل دفعته ثم تاريخه.
num _chronoKey(JMap inst, Map<String, JMap>? recById) {
  final created = _toMs(inst['createdAt']);
  if (created > 0) return created;
  final rec = recById?['${inst['recordId'] ?? ''}'];
  if (rec != null) {
    final act = _toMs(rec['_activityAt']);
    if (act > 0) return act;
    final mod = _toMs(rec['_mod']);
    if (mod > 0) return mod;
  }
  return _toMs(inst['date']);
}

/// الأقساط مرقمة كرونولوجياً بثبات — numberedInstallments حرفياً
/// (الحذف لا يعيد الترقيم؛ فهرس السجلات يُبنى فقط للأقساط القديمة
/// بلا createdAt).
List<JMap> numberedInstallments(JMap? debt, List<JMap> records) {
  final active = activeInstallments(debt);
  if (active.isEmpty) return const [];
  Map<String, JMap>? recById;
  if (records.isNotEmpty &&
      active.any((el) => _toMs(el['createdAt']) == 0)) {
    final needed = {
      for (final el in active)
        if (jsTruthy(el['recordId'])) '${el['recordId']}',
    };
    recById = {
      for (final r in records)
        if (needed.contains('${r['id']}')) '${r['id']}': r,
    };
  }
  final sorted = [...active]..sort((a, b) {
      final ak = _chronoKey(a, recById), bk = _chronoKey(b, recById);
      if (ak != bk) return ak.compareTo(bk);
      // كسر التعادل بالمعرّف — حتمية على كل الأجهزة (حرفية الأصل).
      return '${a['id'] ?? ''}'.compareTo('${b['id'] ?? ''}');
    });
  return [
    for (var i = 0; i < sorted.length; i++)
      {...sorted[i], 'seq': i + 1},
  ];
}

/// قائمة الدفعات **للعرض**: الأحدث أعلى القائمة مع احتفاظ كل دفعة
/// برقمها الكرونولوجي الثابت — installmentsForDisplay حرفياً.
List<JMap> installmentsForDisplay(JMap? debt, List<JMap> records) =>
    numberedInstallments(debt, records).reversed.toList();

/// رقم «دفعة N» لسجل دفعة — installmentSeqForRecord حرفياً.
int installmentSeqForRecord(JMap? debt, List<JMap> records, JMap record) {
  final list = numberedInstallments(debt, records);
  if (list.isEmpty) return 1;
  final rid = '${record['id'] ?? ''}';
  for (final x in list) {
    if ('${x['recordId'] ?? ''}' == rid || '${x['id'] ?? ''}' == rid) {
      return jsNumOr0(x['seq']).toInt();
    }
  }
  return list.length;
}

/// حالة تركيبة بدفعاتها — getCasesWithPayments حرفياً.
class ProsCase {
  const ProsCase({
    required this.pros,
    required this.payments,
    required this.paid,
    required this.remaining,
    this.debt,
  });

  final JMap pros;
  final List<JMap> payments; // كل دفعة تحمل _seq
  final num paid;
  final num remaining;
  final JMap? debt;
}

/// الحالات بالأحدث أولاً؛ دفعات كل حالة عبر دينها المرتبط برقمها الثابت
/// وبالأحدث أولاً؛ الكاش paid = الإجمالي وremaining = 0.
List<ProsCase> getCasesWithPayments(
    List<JMap> items, List<JMap> debts, List<JMap> records) {
  final cases =
      sortByDateNewest([...items.where((r) => r['_t'] == 'p')]);
  final pays = [...items.where((r) => r['_t'] != 'p')];
  return [
    for (final p in cases)
      () {
        JMap? debt;
        for (final d in debts) {
          if (d['prostheticId'] == p['id']) {
            debt = d;
            break;
          }
        }
        final casePays = debt != null
            ? sortByDateNewest([
                for (final r in pays)
                  if (r['debtId'] == debt['id'])
                    {
                      ...r,
                      '_seq':
                          installmentSeqForRecord(debt, records, r),
                    },
              ])
            : <JMap>[];
        final paid = debt != null
            ? jsNumOr0(debt['paidAmount'])
            : (jsTruthy(p['isDebt']) ? 0 : jsNumOr0(p['total']));
        final remaining =
            debt != null ? jsNumOr0(debt['remaining']) : 0;
        return ProsCase(
          pros: p,
          payments: casePays,
          paid: paid,
          remaining: remaining,
          debt: debt,
        );
      }(),
  ];
}
