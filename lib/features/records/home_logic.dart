/// منطق الشاشة الرئيسية — نقل حرفي من AddRecord.vue وhelpers.js:
///   • **todayPatients**: أسماء فريدة من سجلات وتركيبات اليوم.
///   • **todayIncome** (تعريف المالك م23): إجمالي المقبوض فعلياً اليوم =
///     مجموع مجاميع كشف todayIncomeByClinic نفسه — مصدر واحد للرأس
///     والكشف (روافد حصة الطبيب القديمة باقية أدناه لمستهلكيها الآخرين).
///   • **todayDebt**: مجموع متبقي الديون المسجلة اليوم.
///   • تفصيلات العدادات حسب العيادة (بدون عيادة للفارغ) بصفوف الأصل.
///   • **localNameSearch**: فهرس أسماء موحّد من السجلات + التركيبات +
///     الديون بعزل عيادة صارم وبحث ضبابي وحد 8 — أساس اقتراحات
///     «الهاتف أولاً» واختيار المريض.
library;

import '../../core/utils/js_compat.dart';
import '../appointments/appointments_logic.dart' show fuzzyMatch;


typedef JMap = Map<String, Object?>;

const kNoClinic = 'بدون عيادة';

/// م105 — قيمة «يوم احتساب» خاصة تعني: في السجلات والمالية فقط —
/// لا يظهر السجل/الدفعة في **أي** جدول دخل يومي (لا تطابق أي تاريخ).
const kNoIncomeDay = 'none';

num _sum(Iterable<JMap> arr, String key) =>
    arr.fold<num>(0, (s, r) => s + jsNumOr0(r[key]));

/// pdDocAmt — حصة الطبيب من دفعة دين تركيبات: _docAmount إن وُجد وإلا
/// كامل المبلغ (سلوك الصف القديم حرفياً).
num pdDocAmt(JMap r) => r.containsKey('_docAmount')
    ? jsNumOr0(r['_docAmount'])
    : jsNumOr0(r['amount']);

/// prosDocEarnings.pDoc — حصة الطبيب من التركيبات + دفعات ديونها.
num prosDocEarnings(List<JMap> cp, List<JMap> pdPays) {
  final nonDebt = cp.where((p) => !jsTruthy(p['isDebt']));
  return _sum(nonDebt, 'doctorShare') +
      pdPays.fold<num>(0, (s, r) => s + pdDocAmt(r));
}

/// مرضى اليوم — أسماء فريدة (سجلات + تركيبات).
int todayPatients(List<JMap> records, List<JMap> prosthetics) {
  final today = getCurrentDate();
  final names = <String>{
    for (final r in records)
      if (r['date'] == today && jsTruthy(r['name'])) '${r['name']}',
    for (final p in prosthetics)
      if (p['date'] == today && jsTruthy(p['name'])) '${p['name']}',
  };
  return names.length;
}

/// دخل اليوم — **تعريف المالك (م23، 2026-07-27): إجمالي المقبوض فعلياً
/// اليوم** = مجموع مجاميع كشف «دخل اليوم» نفسه (todayIncomeByClinic)
/// مصدراً واحداً، فيستحيل تناقض الرأس والكشف بعد اليوم.
///
/// انحراف مقصود عن الأصل: صيغة AddRecord.vue القديمة كانت تجمع نقديَّ
/// اليوم + «حصة الطبيب» من التركيبات ودفعات ديونها (pDoc/_docAmount) +
/// دفعات الديون — فأظهر الرأس 6,310 بينما كشفه 7,500 لليوم نفسه (لقطة
/// 2026-07-27): دفعتا تركيبات 500+1,200 دخلتا بحصة الطبيب 150+360 فقط.
/// قرار المالك الصريح: «الدخل هو الإجمالي المدفوع اليوم فقط». الصيغة
/// القديمة موثقة في m23 (توثيق سبب التناقض)، وروافد حصة الطبيب
/// (prosDocEarnings/pdDocAmt) باقية لمستهلكيها الآخرين. وسيط debts باقٍ
/// لثبات الواجهة (الكشف لا يحتاجه).
num todayIncome(
    List<JMap> records, List<JMap> prosthetics, List<JMap> debts) {
  num s = 0;
  for (final g in todayIncomeByClinic(records, prosthetics)) {
    s += g.total;
  }
  return s;
}

/// دين اليوم — مجموع متبقي الديون المسجّلة اليوم.
num todayDebt(List<JMap> debts) {
  final today = getCurrentDate();
  num s = 0;
  for (final d in debts) {
    if (d['date'] == today && jsNumOr0(d['remaining']) > 0) {
      s += jsNumOr0(d['remaining']);
    }
  }
  return s;
}

// ── تفصيلات العدادات حسب العيادة ────────────────────────────────────────────

class ClinicPatientsGroup {
  const ClinicPatientsGroup(this.clinic, this.patients);

  final String clinic;
  final List<({String name, List<String> services, int visits})> patients;
}

/// مرضى اليوم موزعين على العيادات — todayPatientsByClinic حرفياً
/// (سجلات + تركيبات، لا دفعات ديون؛ زيارات وخدمات فريدة لكل اسم).
List<ClinicPatientsGroup> todayPatientsByClinic(
    List<JMap> records, List<JMap> prosthetics) {
  final today = getCurrentDate();
  final recs = [
    for (final r in [...records, ...prosthetics])
      // نظام «التحاليل» — التحليل لا يُحسب زيارةً في عدّاد مرضى اليوم.
      if (r['date'] == today &&
          jsTruthy(r['name']) &&
          !jsTruthy(r['isAnalysis']) &&
          !jsTruthy(r['isDebtPayment']))
        r,
  ];
  final groups =
      <String, Map<String, ({Set<String> services, int visits})>>{};
  for (final r in recs) {
    final c = jsTruthy(r['clinic']) ? '${r['clinic']}' : kNoClinic;
    final pmap = groups[c] ??= {};
    final name = '${r['name']}';
    final prev = pmap[name];
    final services = prev?.services ?? <String>{};
    if (jsTruthy(r['service'])) services.add('${r['service']}');
    pmap[name] = (services: services, visits: (prev?.visits ?? 0) + 1);
  }
  return [
    for (final e in groups.entries)
      ClinicPatientsGroup(e.key, [
        for (final p in e.value.entries)
          (
            name: p.key,
            services: p.value.services.toList(),
            visits: p.value.visits,
          ),
      ]),
  ];
}

class ClinicIncomeGroup {
  const ClinicIncomeGroup(this.clinic, this.total, this.patients);

  final String clinic;
  final num total;
  final List<({String name, num amount, String payment, String service})>
      patients;
}

/// م98 — مجموعة «كشف الحساب» بمدى تاريخي: كصنف اليوم مع تاريخ كل صف
/// (يُعرض حين يتجاوز المدى يوماً واحداً).
class ClinicIncomeRangeGroup {
  const ClinicIncomeRangeGroup(this.clinic, this.total, this.patients);

  final String clinic;
  final num total;
  final List<
      ({
        String name,
        num amount,
        String payment,
        String service,
        String date,
      })> patients;
}

/// م98 — «كشف الحساب»: دخل مدى تاريخي `[from..to]` بنفس قواعد م23
/// حرفياً (المقبوض فعلاً: استبعاد أصل الدين غير المدفوع إلا الدفعات،
/// والموجب فقط؛ التركيبات بمبلغها)، مع فلترةٍ اختيارية بالعيادة وطريقة
/// الدفع، **والأحدث إنشاءً أولاً**.
///
///   • التواريخ نصوص `YYYY-MM-DD` — فالمقارنة المعجمية تكافئ الزمنية.
///   • `clinic`/`payment` فارغان أو null = الكل. فلتر العيادة يطابق
///     [kNoClinic] للصفوف بلا عيادة (كما يعرضها الكشف نفسه).
///   • الفرز على `createdAt` (يضبطه الحفظ لكل سجل) وعند غيابه `_mod` —
///     فأحدثُ ما أُضيف يتصدّر، وترتيبُ مجموعات العيادات يتبع أحدثَ صفٍّ
///     في كلٍّ منها.
List<ClinicIncomeRangeGroup> incomeByClinicRange(
  List<JMap> records,
  List<JMap> prosthetics, {
  required String from,
  required String to,
  String? clinic,
  String? payment,
}) {
  bool inRange(Object? d) {
    final s = '${d ?? ''}';
    return s.compareTo(from) >= 0 && s.compareTo(to) <= 0;
  }

  num sortKey(JMap r) => r.containsKey('createdAt')
      ? jsNumOr0(r['createdAt'])
      : jsNumOr0(r['_mod']);

  bool clinicMatch(JMap r) {
    if (clinic == null || clinic.isEmpty) return true;
    final c = jsTruthy(r['clinic']) ? '${r['clinic']}' : kNoClinic;
    return c == clinic;
  }

  bool payMatch(JMap r) =>
      payment == null ||
      payment.isEmpty ||
      '${r['payment'] ?? ''}' == payment;

  final recs = <JMap>[];
  for (final r in records) {
    // نظام «التحاليل» — معزولة عن كشف الدخل بالمدى (لا تُحسب دخلاً).
    if (jsTruthy(r['isAnalysis'])) continue;
    if (!inRange(r['date'])) continue;
    if (r['payment'] == 'دين' && !jsTruthy(r['isDebtPayment'])) continue;
    if (jsNumOr0(r['amount']) <= 0) continue;
    if (!clinicMatch(r) || !payMatch(r)) continue;
    recs.add(r);
  }
  for (final p in prosthetics) {
    if (!inRange(p['date'])) continue;
    if (jsNumOr0(p['amount']) <= 0) continue;
    if (!clinicMatch(p) || !payMatch(p)) continue;
    recs.add(p);
  }

  // م114 — الأحدث أولاً **بالتاريخ** ثم بالأحدث إنشاءً ضمن اليوم؛
  // وأولُ ظهورٍ لعيادةٍ يحدد موضع مجموعتها.
  recs.sort((a, b) {
    final c = '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}');
    return c != 0 ? c : sortKey(b).compareTo(sortKey(a));
  });

  final groups = <String,
      List<
          ({
        String name,
        num amount,
        String payment,
        String service,
        String date,
      })>>{};
  final totals = <String, num>{};
  for (final r in recs) {
    final c = jsTruthy(r['clinic']) ? '${r['clinic']}' : kNoClinic;
    final amt = jsNumOr0(r['amount']);
    totals[c] = (totals[c] ?? 0) + amt;
    (groups[c] ??= []).add((
      name: jsTruthy(r['name']) ? '${r['name']}' : '—',
      amount: amt,
      payment: '${r['payment'] ?? ''}',
      service: '${r['service'] ?? ''}',
      date: '${r['date'] ?? ''}',
    ));
  }
  return [
    for (final e in groups.entries)
      ClinicIncomeRangeGroup(e.key, totals[e.key] ?? 0, e.value),
  ];
}

/// دخل اليوم حسب العيادة — todayIncomeByClinic حرفياً:
/// مبالغ مستلمة فعلاً (استبعاد أصل الدين غير المدفوع payment=='دين'
/// إلا الدفعات) والمبالغ الموجبة فقط؛ التركيبات بمبلغ amount.
/// م99 — «الكشف المالي»: تعميمٌ أوسع من [incomeByClinicRange] لقسم
/// المالية — فلترةٌ **متعددة الاختيار** بالعيادات والفئات (طرق الدفع +
/// «تركيبات» + «دين») وبحثٌ بالاسم، مجموعاً حسب العيادة والأحدثُ أولاً،
/// بنفس قواعد م23 حرفياً.
///
///   • فئةُ الصف: التركيبات ⇒ «تركيبات»؛ ودفعةُ الدين (payment=='دين'
///     مع isDebtPayment) ⇒ «دين»؛ وإلا قيمة `payment` (كاش/تحويل/…).
///   • [clinics]/[categories] فارغتان أو null = الكل. [nameQuery] فارغ = الكل.
List<ClinicIncomeRangeGroup> financialStatement(
  List<JMap> records,
  List<JMap> prosthetics, {
  required String from,
  required String to,
  Set<String>? clinics,
  Set<String>? categories,
  String nameQuery = '',
}) {
  bool inRange(Object? d) {
    final s = '${d ?? ''}';
    return s.compareTo(from) >= 0 && s.compareTo(to) <= 0;
  }

  num sortKey(JMap r) => r.containsKey('createdAt')
      ? jsNumOr0(r['createdAt'])
      : jsNumOr0(r['_mod']);

  final q = nameQuery.trim();
  bool nameOk(JMap r) => q.isEmpty || '${r['name'] ?? ''}'.contains(q);

  bool clinicOk(String c) =>
      clinics == null || clinics.isEmpty || clinics.contains(c);
  bool catOk(String cat) =>
      categories == null || categories.isEmpty || categories.contains(cat);

  final tagged = <({JMap row, String clinic, String category, num key})>[];

  for (final r in records) {
    // نظام «التحاليل» — معزولة عن الكشف المالي (لا تدخل أي فئة دخل).
    if (jsTruthy(r['isAnalysis'])) continue;
    if (!inRange(r['date'])) continue;
    if (r['payment'] == 'دين' && !jsTruthy(r['isDebtPayment'])) continue;
    if (jsNumOr0(r['amount']) <= 0) continue;
    final cat = (r['payment'] == 'دين' && jsTruthy(r['isDebtPayment']))
        ? 'دين'
        : '${r['payment'] ?? ''}';
    final c = jsTruthy(r['clinic']) ? '${r['clinic']}' : kNoClinic;
    if (!clinicOk(c) || !catOk(cat) || !nameOk(r)) continue;
    tagged.add((row: r, clinic: c, category: cat, key: sortKey(r)));
  }
  for (final p in prosthetics) {
    if (!inRange(p['date'])) continue;
    if (jsNumOr0(p['amount']) <= 0) continue;
    const cat = 'تركيبات';
    final c = jsTruthy(p['clinic']) ? '${p['clinic']}' : kNoClinic;
    if (!clinicOk(c) || !catOk(cat) || !nameOk(p)) continue;
    tagged.add((row: p, clinic: c, category: cat, key: sortKey(p)));
  }

  // م114 — بالتاريخ أولاً ثم الأحدث إنشاءً ضمن اليوم.
  tagged.sort((a, b) {
    final c = '${b.row['date'] ?? ''}'.compareTo('${a.row['date'] ?? ''}');
    return c != 0 ? c : b.key.compareTo(a.key);
  });

  final groups = <String,
      List<
          ({
        String name,
        num amount,
        String payment,
        String service,
        String date,
      })>>{};
  final totals = <String, num>{};
  for (final t in tagged) {
    final r = t.row;
    final amt = jsNumOr0(r['amount']);
    totals[t.clinic] = (totals[t.clinic] ?? 0) + amt;
    (groups[t.clinic] ??= []).add((
      name: jsTruthy(r['name']) ? '${r['name']}' : '—',
      amount: amt,
      // الفئة المعروضة تحت الاسم (تركيبات/دين/كاش/…).
      payment: t.category,
      service: '${r['service'] ?? ''}',
      date: '${r['date'] ?? ''}',
    ));
  }
  return [
    for (final e in groups.entries)
      ClinicIncomeRangeGroup(e.key, totals[e.key] ?? 0, e.value),
  ];
}

/// م98 — صار غلافاً لليوم الحالي فوق [incomeByClinicRange]: مصدرٌ واحد
/// للقواعد (تعريف م23 محفوظ حرفياً)، والأحدثُ إضافةً أولاً هنا أيضاً.
List<ClinicIncomeGroup> todayIncomeByClinic(
    List<JMap> records, List<JMap> prosthetics) {
  final today = getCurrentDate();
  return [
    for (final g in incomeByClinicRange(records, prosthetics,
        from: today, to: today))
      ClinicIncomeGroup(g.clinic, g.total, [
        for (final p in g.patients)
          (
            name: p.name,
            amount: p.amount,
            payment: p.payment,
            service: p.service,
          ),
      ]),
  ];
}

class ClinicDebtGroup {
  const ClinicDebtGroup(this.clinic, this.total, this.patients);

  final String clinic;
  final num total;
  final List<
      ({
        String name,
        num remaining,
        num total,
        num paid,
        String service,
      })> patients;
}

/// ديون اليوم حسب العيادة — todayDebtByClinic حرفياً.
List<ClinicDebtGroup> todayDebtByClinic(List<JMap> debts) {
  final today = getCurrentDate();
  final groups = <String,
      List<
          ({
        String name,
        num remaining,
        num total,
        num paid,
        String service,
      })>>{};
  final totals = <String, num>{};
  for (final d in debts) {
    if (d['date'] != today) continue;
    final rem = jsNumOr0(d['remaining']);
    if (rem <= 0) continue;
    final c = jsTruthy(d['clinic']) ? '${d['clinic']}' : kNoClinic;
    totals[c] = (totals[c] ?? 0) + rem;
    (groups[c] ??= []).add((
      name: jsTruthy(d['name']) ? '${d['name']}' : '—',
      remaining: rem,
      total: jsNumOr0(jsOr(d['totalAmount'], d['total'])),
      paid: jsNumOr0(d['paidAmount']),
      service: '${d['service'] ?? ''}',
    ));
  }
  return [
    for (final e in groups.entries)
      ClinicDebtGroup(e.key, totals[e.key] ?? 0, e.value),
  ];
}

// ── اقتراحات المرضى (localNameSearch حرفياً) ────────────────────────────────

class PatientSuggestion {
  const PatientSuggestion(
      {required this.name,
      this.phone = '',
      this.phone2 = '',
      this.clinic = ''});

  final String name;
  final String phone;
  final String phone2;
  final String clinic;
}

/// فهرس موحّد: سجلات + تركيبات ثم ديون — العزل الصارم للعيادة المختارة
/// (اسم بعيادة مختلفة أو مفقودة لا يُقترح عند اختيار عيادة)، ضبابي، حد 8.
List<PatientSuggestion> localNameSearch(
  String q, {
  required String selectedClinic,
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
}) {
  final map = <String, ({String phone, String phone2, String clinic})>{};
  for (final r in [...records, ...prosthetics]) {
    if (!jsTruthy(r['name'])) continue;
    if (selectedClinic.isNotEmpty && r['clinic'] != selectedClinic) {
      continue;
    }
    final name = '${r['name']}';
    final prev = map[name];
    if (prev == null) {
      map[name] = (
        phone: '${r['phone'] ?? ''}',
        phone2: '${r['phone2'] ?? ''}',
        clinic: '${r['clinic'] ?? ''}',
      );
    } else {
      map[name] = (
        phone: prev.phone.isEmpty ? '${r['phone'] ?? ''}' : prev.phone,
        phone2: prev.phone2,
        clinic:
            prev.clinic.isEmpty ? '${r['clinic'] ?? ''}' : prev.clinic,
      );
    }
  }
  for (final d in debts) {
    if (!jsTruthy(d['name'])) continue;
    if (selectedClinic.isNotEmpty && d['clinic'] != selectedClinic) {
      continue;
    }
    final name = '${d['name']}';
    final prev = map[name];
    if (prev == null) {
      map[name] = (
        phone: '${d['phone'] ?? ''}',
        phone2: '${d['phone2'] ?? ''}',
        clinic: '${d['clinic'] ?? ''}',
      );
    } else if (prev.phone.isEmpty && jsTruthy(d['phone'])) {
      map[name] =
          (phone: '${d['phone']}', phone2: prev.phone2, clinic: prev.clinic);
    }
  }
  return [
    for (final e in map.entries)
      if (fuzzyMatch(q, e.key))
        PatientSuggestion(
          name: e.key,
          phone: e.value.phone,
          phone2: e.value.phone2,
          clinic: e.value.clinic,
        ),
  ].take(8).toList();
}

/// بحث «الهاتف أولاً» — onPhoneInput المحلي: نفس الرقم المطبّع داخل
/// العيادة المختارة فقط (حد 8).
List<PatientSuggestion> phoneFirstSearch(
  String phone, {
  required String selectedClinic,
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
}) {
  final ph = normPhoneDigits(phone);
  if (ph.length < 3) return const [];
  bool inClinic(Object? c) =>
      selectedClinic.isEmpty || c == selectedClinic;
  final seen = <String>{};
  final out = <PatientSuggestion>[];
  for (final r in [...records, ...prosthetics, ...debts]) {
    if (!jsTruthy(r['name']) || !inClinic(r['clinic'])) continue;
    if (normPhoneDigits('${r['phone'] ?? ''}') != ph) continue;
    final name = '${r['name']}';
    if (!seen.add(name)) continue;
    out.add(PatientSuggestion(
      name: name,
      phone: '${r['phone'] ?? ''}',
      phone2: '${r['phone2'] ?? ''}',
      clinic: '${r['clinic'] ?? ''}',
    ));
    if (out.length >= 8) break;
  }
  return out;
}

/// تطبيع هاتف — normPhone حرفياً (أرقام عربية ← لاتينية، إسقاط 00 و218
/// وأصفار البداية).
String normPhoneDigits(String? p) {
  if (p == null || p.isEmpty) return '';
  final b = StringBuffer();
  for (final ch in p.runes) {
    if (ch >= 0x0660 && ch <= 0x0669) {
      b.write(ch - 0x0660);
    } else if (ch >= 0x06F0 && ch <= 0x06F9) {
      b.write(ch - 0x06F0);
    } else {
      b.writeCharCode(ch);
    }
  }
  var d = b.toString().replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return '';
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('218')) d = d.substring(3);
  d = d.replaceFirst(RegExp(r'^0+'), '');
  return d;
}

/// medicalHasData — هل لسجل المريض الطبي بيانات فعلية؟
bool medicalHasData(Object? m) {
  if (m is! Map) return false;
  return jsTruthy(m['gender']) ||
      jsTruthy(m['age']) ||
      (m['conditions'] is List && (m['conditions'] as List).isNotEmpty) ||
      jsTruthy(m['diagnosis']) ||
      jsTruthy(m['notes']);
}

// ── دخل اليوم كجدول (LedgerRow) — أساس شاشة الإيراد اليومي ──────────────────
//
//  صفٌّ لكل حدث دخلٍ اليوم: علاجات (سجلات + تركيبات) + دفعات ديونٍ تمّت اليوم.
//  القيمة/المدفوع/المتبقي: نقداً ⇒ القيمة=المدفوع والمتبقي=0؛ ديناً ⇒ يُوصَل
//  بالدين المرتبط (القيمة=الإجمالي، المدفوع=المسدَّد، المتبقي=المتبقي)؛ دفعةُ
//  دينٍ ⇒ القيمة=المدفوع=مبلغ الدفعة والمتبقي=متبقي دينها بعدها.

class LedgerRow {
  const LedgerRow({
    required this.name,
    required this.clinic,
    required this.service,
    required this.payment,
    required this.timeMs,
    required this.value,
    required this.paid,
    required this.remaining,
    this.isExpense = false,
    this.method = '',
    this.id = '',
    this.kind = '',
    this.phone = '',
    this.by = '',
    this.payParts = const {},
  });

  final String name;
  final String clinic;
  final String service;
  final String payment; // كاش/تحويل/دين/دفعة دين/تركيبات/مصروف
  final num timeMs; // زمن التسجيل (ms) للترتيب والعرض
  final num value; // القيمة (الإجمالي) — للمصروف: مبلغ الخصم
  final num paid; // المدفوع
  final num remaining; // الدين المتبقي
  final bool isExpense; // صفّ مصروف (خصمٌ من الدخل، لا يُحتسب دخلاً)

  /// م99 — هوية الصف لقائمة الخيارات (ضغط مطول/نقر يميني):
  /// [id] معرف الكيان، [kind] نوعه: r سجل، p تركيبة، dp دفعة دين،
  /// e مصروف، و[phone] هاتف السجل إن وُجد (للزيارة السريعة).
  final String id;
  final String kind;
  final String phone;

  /// م120 — اسم دخول الموظف الذي أدخل الصف (createdBy)؛ فارغ للقديم.
  final String by;

  /// م95 — الطريقة **الفعلية** لحركة المال (كاش/تحويل/…) منفصلةً عن
  /// تسمية العرض في [payment]: صف «دفعة دين» يعرض التسمية وطريقته
  /// الحقيقية هنا، وصف المصروف يحمل هنا نوع دفعه. فارغةٌ ⇒ تعامَل
  /// بقيمة [payment] (توافقاً مع منشئي صفوف قدامى).
  final String method;

  /// الطريقة المعتمدة في توزيع البطاقة العلوية.
  String get effectiveMethod => method.isNotEmpty ? method : payment;

  /// م-تكافؤ — أجزاء الدفع حسب الطريقة للدفعة **المختلطة** (كاش + تحويل
  /// معاً في صفٍّ مدموج): تُملأ فقط حين تتعدد الطرق فعلاً، وإلا بقيت
  /// فارغة. البنية لا تحمل دفعةً مقسّمة أصلاً (عمود payment مفرد)، فالخلط
  /// ينشأ حصراً من دمج عدة حركات (دفعات نفس الدين في اليوم) بطرقٍ شتى.
  final Map<String, num> payParts;

  /// الأجزاء الفعّالة للتوزيع والفلترة: المختلط بأجزائه، وغيره جزءٌ
  /// واحد بالطريقة الفعلية وكامل المدفوع — فيتطابق مع السلوك القديم.
  Map<String, num> get effectiveParts =>
      payParts.length > 1 ? payParts : {effectiveMethod: paid};

  /// هل الصف مختلط الدفع (أكثر من طريقة)؟
  bool get isMixedPay => payParts.length > 1;
}

/// فترة اليوم — صباحي/مسائي بفاصلٍ افتراضيّ الظهر (12).
enum LedgerPeriod { morning, evening }

const ledgerPeriodLabels = <LedgerPeriod, String>{
  LedgerPeriod.morning: 'صباحي',
  LedgerPeriod.evening: 'مسائي',
};

LedgerPeriod ledgerPeriodOf(num ms, {int cutoffHour = 12}) {
  if (ms <= 0) return LedgerPeriod.morning;
  final h = DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toLocal().hour;
  return h < cutoffHour ? LedgerPeriod.morning : LedgerPeriod.evening;
}

/// «الساعة:الدقيقة» محلياً من زمن ms (— إن غاب).
String ledgerTimeLabel(num ms) {
  if (ms <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms.toInt()).toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

class LedgerTotals {
  const LedgerTotals({
    required this.count,
    required this.value,
    required this.paid,
    required this.remaining,
    required this.expense,
    required this.net,
    this.paidBy = const {},
    this.expenseBy = const {},
  });
  final int count; // عدد حالات الدخل (بلا صفوف المصروف)
  final num value;
  final num paid;
  final num remaining;
  final num expense; // مجموع صفوف المصروف
  final num net; // صافي الدخل = المدفوع − المصروفات

  /// م95 — توزيع البطاقة العلوية: المدفوع حسب الطريقة الفعلية
  /// (كاش/تحويل/…)، والمصروف حسب طريقة دفعه.
  final Map<String, num> paidBy;
  final Map<String, num> expenseBy;

  /// صافي طريقةٍ ما = مدفوعها − مصروفها.
  num netOf(String m) => (paidBy[m] ?? 0) - (expenseBy[m] ?? 0);
}

/// إجماليات — صفوف المصروف تُجمَع في [LedgerTotals.expense] فقط، وصفوف
/// الدخل في value/paid/remaining، والصافي = المدفوع − المصروفات.
LedgerTotals ledgerTotals(List<LedgerRow> rows) {
  num v = 0, p = 0, r = 0, e = 0;
  var c = 0;
  final paidBy = <String, num>{};
  final expenseBy = <String, num>{};
  for (final x in rows) {
    final m = x.effectiveMethod;
    if (x.isExpense) {
      e += x.value;
      expenseBy[m] = (expenseBy[m] ?? 0) + x.value;
    } else {
      v += x.value;
      p += x.paid;
      r += x.remaining;
      c++;
      // المدفوع فقط يدخل التوزيع — صفر المدفوع لا يضيف شيئاً.
      // م-تكافؤ — الصف المختلط يوزَّع بأجزائه الحقيقية (كاش على كاش
      // وتحويل على تحويل) بدل نسبة المجموع كله لطريقة آخر دفعة.
      if (x.paid != 0) {
        x.effectiveParts.forEach((pm, amt) {
          if (amt != 0) paidBy[pm] = (paidBy[pm] ?? 0) + amt;
        });
      }
    }
  }
  return LedgerTotals(
      count: c,
      value: v,
      paid: p,
      remaining: r,
      expense: e,
      net: p - e,
      paidBy: paidBy,
      expenseBy: expenseBy);
}

/// صفوف دخل اليوم مرتّبةً بزمن التسجيل تصاعدياً (الأقدم أولاً).
List<LedgerRow> todayLedgerRows(
    List<JMap> records, List<JMap> prosthetics, List<JMap> debts,
    // م132 — الدمج بالدين سلوكٌ دائم (قرار المالك النهائي): دفعات نفس
    // الدين في اليوم سطرٌ واحد تتحدث قيمه، وكل دينٍ آخر سطرٌ مستقل.
    // العلم يبقى للاختبارات التي توثق سلوك السطر المفرد.
    {bool mergeDebtPays = true}) {
  final today = getCurrentDate();
  num timeOf(JMap r) =>
      jsNumOr0(jsOr(r['createdAt'], jsOr(r['_activityAt'], r['_mod'])));
  num remOf(JMap d) => jsNumOr0(d['remaining']);
  num totOf(JMap d) =>
      jsNumOr0(jsOr(d['totalAmount'], jsOr(d['total'], d['total_amount'])));
  // م101 — يوم احتساب الإيراد: incomeDate إن وُجد وإلا تاريخ الصف —
  // فكل مبلغ يُحسب في يومٍ واحد بالضبط (قرار المالك: لا ازدواج).
  // م105 — القيمة الخاصة [kNoIncomeDay] لا تطابق أي يوم أبداً: السجل
  // في السجلات والمالية فقط، خارج كل جداول الدخل اليومي.
  String effDay(JMap r) =>
      jsTruthy(r['incomeDate']) ? '${r['incomeDate']}' : '${r['date'] ?? ''}';
  // مدفوع صف الدين المدموج = أقساط **هذا اليوم** فقط (بيوم احتسابها) —
  // لا الإجمالي التراكمي الذي كان يُظهر دفعة يومٍ آخر في اليومين معاً.
  // دينٌ بلا قائمة أقساط (بيانات قديمة جداً): التراكمي كما كان.
  num paidTodayOf(JMap d) {
    final inst = d['installments'];
    if (inst is! List) {
      return jsNumOr0(jsOr(d['paidAmount'], d['paid_amount']));
    }
    num s = 0;
    for (final x in inst) {
      if (x is Map && effDay(Map<String, Object?>.from(x)) == today) {
        s += jsNumOr0(x['amount']);
      }
    }
    return s;
  }
  String nm(JMap r) => jsTruthy(r['name'])
      ? '${r['name']}'
      : (jsTruthy(r['patient_name']) ? '${r['patient_name']}' : '—');
  String cli(JMap r) => jsTruthy(r['clinic']) ? '${r['clinic']}' : kNoClinic;
  String ph(JMap r) {
    final p = '${r['phone'] ?? ''}';
    return p == 'null' ? '' : p;
  }

  final debtById = {for (final d in debts) '${d['id']}': d};
  // م-تكافؤ — أجزاء دفعات اليوم لكل دين حسب الطريقة (كاش/تحويل/…):
  // تكشف الدفع المختلط في الصف المدموج فتُعرض وتُوزَّع أجزاؤه بدقة بدل
  // نسبة المجموع كله لطريقةٍ واحدة. كل دفعة (بما فيها الأولى) لها سجل
  // isDebtPayment يحمل طريقته — وهذا مصدر الأجزاء.
  final dpPartsByDebt = <String, Map<String, num>>{};
  for (final r in records) {
    if (effDay(r) != today || !jsTruthy(r['isDebtPayment'])) continue;
    final amt = jsNumOr0(r['amount']);
    if (amt <= 0) continue;
    final did = '${r['debtId'] ?? ''}';
    if (did.isEmpty || did == 'null') continue;
    final m = '${r['payment'] ?? ''}'.trim();
    if (m.isEmpty) continue;
    final p = dpPartsByDebt.putIfAbsent(did, () => <String, num>{});
    p[m] = (p[m] ?? 0) + amt;
  }
  // أجزاء مختلطة فقط، وبشرط مطابقة مجموعها للمدفوع المعروض — أي انحراف
  // (بيانات قديمة بلا سجلات دفعات) يُسقط الأجزاء فيبقى السلوك القديم.
  Map<String, num> mixedPartsOf(String debtId, num paid) {
    final parts = dpPartsByDebt[debtId];
    if (parts == null || parts.length < 2) return const {};
    num s = 0;
    parts.forEach((_, v) => s += v);
    return (s - paid).abs() < 0.001 ? parts : const {};
  }
  final debtByPros = {
    for (final d in debts)
      if (jsTruthy(d['prostheticId'])) '${d['prostheticId']}': d,
  };
  // م93 — الرابط الحقيقي يكتبه الحفظ على صف الدين لا على السجل:
  // record_saver يخزّن debt.recordId → record.id بينما السجل نفسه لا يحمل
  // debtId إطلاقاً. بلا هذه الخريطة العكسية كان دينُ اليوم لا يُعثر عليه
  // فيظهر الصف «كاملاً ديناً»: القيمة كلّها متبقّية، المدفوع صفر، والطريقة
  // «دين» رغم دفعةٍ أولى حقيقية (بلاغ ما بعد 92).
  final debtByRecord = {
    for (final d in debts)
      if (jsTruthy(d['recordId'])) '${d['recordId']}': d,
  };
  // طريقة الدفع المعروضة لصفّ الدين: الطريقة الحقيقية (كاش/تحويل) متى دُفع
  // شيء، وإلا «دين» (آجل بلا دفع). — بدل عرض كلمة «دين» دائماً.
  String debtPay(JMap? d, num paid) {
    final p = '${d?['payment'] ?? ''}'.trim();
    return (paid > 0 && p.isNotEmpty && p != 'دين') ? p : 'دين';
  }

  // م130 — «المستحق لحظة الدفعة»: إجمالي الدين ناقص مجموع الدفعات
  // السابقة لهذه الدفعة (قرار المالك: محمد الخالد دينه 5,000 دفع منه
  // 2,000 سابقاً — فدفعة اليوم 2,500 تُعرض قيمتها 3,000 لا 5,000 ولا
  // 2,500، فيقرأ الصف: القيمة − المدفوع = المتبقي). القسط يُطابَق عبر
  // recordId، والسابقُ أقدمُ إنشاءً (وبالترتيب عند التساوي). احتياطان:
  // دينٌ بلا قائمة أقساط ⇒ المتبقي الحالي + الدفعة (يكافئها للدفعة
  // الأخيرة)، ودفعة يتيمة بلا دين ⇒ مبلغ الدفعة نفسه.
  num dueAtPayment(JMap d, String recId, num amt) {
    final inst = d['installments'];
    if (inst is List) {
      num? myAt;
      var myIdx = -1;
      for (var i = 0; i < inst.length; i++) {
        final x = inst[i];
        if (x is Map && '${x['recordId'] ?? ''}' == recId) {
          myAt = jsNumOr0(x['createdAt']);
          myIdx = i;
          break;
        }
      }
      if (myIdx >= 0) {
        num before = 0;
        for (var i = 0; i < inst.length; i++) {
          if (i == myIdx) continue;
          final x = inst[i];
          if (x is! Map) continue;
          final at = jsNumOr0(x['createdAt']);
          if (at < myAt! || (at == myAt && i < myIdx)) {
            before += jsNumOr0(x['amount']);
          }
        }
        final due = totOf(d) - before;
        if (due > 0) return due;
      }
    }
    final fallback = remOf(d) + amt;
    return fallback > 0 ? fallback : amt;
  }

  final rows = <LedgerRow>[];

  // 1) علاجات السجلات (عدا دفعات الديون). الدين = صفٌّ واحد:
  //    القيمة=الإجمالي، المدفوع=المسدَّد، المتبقي=المتبقي، وطريقة الدفع الحقيقية.
  for (final r in records) {
    // نظام «التحاليل» — صفوف التحاليل معزولة عن جدول الدخل اليومي: لا صفَّ
    // لها هنا فلا تُحسب دخلاً (قيمتها المخبرية خارج المالية العامة).
    if (jsTruthy(r['isAnalysis'])) continue;
    if (effDay(r) != today || jsTruthy(r['isDebtPayment'])) continue;
    final amt = jsNumOr0(r['amount']);
    final isDebtCase = r['payment'] == 'دين' || jsTruthy(r['isDebt']);
    if (amt <= 0 && !isDebtCase) continue;
    if (isDebtCase) {
      // بحث مزدوج: debtId إن وُجد (بيانات قديمة) وإلا الخريطة العكسية
      // بمعرّف السجل نفسه — وهو مسار البيانات التي يكتبها الحفظ اليوم.
      final d =
          debtById['${r['debtId'] ?? ''}'] ?? debtByRecord['${r['id']}'];
      final value = d != null ? totOf(d) : amt;
      final paid = d != null ? paidTodayOf(d) : 0;
      rows.add(LedgerRow(
        name: nm(r),
        clinic: cli(r),
        service: '${r['service'] ?? ''}',
        payment: debtPay(d, paid),
        // م95 — الطريقة الفعلية لتوزيع البطاقة: طريقة الدين المخزنة.
        method: '${d?['payment'] ?? ''}'.trim(),
        // م-تكافؤ — دفعات اليوم على دين اليوم بطرقٍ مختلفة ⇒ أجزاء.
        payParts: d != null ? mixedPartsOf('${d['id']}', paid) : const {},
        id: '${r['id'] ?? ''}',
        kind: 'r',
        phone: ph(r),
        by: '${r['createdBy'] ?? ''}',
        timeMs: timeOf(r),
        value: value,
        paid: paid,
        remaining: d != null ? remOf(d) : value,
      ));
    } else {
      rows.add(LedgerRow(
        name: nm(r),
        clinic: cli(r),
        service: '${r['service'] ?? ''}',
        payment: '${r['payment'] ?? ''}',
        id: '${r['id'] ?? ''}',
        kind: 'r',
        phone: ph(r),
        by: '${r['createdBy'] ?? ''}',
        timeMs: timeOf(r),
        value: amt,
        paid: amt,
        remaining: 0,
      ));
    }
  }

  // 2) التركيبات.
  for (final p in prosthetics) {
    if (effDay(p) != today) continue;
    final amt = jsNumOr0(jsOr(p['total'], p['amount']));
    final isDebtCase = jsTruthy(p['isDebt']);
    if (amt <= 0 && !isDebtCase) continue;
    final svc = jsTruthy(p['type']) ? 'تركيبة ${p['type']}' : 'تركيبات';
    if (isDebtCase) {
      final d = debtByPros['${p['id']}'];
      final value = d != null ? totOf(d) : amt;
      final paid = d != null ? paidTodayOf(d) : 0;
      rows.add(LedgerRow(
        name: nm(p),
        clinic: cli(p),
        service: svc,
        payment: debtPay(d, paid),
        method: '${d?['payment'] ?? ''}'.trim(),
        payParts: d != null ? mixedPartsOf('${d['id']}', paid) : const {},
        id: '${p['id'] ?? ''}',
        kind: 'p',
        phone: ph(p),
        by: '${p['createdBy'] ?? ''}',
        timeMs: timeOf(p),
        value: value,
        paid: paid,
        remaining: d != null ? remOf(d) : value,
      ));
    } else {
      rows.add(LedgerRow(
        name: nm(p),
        clinic: cli(p),
        service: svc,
        payment: '${p['payment'] ?? 'كاش'}',
        id: '${p['id'] ?? ''}',
        kind: 'p',
        phone: ph(p),
        by: '${p['createdBy'] ?? ''}',
        timeMs: timeOf(p),
        value: amt,
        paid: amt,
        remaining: 0,
      ));
    }
  }

  // 3) دفعات الديون اليوم — على ديونٍ من أيامٍ سابقة فقط. أما دفعةُ دينِ
  //    اليوم الأولى فمدموجةٌ في صفّ أصله أعلاه (لا صفّ مكرَّر ولا ازدواج مدفوع).
  //    م131 — لكل دفعة: القيمة = المستحق لحظتها، والمتبقي = القيمة −
  //    المدفوع (كان remOf النهائي المشترك فيتطابق خطأً بين دفعتين في
  //    اليوم — بلاغ المالك). ومع [mergeDebtPays] تُدمج دفعات نفس الدين
  //    في اليوم بسطرٍ واحد (عرضٌ فقط — ملف المريض وأقساطه لا يتغيران).
  final dpRecs = <JMap>[];
  for (final r in records) {
    if (effDay(r) != today || !jsTruthy(r['isDebtPayment'])) continue;
    if (jsNumOr0(r['amount']) <= 0) continue;
    final d = debtById['${r['debtId'] ?? ''}'];
    if (d != null && '${d['date'] ?? ''}' == today) continue; // دين اليوم ⇒ مدموج
    dpRecs.add(r);
  }
  LedgerRow dpRow(JMap r, {num? paidSum, int count = 1}) {
    final amt = jsNumOr0(r['amount']);
    final paid = paidSum ?? amt;
    final d = debtById['${r['debtId'] ?? ''}'];
    // في الدمج: المستحق لحظة «أول» دفعةٍ باليوم = مستحق هذه الدفعة +
    // ما دُفع قبلها اليوم — وهنا r هي الأولى زمنياً فالمعادلة مباشرة.
    final due = d != null ? dueAtPayment(d, '${r['id'] ?? ''}', amt) : paid;
    final rem = due - paid;
    return LedgerRow(
      name: nm(r),
      clinic: cli(r),
      service: jsTruthy(r['service'])
          ? '${r['service']}${count > 1 ? ' ×$count' : ''}'
          : 'دفعة دين${count > 1 ? ' ×$count' : ''}',
      payment: 'دفعة دين',
      // م95 — التسمية للعرض؛ الطريقة الفعلية من سجل الدفعة نفسه.
      method: '${r['payment'] ?? ''}'.trim(),
      id: '${r['id'] ?? ''}',
      kind: 'dp',
      phone: ph(r),
      by: '${r['createdBy'] ?? ''}',
      timeMs: timeOf(r),
      value: due,
      paid: paid,
      remaining: rem > 0 ? rem : 0,
    );
  }

  if (!mergeDebtPays) {
    for (final r in dpRecs) {
      rows.add(dpRow(r));
    }
  } else {
    // تجميع دفعات اليوم بالدين: السطر باسم أول دفعة (قيمتها = المستحق
    // أولاً) ومجموع المدفوع، والوقت للفرز من آخر دفعة عبر timeMs الأكبر.
    final byDebt = <String, List<JMap>>{};
    var orphanIdx = 0;
    for (final r in dpRecs) {
      final key = jsTruthy(r['debtId'])
          ? 'd:${r['debtId']}'
          : 'o:${orphanIdx++}'; // يتيمة بلا دين — لا تُدمج
      byDebt.putIfAbsent(key, () => []).add(r);
    }
    byDebt.forEach((_, group) {
      group.sort((a, b) => timeOf(a).compareTo(timeOf(b)));
      num sum = 0;
      // م-تكافؤ — أجزاء المجموعة حسب الطريقة: دفعة كاش + دفعة تحويل على
      // نفس الدين تبقى صفاً واحداً لكن بأجزائها الحقيقية (عرضاً وتوزيعاً).
      final parts = <String, num>{};
      for (final r in group) {
        final amt = jsNumOr0(r['amount']);
        sum += amt;
        final m = '${r['payment'] ?? ''}'.trim();
        if (m.isNotEmpty && amt > 0) parts[m] = (parts[m] ?? 0) + amt;
      }
      final first = group.first;
      final merged = dpRow(first, paidSum: sum, count: group.length);
      // وقت السطر من آخر دفعة (كصفٍّ حي يقفز لأعلى الجدول مع كل دفعة).
      rows.add(LedgerRow(
        name: merged.name,
        clinic: merged.clinic,
        service: merged.service,
        payment: merged.payment,
        method: '${group.last['payment'] ?? ''}'.trim(),
        payParts: parts.length > 1 ? parts : const {},
        id: merged.id,
        kind: merged.kind,
        phone: merged.phone,
        by: merged.by,
        timeMs: timeOf(group.last),
        value: merged.value,
        paid: merged.paid,
        remaining: merged.remaining,
      ));
    });
  }

  rows.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return rows;
}

// ── نظام «التحاليل» — ربط صفوف الدخل بتحاليلها (عرضاً وحذفاً) ──────────────
//
//  صفوف التحاليل محروسةٌ خارج جدول الدخل والمالية (isAnalysis)، فتُقرأ من
//  جدول السجلات مباشرة لبناء خريطتَي ربط: بمعرّف الزيارة (analysisOf) وهي
//  الرابط الحقيقي الذي يكتبه الحفظ، وباسم المريض + يومٍ للاحتياط. لا قيمة
//  مالية تدخل أي إجمالي — عرضٌ بالصلاحية العامة وحذفٌ مشروطٌ بـrecords.delete.

/// تحليلٌ مرتبطٌ للعرض والحذف (الاسم/القيمة/الطريقة/المعرّف).
/// [id] معرّف سجل التحليل في قاعدة البيانات — يتيح الحذف المباشر من الجداول
/// عبر repos.records.delete(id). القيمة الافتراضية '' للتوافق الخلفي.
class AnalysisLink {
  const AnalysisLink({
    required this.name,
    required this.amount,
    required this.payment,
    this.id = '',
  });

  final String name;
  final num amount;
  final String payment;
  // معرّف السجل في قاعدة البيانات — يتيح الحذف المباشر من الجداول.
  final String id;

  bool get isCash => payment == 'كاش';
}

/// خريطتا ربط التحاليل: [byRecord] بمعرّف الزيارة (analysisOf)، و[byPatDay]
/// بمفتاح «الاسم|اليوم» للاحتياط حين لا يُطابق المعرّف (بيانات قديمة).
class AnalysisIndex {
  const AnalysisIndex(this.byRecord, this.byPatDay);

  final Map<String, List<AnalysisLink>> byRecord;
  final Map<String, List<AnalysisLink>> byPatDay;

  /// تحاليل صفٍّ: الربط بالمعرّف أولاً ثم بالاسم+اليوم (كما في العرض).
  List<AnalysisLink> forRow(String recId, String name, String day) {
    final byId = byRecord[recId];
    if (byId != null && byId.isNotEmpty) return byId;
    return byPatDay['$name|$day'] ?? const [];
  }
}

/// يبني فهرس التحاليل من صفوف السجلات (isAnalysis فقط). [day] الافتراضي
/// اليوم الحالي (لمفتاح الاسم+اليوم) — يمرَّر صراحةً في الاختبارات.
/// حقل [id] في كل رابط يُملأ من 'id' السجل ليتيح الحذف المباشر.
AnalysisIndex buildAnalysisIndex(List<JMap> records) {
  final byRecord = <String, List<AnalysisLink>>{};
  final byPatDay = <String, List<AnalysisLink>>{};
  for (final r in records) {
    if (!jsTruthy(r['isAnalysis'])) continue;
    // معرّف سجل التحليل — يُمرَّر في الرابط لإتاحة الحذف المباشر.
    final link = AnalysisLink(
      name: jsTruthy(r['analysisName']) ? '${r['analysisName']}' : 'تحليل',
      amount: jsNumOr0(r['amount']),
      payment: '${r['payment'] ?? ''}'.trim(),
      id: '${r['id'] ?? ''}',
    );
    final of = '${r['analysisOf'] ?? ''}';
    if (of.isNotEmpty && of != 'null') {
      (byRecord[of] ??= []).add(link);
    }
    final nm = '${r['name'] ?? ''}';
    final day = '${r['date'] ?? ''}';
    if (nm.isNotEmpty && day.isNotEmpty) {
      (byPatDay['$nm|$day'] ??= []).add(link);
    }
  }
  return AnalysisIndex(byRecord, byPatDay);
}

/// أنماط فرز جدول الدخل.
enum LedgerSort { timeAsc, timeDesc, nameAsc, nameDesc, valueDesc, valueAsc }

const ledgerSortLabels = <LedgerSort, String>{
  LedgerSort.timeAsc: 'الساعة (الأقدم)',
  LedgerSort.timeDesc: 'الساعة (الأحدث)',
  LedgerSort.nameAsc: 'الاسم (أ-ي)',
  LedgerSort.nameDesc: 'الاسم (ي-أ)',
  LedgerSort.valueDesc: 'القيمة (الأعلى)',
  LedgerSort.valueAsc: 'القيمة (الأدنى)',
};

/// فلترة صفوف الدخل: اسم (تضمين) + عيادات + طرق دفع (اختيار متعدد؛ فارغ=الكل)
/// + «عليه متبقٍّ فقط».
///
///  م-تكافؤ — فلتر الطريقة يلتقط الصف المختلط عبر أجزائه أيضاً، ثم
///  **يُسقطه على الطريقة المطلوبة وحدها**: فلترة «كاش» تعرض جزء الكاش
///  فقط (قيمةً ومدفوعاً) لا المجموع المدموج — والمتبقي يبقى متبقي الدين
///  الحقيقي. لا دمج بين الطريقتين أثناء الفلترة (قرار المالك).
List<LedgerRow> filterLedgerRows(
  List<LedgerRow> rows, {
  String nameQuery = '',
  Set<String> clinics = const {},
  Set<String> payments = const {},
  bool onlyRemaining = false,
  LedgerPeriod? period,
  int cutoffHour = 12,
}) {
  final q = nameQuery.trim();
  LedgerRow project(LedgerRow r) {
    // إسقاط الصف المختلط على الطرق المطلوبة فقط (متى لم تُطابق تسميتُه).
    if (payments.isEmpty || !r.isMixedPay || payments.contains(r.payment)) {
      return r;
    }
    final sub = <String, num>{
      for (final e in r.payParts.entries)
        if (payments.contains(e.key)) e.key: e.value,
    };
    if (sub.isEmpty || sub.length == r.payParts.length) return r;
    num s = 0;
    sub.forEach((_, v) => s += v);
    return LedgerRow(
      name: r.name,
      clinic: r.clinic,
      service: r.service,
      payment: r.payment,
      method: sub.length == 1 ? sub.keys.first : r.method,
      payParts: sub.length > 1 ? sub : const {},
      id: r.id,
      kind: r.kind,
      phone: r.phone,
      by: r.by,
      timeMs: r.timeMs,
      isExpense: r.isExpense,
      value: s,
      paid: s,
      remaining: r.remaining,
    );
  }

  bool payMatch(LedgerRow r) =>
      payments.isEmpty ||
      payments.contains(r.payment) ||
      r.effectiveParts.keys.any(payments.contains);

  return [
    for (final r in rows)
      if ((q.isEmpty || r.name.contains(q)) &&
          (clinics.isEmpty || clinics.contains(r.clinic)) &&
          payMatch(r) &&
          (!onlyRemaining || r.remaining > 0) &&
          (period == null ||
              ledgerPeriodOf(r.timeMs, cutoffHour: cutoffHour) == period))
        project(r),
  ];
}

/// خيارات فلتر «الدفع» من الصفوف: تسميات الصفوف + طرق الأجزاء المختلطة
/// (فيظهر «كاش» و«تحويل» كخيارين متى وُجد صفٌّ مختلط) — تستعملها
/// الشاشتان الهاتفية والمكتبية فيتطابق الخياران بالبناء.
List<String> ledgerPayOptions(List<LedgerRow> rows) {
  final s = <String>{};
  for (final r in rows) {
    if (r.payment.isNotEmpty) s.add(r.payment);
    if (r.isMixedPay) s.addAll(r.payParts.keys);
  }
  return s.toList()..sort();
}

/// فرز صفوف الدخل وفق [mode] (نسخة جديدة، لا يمسّ الأصل).
List<LedgerRow> sortLedgerRows(List<LedgerRow> rows, LedgerSort mode) {
  final out = [...rows];
  switch (mode) {
    case LedgerSort.timeAsc:
      out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    case LedgerSort.timeDesc:
      out.sort((a, b) => b.timeMs.compareTo(a.timeMs));
    case LedgerSort.nameAsc:
      out.sort((a, b) => a.name.compareTo(b.name));
    case LedgerSort.nameDesc:
      out.sort((a, b) => b.name.compareTo(a.name));
    case LedgerSort.valueDesc:
      out.sort((a, b) => b.value.compareTo(a.value));
    case LedgerSort.valueAsc:
      out.sort((a, b) => a.value.compareTo(b.value));
  }
  return out;
}
