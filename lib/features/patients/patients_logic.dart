/// منطق قسم السجلات — نقل حرفي من patients.store.js وClinicsLanding.vue
/// وClinicPatients.vue:
///   • **recordAmount**: توحيد مبلغ الصف amount ?? total ?? totalAmount.
///   • **buildPatientMap**: التجميع المرجعي لكل مريض (زيارات، إجمالي
///     محصَّل، إجمالي كلي، آخر تاريخ/تعديل/نشاط سريري، خدمات، ديون
///     وأرصدة مخابر) — الدين المرتبط بسجل يستبدل مبلغه بالمدفوع فقط،
///     والدين غير المرتبط يُحسب زيارةً بمدفوعه (حرفياً بكل فروعه).
///   • **clinicCards**: بطاقات بوابة العيادات — مرضى وزيارات الشهر،
///     الدخل (استبعاد ما ارتبط بدين + إضافة دفعات ديون الشهر)، الديون
///     المعلقة.
///   • **landingSearchResults**: البحث الشامل (اسم ضبابي مرتب fuzzyScore
///     أو وضع هاتف بالأرقام) حد 15 مع عيادة أول قيد.
///   • **clinicPatients/filterClinicPatients**: مرضى عيادة بشاراتهم
///     (دين نشط/تركيبات/تقرير) وفهرس هواتفهم، وأنماط الفرز الخمسة
///     بأولوية البحث.
library;

import 'treatment_plan_store.dart';
import '../../data/repositories/patients_repository.dart'
    show patientKeyFor;
import '../../data/sync/merge/config_tombs.dart';
import '../../core/utils/ar_normalize.dart';
import '../../core/utils/js_compat.dart';
import 'audit_log.dart' show appendAudit;
import 'clinic_scope.dart'
    show clinicScopedKey, clinicScopedRename, medicalScopedKey;
import '../appointments/appointments_logic.dart'
    show fuzzyMatch, levenshtein;

typedef JMap = Map<String, Object?>;

/// recordAmount — حرفياً (amount ?? total ?? totalAmount).
num recordAmount(JMap? r) {
  if (r == null) return 0;
  final v = r.containsKey('amount') && r['amount'] != null
      ? r['amount']
      : (r.containsKey('total') && r['total'] != null
          ? r['total']
          : r['totalAmount']);
  return jsNumOr0(v);
}

/// fuzzyScore — حرفياً من search.js (0 تطابق، 1 بادئة، 2 احتواء، 3+ مسافة).
int fuzzyScore(String query, String name) {
  final q = normAr(query);
  final n = normAr(name);
  if (n == q) return 0;
  if (n.startsWith(q)) return 1;
  if (n.contains(q)) return 2;
  return 3 + levenshtein(q, n);
}

// ── م90 — تمييز المتشابهين داخل العيادة الواحدة (بالهاتف) ──────────────────
//
//  قرار مالك يحدّث م35 جزئياً: (اسم|عيادة) وحدها تدمج مريضَين متشابهين في
//  نفس العيادة. المميّز الطبيعي هو الهاتف — وهو أصلاً جزء هوية الخلفية
//  (p:هاتف:اسم من هجرة الهوية الهاتفية) — فيُعتمد **في طبقة العرض والتنقل
//  فقط**: صفر مساس بمفاتيح المزامنة أو الحمولات.
//
//  قاعدة التقسيم الحتمية:
//  • هاتفٌ مميز واحد أو لا شيء في مجموعة (اسم|عيادة) ⇒ هوية واحدة تضم
//    الكل (ومنها الصفوف بلا هاتف) — سلوك م35 حرفياً، فلا يتغيّر أي مريض
//    قائم غير متشابه.
//  • هاتفان مختلفان فأكثر ⇒ تنقسم: صفوف كل هاتف هوية `p:<رقم مطبَّع>`،
//    والصفوف بلا هاتف هوية `none` («بلا رقم») مستقلة — لا تخمين في
//    إلحاقها بأحد الهاتفين.
//  الهاتف الأول وحده هو المعرِّف (كما patientKeyFor في الخلفية) —
//  phone2 وسيلة تواصل لا هوية.
//
// ── م181 — الحلّال الموحّد بالوراثة (العزل الجذري) ─────────────────────────
//
//  م90 كان يقرأ هاتف كل صفٍّ **الخام وحده**، وسجلات الدفعات (الدفعة
//  الأولى ودفعات الديون) كانت تُكتب بلا هاتفٍ ولا معرّف — فكل دفعةٍ
//  لمريضٍ متشابهٍ كانت تلد مريض «بلا رقم» شبحاً بصفر قيم، وترويسة الملف
//  تنكسر (لقطات بلاغ المالك). الحل الجذري طبقتان:
//  • كتابةً: كل صفٍّ يُسكّ بهويته كاملة (هاتف + patient_id) — انظر
//    record_saver وdebt_actions.
//  • قراءةً: [IdentityIndex] يحلّ هوية أي صفٍّ من ثلاثة مصادر بالترتيب:
//    هاتفه الخام ← هاتف patient_id المسكوك (`p:<هاتف>:…`) ← **وراثةً من
//    صفّ أصله عبر الروابط الموجودة** (دفعة→دينها عبر debtId، دين→سجله
//    عبر recordId/prostheticId، تحليل→زيارته عبر analysisOf) — فتُصلَح
//    بيانات ما قبل م181 المكسورة قراءةً، حتمياً وبلا هجرة كتابة.

// ── م189 — شكلٌ واحدٌ للهاتف في فضاء الهوية (السبب الجذري للملف الشبح) ────
//
//  كان في فضاء الهوية الواحد **شكلان** للرقم نفسه: هاتف الصفّ الخام يُقرأ
//  بأرقامه كما كُتب (`0919292281`)، والهاتف المسكوك في `patient_id` يمرّ
//  على التطبيع القانوني (`patientKeyFor` ⇒ `normPhone`) فيفقد صفر البدء
//  (`919292281`). فصفٌّ يرث هويته من المعرّف (صفّ التحليل مثلاً) يصير هويةً
//  **أخرى** لنفس الشخص ⇒ ملفٌّ ثالث بصفر زيارات وبرقمٍ بلا صفر — وهو
//  حرفياً ما أظهرته لقطة المالك (`91929228I` مقابل `0919292281`).
//
//  العلاج: التطبيع القانوني ([normPhone]) في **كلا** المصدرين — فالمقارنة
//  تصير على شكلٍ واحد، ويذوب الملف الشبح **قراءةً** بلا أي هجرة بيانات.
//  والعرض يبقى بالرقم كما كتبه المالك (انظر [PatientAgg.phone]).

/// هاتف الهوية القانوني لصفٍّ (فارغ = بلا هاتف) — من عموده الخام.
/// م189 — بالتطبيع القانوني نفسه الذي يسكّ به المعرّف، لا بالأرقام الخام.
String rowIdentityPhone(JMap r) => normPhone('${r['phone'] ?? ''}');

/// أرقام الهاتف الخام لصفٍّ **للعرض** (كما كُتب) — لا للهوية.
String rowRawPhone(JMap r) =>
    '${r['phone'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');

/// م181 — هاتف patient_id المسكوك (`p:<هاتف>:<اسم>`) أو فارغ.
/// م189 — يمرّ على [normPhone] أيضاً فيتّحد شكلُه بشكل هاتف العمود.
String _pidPhone(JMap r) {
  final pid = '${r['patient_id'] ?? ''}';
  if (!pid.startsWith('p:')) return '';
  final cut = pid.indexOf(':', 2);
  final ph = cut < 0 ? pid.substring(2) : pid.substring(2, cut);
  return normPhone(ph);
}

/// م181 — فهرس الروابط: يحلّ هوية الصفوف المرتبطة وراثةً من أصولها.
/// يُبنى مرة واحدة لكل عملية تجميع/ترشيح من الجداول الثلاثة معاً.
class IdentityIndex {
  IdentityIndex(List<JMap> records, List<JMap> prosthetics, List<JMap> debts)
      : _byId = {
          for (final r in records) '${r['id']}': r,
          for (final p in prosthetics) '${p['id']}': p,
          for (final d in debts) '${d['id']}': d,
        };

  final Map<String, JMap> _byId;

  /// روابط الأصل بترتيب القرب: دفعة→دينها، دين→سجله/تركيبته، تحليل→زيارته.
  static const _linkKeys = ['debtId', 'recordId', 'prostheticId', 'analysisOf'];

  /// هاتف هوية الصف: الخام ← المسكوك ← الموروث عبر الروابط (عمق محدود
  /// بمجموعة زيارةٍ ضد أي دورة). فارغ = «بلا رقم» حقيقةً.
  String phoneOf(JMap r, [Set<String>? seen]) {
    final own = rowIdentityPhone(r);
    if (own.isNotEmpty) return own;
    final minted = _pidPhone(r);
    if (minted.isNotEmpty) return minted;
    for (final k in _linkKeys) {
      final id = '${r[k] ?? ''}';
      if (id.isEmpty || id == 'null') continue;
      final parent = _byId[id];
      if (parent == null || identical(parent, r)) continue;
      final visited = seen ?? {'${r['id']}'};
      if (!visited.add(id)) continue;
      final ph = phoneOf(parent, visited);
      if (ph.isNotEmpty) return ph;
    }
    return '';
  }
}

/// هوية الصفّ الفرعية داخل مجموعةٍ **منقسمة**: `p:<هاتف>` أو `none`.
/// م181 — بالحلّال الموروث عند تمرير [idx] (المسار المعتمد في كل العرض).
String identityOfRow(JMap r, [IdentityIndex? idx]) {
  final ph = idx?.phoneOf(r) ?? rowIdentityPhone(r);
  return ph.isEmpty ? 'none' : 'p:$ph';
}

/// الهواتف المميزة غير الفارغة داخل صفوف مجموعةٍ واحدة — قرار الانقسام.
Set<String> distinctIdentityPhones(Iterable<JMap> rows,
        [IdentityIndex? idx]) =>
    {
      for (final r in rows)
        if ((idx?.phoneOf(r) ?? rowIdentityPhone(r)).isNotEmpty)
          idx?.phoneOf(r) ?? rowIdentityPhone(r),
    };

/// هل يخصّ الصفُّ الهويةَ المطلوبة؟ هويةٌ فارغة = الكل (السلوك القائم).
/// م181 — بالحلّال الموروث عند تمرير [idx].
bool rowMatchesIdentity(JMap r, String identity, [IdentityIndex? idx]) {
  if (identity.isEmpty) return true;
  final ph = idx?.phoneOf(r) ?? rowIdentityPhone(r);
  return identity == 'none' ? ph.isEmpty : identity == 'p:$ph';
}

/// م181 — هوية الملاحة لصفٍّ من المستودعات مباشرة (فتح ملف المريض من أي
/// شاشة: الديون، دخل اليوم، سطح المكتب…): تُبنى الفهرسة من الجداول
/// الثلاثة فيرث الصفُّ المرتبط هويةَ أصله — **كل مسارات الفتح تمرّ من
/// هنا** فلا يفتح مسارٌ ملفاً بهويةٍ خاطئة تخلط سميّاً بسميّه.
String navIdentityOf(dynamic repos, JMap row) => identityOfRow(
      row,
      IdentityIndex(
        (repos.records.getAll() as List).cast<JMap>(),
        (repos.prosthetics.getAll() as List).cast<JMap>(),
        (repos.debts.getAll() as List).cast<JMap>(),
      ),
    );

/// تجميعة مريض — صنوان قيم buildPatientMap.
/// م35 (قرار مالك): الهوية = (اسم + عيادة) — نفس الاسم في عيادتين
/// تجميعتان مستقلتان تماماً.
/// م90: وعند التشابه داخل العيادة الواحدة تنقسم بالهاتف ([identity]).
class PatientAgg {
  PatientAgg(this.name,
      [this.clinic = '', this.identity = '', String phone = ''])
      : _idPhone = phone;

  final String name;
  final String clinic;

  /// م90 — الهوية الفرعية: '' = موحّدة (لا تشابه)، `p:<هاتف>` أو `none`
  /// عند انقسام مجموعة (اسم|عيادة) على هاتفين فأكثر.
  final String identity;

  /// هاتف الهوية القانوني (بلا صفر البدء) — أساس المقارنة لا العرض.
  final String _idPhone;

  /// أول هاتفٍ خامٍ رآه التجميع (كما كتبه المستخدم) — للعرض وحده.
  String _rawPhone = '';

  /// م90 — هاتف العرض للتفريق البصري (فارغ للهوية الموحّدة و«بلا رقم»).
  /// م189 — **الخام يتقدّم على القانوني**: بعد توحيد شكل الهوية صار
  /// `_idPhone` بلا صفر البدء، وعرضه هكذا يربك المالك (رقمٌ يخالف ما
  /// كتبه). فالعرض بالرقم كما كُتب، والمقارنة بالقانوني — كلٌّ في بابه.
  /// وبهذا تبقى المفاتيح المشتقّة من هاتف العرض (المعلومات الطبية/الخطة/
  /// الأرشفة) كما كانت حرفياً لكل مريضٍ قائم.
  String get phone => _rawPhone.isNotEmpty ? _rawPhone : _idPhone;

  /// م189 — يسجّل هاتف الصفّ الخام (أول غير فارغٍ يفوز).
  void noteRawPhone(Object? raw) {
    if (_rawPhone.isNotEmpty) return;
    final d = '${raw ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isNotEmpty) _rawPhone = d;
  }
  final List<JMap> entries = [];
  num total = 0;
  num grossTotal = 0;
  int visitCount = 0;
  String lastDate = '';
  num lastMod = 0;
  num lastActivity = 0;
  final Set<String> services = {};
  num debtTotal = 0;
  num debtRemaining = 0;
  num labTotal = 0;
  num labPaid = 0;
}

/// buildPatientMap — النقل الحرفي الكامل.
/// م35: التجميع الافتراضي بمفتاح (اسم|عيادة)؛ [groupByClinic]=false يعيد
/// التجميع العالمي بالاسم (للتجميعة الشاملة عند فتح ملف بلا عيادة).
/// م181 — [splitSameName]=false يعطّل انقسام المتشابهين كلياً (تجميعة
/// واحدة بالاسم): يمرّره patientForClinic بعد ترشيح الصفوف بالهوية سلفاً
/// فتطابق الترويسةُ الصفوفَ الظاهرة دائماً (كان بحث خريطةٍ منقسمة بمفتاح
/// الاسم المجرد يعيد null ⇒ ترويسة 0/0/0 — لقطة بلاغ المالك).
Map<String, PatientAgg> buildPatientMap(
    List<JMap> recs, List<JMap> pros, List<JMap> dbts,
    {bool groupByClinic = true, bool splitSameName = true}) {
  final all = [...recs, ...pros];
  // وسم صفوف التركيبات قبل الدمج (توأم _t == 'p').
  final prosIds = {for (final p in pros) '${p['id']}'};
  final map = <String, PatientAgg>{};
  final matchedDebtIds = <String>{};

  // م181 — حلّال الهوية الموروث: يُبنى من الجداول الثلاثة معاً فتحلّ
  // دفعةٌ بلا هاتف إلى هوية دينها وسجلها (إصلاح بيانات ما قبل م181).
  final idx = IdentityIndex(recs, pros, dbts);

  // م90 — تمريرة أولى: هواتف كل مجموعة (اسم|عيادة) من الجداول الثلاثة
  // معاً — فيتطابق قرارُ الانقسام بين حلقتي السجلات والديون حتماً.
  final groupPhones = <String, Set<String>>{};
  if (splitSameName) {
    for (final r in [...all, ...dbts]) {
      final nm = '${r['name'] ?? ''}'.trim();
      if (nm.isEmpty) continue;
      final cl = groupByClinic ? '${r['clinic'] ?? ''}'.trim() : '';
      final ph = idx.phoneOf(r);
      if (ph.isNotEmpty) {
        (groupPhones[clinicScopedKey(nm, cl)] ??= {}).add(ph);
      }
    }
  }

  // مفتاح الصفّ وهويته: انقسامٌ فقط عند هاتفين مختلفين فأكثر في المجموعة.
  (String, String) keyAndIdentity(JMap r, String nm, String cl) {
    final base = clinicScopedKey(nm, cl);
    if ((groupPhones[base]?.length ?? 0) < 2) return (base, '');
    final ident = identityOfRow(r, idx);
    return ('$base||$ident', ident);
  }

  PatientAgg aggFor(JMap r, String nm, String cl) {
    final (k, ident) = keyAndIdentity(r, nm, cl);
    final agg = map[k] ??= PatientAgg(nm, cl, ident,
        ident.startsWith('p:') ? ident.substring(2) : '');
    // م189 — هاتف العرض من الصفوف نفسها (كما كُتب) لا من الهوية القانونية.
    agg.noteRawPhone(r['phone']);
    return agg;
  }

  for (final r in all) {
    final nm = '${r['name'] ?? ''}'.trim();
    if (nm.isEmpty) continue;
    // م35 — مفتاح التجميع المركب (اسم|عيادة): لا اندماج بين العيادات.
    final cl = groupByClinic ? '${r['clinic'] ?? ''}'.trim() : '';
    final agg = aggFor(r, nm, cl);

    final isPros = r['_t'] == 'p' || prosIds.contains('${r['id']}');
    agg.entries.add({
      ...r,
      '_s': isPros ? 'p' : 'r',
      'amount': jsNumOr0(jsOr(r['amount'], r['total'])),
    });

    final entryGross = jsNumOr0(jsOr(r['amount'], r['total']));

    if (jsTruthy(r['isDebtPayment'])) {
      // دفعات الديون محسوبة سلفاً في paidAmount — لا شيء هنا.
    } else if (jsTruthy(r['isDebt'])) {
      agg.visitCount++;
      agg.grossTotal += entryGross;
      JMap? dbt;
      for (final d in dbts) {
        if (isPros
            ? d['prostheticId'] == r['id']
            : d['recordId'] == r['id']) {
          dbt = d;
          break;
        }
      }
      if (dbt != null) matchedDebtIds.add('${dbt['id']}');
      agg.total +=
          dbt != null ? jsNumOr0(dbt['paidAmount']) : entryGross;
    } else if (!jsTruthy(r['isAnalysis'])) {
      // نظام «التحاليل» — التحليل لا يزيد عدد الزيارات ولا الإجمالي
      // (دخلٌ مخبري معزول). يبقى في [entries] للعرض فقط دون أثرٍ مالي.
      agg.visitCount++;
      agg.grossTotal += entryGross;
      agg.total += entryGross;
    }

    final date = '${r['date'] ?? ''}';
    if (agg.lastDate.isEmpty || date.compareTo(agg.lastDate) > 0) {
      agg.lastDate = date;
    }
    final mod = jsNumOr0(r['_mod']);
    if (mod > agg.lastMod) agg.lastMod = mod;
    final act = jsNumOr0(r['_activityAt']) != 0
        ? jsNumOr0(r['_activityAt'])
        : (date.isNotEmpty
            ? (DateTime.tryParse(date)?.millisecondsSinceEpoch ?? 0)
            : 0);
    if (act > agg.lastActivity) agg.lastActivity = act;
    if (jsTruthy(r['service'])) agg.services.add('${r['service']}');
  }

  for (final d in dbts) {
    final nm = '${d['name'] ?? ''}'.trim();
    if (nm.isEmpty) continue;
    final cl = groupByClinic ? '${d['clinic'] ?? ''}'.trim() : '';
    // م90 — الدين يُنسب لهوية هاتفه هو (نفس قاعدة الانقسام).
    final agg = aggFor(d, nm, cl);
    agg.debtTotal += jsNumOr0(jsOr(d['totalAmount'], d['total']));
    agg.debtRemaining += jsNumOr0(d['remaining']);
    if (d['type'] == 'prosthetic') {
      agg.labTotal += jsNumOr0(d['labValue']);
      agg.labPaid += jsNumOr0(d['labPaid']);
    }
    if (!matchedDebtIds.contains('${d['id']}')) {
      final debtGross = jsNumOr0(jsOr(d['totalAmount'], d['total']));
      agg.visitCount++;
      agg.grossTotal += debtGross;
      agg.total += jsNumOr0(d['paidAmount']);
      final date = '${d['date'] ?? ''}';
      if (date.isNotEmpty &&
          (agg.lastDate.isEmpty || date.compareTo(agg.lastDate) > 0)) {
        agg.lastDate = date;
      }
      if (jsTruthy(d['service'])) agg.services.add('${d['service']}');
    }
  }

  return map;
}

// ── بوابة العيادات ──────────────────────────────────────────────────────────

class ClinicCard {
  const ClinicCard({
    required this.name,
    required this.patientCount,
    required this.visitCount,
    required this.income,
    required this.debtCount,
  });

  final String name;
  final int patientCount;
  final int visitCount;
  final num income;
  final int debtCount;
}

/// clinicCards — حرفياً: سجلات وتركيبات الشهر (لا دفعات)، الدخل
/// recordAmount مع استبعاد المرتبط بدين + دفعات ديون الشهر، الديون
/// المعلقة (كل status != paid).
List<ClinicCard> clinicCards({
  required List<String> clinics,
  required String month,
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
}) {
  final prosIds = {for (final p in prosthetics) '${p['id']}'};
  final allRecs = [...records, ...prosthetics];
  final monthRecs = [
    for (final r in allRecs)
      // نظام «التحاليل» — معزولة عن بطاقات العيادات: لا مريضاً ولا زيارةً
      // ولا دخلاً (دخلها المخبري خارج بوابة العيادات كلياً).
      if ('${r['date'] ?? ''}'.length >= 7 &&
          '${r['date']}'.substring(0, 7) == month &&
          !jsTruthy(r['isAnalysis']) &&
          !jsTruthy(r['isDebtPayment']))
        r,
  ];

  return [
    for (final name in clinics)
      () {
        final cRecs = [
          for (final r in monthRecs)
            if (r['clinic'] == name) r,
        ];
        final patients = <String>{
          for (final r in cRecs)
            if (jsTruthy(r['name'])) '${r['name']}',
        };
        num income = 0;
        for (final r in cRecs) {
          final isPros = prosIds.contains('${r['id']}');
          final hasDebt = isPros
              ? debts.any((d) => d['prostheticId'] == r['id'])
              : debts.any((d) => d['recordId'] == r['id']);
          if (hasDebt) continue;
          income += recordAmount(r);
        }
        num debtPayments = 0;
        for (final r in records) {
          if (jsTruthy(r['isDebtPayment']) &&
              r['clinic'] == name &&
              '${r['date'] ?? ''}'.length >= 7 &&
              '${r['date']}'.substring(0, 7) == month) {
            debtPayments += jsNumOr0(r['amount']);
          }
        }
        final cDebts = [
          for (final d in debts)
            if (d['clinic'] == name && d['status'] != 'paid') d,
        ];
        return ClinicCard(
          name: name,
          patientCount: patients.length,
          visitCount: cRecs.length,
          income: income + debtPayments,
          debtCount: cDebts.length,
        );
      }(),
  ];
}

class LandingResult {
  const LandingResult(this.agg, this.clinic);

  final PatientAgg agg;
  final String clinic;
}

/// searchResults — البحث الشامل حرفياً: وضع هاتف بالأرقام عبر phone
/// المريض وقيوده، أو اسم ضبابي مرتباً بـ fuzzyScore؛ حد 15؛ العيادة
/// من أول قيد.
List<LandingResult> landingSearchResults(
  String query, {
  required Map<String, PatientAgg> patientMap,
  required bool phoneMode,
}) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  List<PatientAgg> pts;
  if (phoneMode) {
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const [];
    pts = [
      for (final p in patientMap.values)
        if (() {
          final phones = <String>[
            for (final e in p.entries)
              if (jsTruthy(e['phone'])) '${e['phone']}',
            for (final e in p.entries)
              if (jsTruthy(e['phone2'])) '${e['phone2']}',
          ];
          return phones.any((ph) =>
              ph.replaceAll(RegExp(r'[^0-9]'), '').contains(digits));
        }())
          p,
    ];
  } else {
    pts = [
      for (final p in patientMap.values)
        if (fuzzyMatch(q, p.name)) p,
    ]..sort(
        (a, b) => fuzzyScore(q, a.name).compareTo(fuzzyScore(q, b.name)));
  }
  return [
    // م35 — عيادة التجميعة نفسها (الهوية المركبة)، لا أول قيد.
    for (final p in pts.take(15))
      LandingResult(
          p,
          p.clinic.isNotEmpty
              ? p.clinic
              : (p.entries.isNotEmpty
                  ? '${p.entries.first['clinic'] ?? ''}'
                  : '')),
  ];
}

// ── مرضى العيادة ────────────────────────────────────────────────────────────

class ClinicPatientRow {
  const ClinicPatientRow({
    required this.agg,
    required this.hasDebt,
    required this.hasPros,
    required this.hasReport,
    required this.phones,
    this.archived = false,
  });

  final PatientAgg agg;
  final bool hasDebt;
  final bool hasPros;
  final bool hasReport;
  final String phones;

  /// م75 — مؤرشف: يُخفى من القائمة والبحث افتراضياً، ويظهر بشارة رمادية
  /// عند تفعيل «إظهار المؤرشفين».
  final bool archived;
}

bool _entryHasReport(JMap e) {
  final rep = e['report'];
  if (rep is List) return rep.isNotEmpty;
  if (rep is Map) {
    final entries = rep['entries'];
    return entries is List && entries.isNotEmpty;
  }
  return false;
}

/// patients (ClinicPatients) — حرفياً: مرضى لهم قيد في العيادة، شارات
/// الدين النشط/التركيبات/التقرير، وفهرس هواتف من الجداول الثلاثة.
List<ClinicPatientRow> clinicPatients(
  String clinicName, {
  required Map<String, PatientAgg> patientMap,
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
  // م75 — مفاتيح المرضى المؤرشفين (اسم|عيادة). كل صف يُوسم بحالته؛
  // الترشيح النهائي (إخفاء/إظهار) في filterClinicPatients كي يبقى بناء
  // القائمة واحداً والقرار في مكان واحد.
  Set<String> archivedKeys = const {},
}) {
  // م-عزل الهوية — الفهرس بمفتاح **اسم|هوية** (لا الاسم وحده): صفوف كل
  // هوية هاتفية تُجمَّع منفصلة، فلا يتسرّب هاتفُ سميٍّ إلى بحث/عرض سميّه.
  // (بقاء البناء عابراً للعيادات كالأصل — الترشيح بالعيادة في العرض.)
  // م181 — الهوية بالحلّال الموروث (دفعة/دين بلا هاتف تتبع أصلها).
  final idIdx = IdentityIndex(records, prosthetics, debts);
  final phoneIdx = <String, String>{};
  final phoneIdxByName = <String, String>{};
  for (final r in [...records, ...prosthetics, ...debts]) {
    final name = '${r['name'] ?? ''}';
    if (name.isEmpty) continue;
    final ph = ('${r['phone'] ?? ''} ${r['phone2'] ?? ''}')
        .replaceAll(RegExp(r'[^0-9 ]'), '')
        .trim();
    if (ph.isEmpty) continue;
    final k = '$name|${identityOfRow(r, idIdx)}';
    phoneIdx[k] = ('${phoneIdx[k] ?? ''} $ph').trim();
    // اتحادُ هواتف الاسم — للهوية الموحّدة (غير المنقسمة) التي تضم كل صفوفه.
    phoneIdxByName[name] = ('${phoneIdxByName[name] ?? ''} $ph').trim();
  }

  return [
    // م35 — التجميعات صارت (اسم|عيادة): مرضى هذه العيادة هم تجميعاتها
    // فقط، وشارة الدين من ديون العيادة نفسها لا من عيادة أخرى.
    for (final p in patientMap.values)
      if (p.clinic == clinicName)
        ClinicPatientRow(
          agg: p,
          // م90 — دين السميّ لا يشعل شارة سميّه: الدين يُنسب لهويته.
          hasDebt: debts.any((d) =>
              d['name'] == p.name &&
              '${d['clinic'] ?? ''}' == clinicName &&
              d['status'] != 'paid' &&
              rowMatchesIdentity(d, p.identity, idIdx)),
          hasPros: p.entries
              .any((e) => e['_s'] == 'p' || e['_t'] == 'p'),
          hasReport: p.entries.any(_entryHasReport),
          // م90 — هوية منقسمة: هاتفها وحده (من فهرس اسم|هوية)؛ الموحّدة:
          // اتحاد هواتف الاسم (لها هاتف مميّز واحد على الأكثر بحكم عدم
          // الانقسام، فالاتحاد هو ذلك الهاتف).
          phones: p.identity.isEmpty
              ? phoneIdxByName[p.name] ?? ''
              : (phoneIdx['${p.name}|${p.identity}'] ?? p.phone),
          // م189 — حالةُ الأرشفة **بالهوية**: كانت بمفتاح «اسم|عيادة» وحده
          // فكان السميّان مؤرشفَين معاً حتماً (بلاغ المالك).
          archived: aggArchived(archivedKeys, p),
        ),
  ];
}

/// م189 — هل هذه **الهوية** مؤرشفة؟
///
/// قراءة متدرجة مقصودة:
///  1) مفتاح الهوية «اسم|عيادة|هاتف» — العزل الحقيقي بين السميَّين.
///  2) ثم مفتاح «اسم|عيادة» القديم — **لكن للمجموعة غير المنقسمة وحدها**:
///     فمرضى ما قبل م189 المؤرشفون (ومعظمهم بلا سميّ) لا تُفقد أرشفتهم،
///     وفي الوقت نفسه لا يعود المفتاح القديم يجمع السميَّين في مصيرٍ واحد.
bool aggArchived(Set<String> keys, PatientAgg p) {
  if (keys.contains(medicalScopedKey(p.name, p.clinic, p.phone))) return true;
  if (p.identity.isEmpty) {
    return keys.contains(clinicScopedKey(p.name, p.clinic));
  }
  return false;
}

/// أنماط الفرز — sortBy الأصل.
const clinicSortLabels = {
  'activity': 'الأحدث نشاطاً',
  'date': 'آخر زيارة',
  'name': 'الاسم',
  'amount': 'الإجمالي',
  'modified': 'آخر تعديل',
};

/// filteredPatients — حرفياً: البحث أولاً (هاتف بالأرقام أو اسم ضبابي
/// مرتب)، وإلا الفرز المختار (الافتراضي النشاط السريري ثم آخر زيارة).
List<ClinicPatientRow> filterClinicPatients(
  List<ClinicPatientRow> pts, {
  required String query,
  required bool phoneMode,
  required String sortBy,
  // م64 — فلتر «عليه دين/متبقٍ»: يقصر القائمة على المرضى ذوي دين مفتوح.
  bool debtOnly = false,
  // م75 — إظهار المؤرشفين: افتراضاً false فيُخفَون من القائمة والبحث معاً
  // (كما يُخفى المحذوف). تفعيله يُظهرهم ببشارة رمادية في الواجهة.
  bool showArchived = false,
}) {
  // الإخفاء أولاً وقبل أي بحث أو فرز: القرار في مكان واحد فلا يتسرّب
  // مؤرشف عبر مسار البحث بينما يُخفى في مسار الفرز.
  var out = showArchived
      ? [...pts]
      : [for (final p in pts) if (!p.archived) p];
  if (debtOnly) {
    out = [for (final p in out) if (p.hasDebt) p];
  }
  final q = query.trim();
  if (q.isNotEmpty) {
    if (phoneMode) {
      final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isEmpty) return const [];
      return [
        for (final p in out)
          if (p.phones.replaceAll(' ', '').contains(digits)) p,
      ];
    }
    final named = [
      for (final p in out)
        if (fuzzyMatch(q, p.agg.name)) p,
    ]..sort((a, b) => fuzzyScore(q, a.agg.name)
        .compareTo(fuzzyScore(q, b.agg.name)));
    return named;
  }
  switch (sortBy) {
    case 'name':
      out.sort((a, b) => a.agg.name.compareTo(b.agg.name));
    case 'amount':
      out.sort((a, b) => b.agg.total.compareTo(a.agg.total));
    case 'date':
      out.sort((a, b) => b.agg.lastDate.compareTo(a.agg.lastDate));
    case 'modified':
      out.sort((a, b) => b.agg.lastMod.compareTo(a.agg.lastMod));
    default: // activity
      out.sort((a, b) {
        final c = b.agg.lastActivity.compareTo(a.agg.lastActivity);
        return c != 0 ? c : b.agg.lastDate.compareTo(a.agg.lastDate);
      });
  }
  return out;
}

/// saveEditPatient — اكتساح تعديل بيانات المريض: الاسم الجديد (+ الهاتفان
/// إن مُرِّرا) على السجلات/التركيبات/الديون، والاسم + الهاتف الأول فقط
/// على المواعيد. يعيد عدد الصفوف المعدلة.
/// م35 (قرار مالك): [clinic] غير الفارغة تحصر الاكتساح بصفوف تلك العيادة
/// — مريض العيادة الأخرى بنفس الاسم لا يُمس؛ وتُهاجر مفاتيح الخطة
/// العلاجية والبطاقة الطبية المركبة (اسم|عيادة) معه.
int editPatientCascade(
  dynamic repos, {
  required String origName,
  required String newName,
  String phone = '',
  String phone2 = '',
  String clinic = '',
  // م-عزل الهوية — [identity] (p:هاتف / none) تحصر الاكتساح بصفوف تلك
  // الهوية وحدها: تعديلُ بيانات سميٍّ لا يمسّ صفوف سميّه (الاسم/الهاتف).
  // فارغةٌ = السلوك القائم (كل صفوف الاسم في العيادة — م35).
  String identity = '',
}) {
  final nm = newName.trim();
  if (nm.isEmpty) return 0;
  final cl = clinic.trim();
  final allRecs = repos.records.getAll() as List<JMap>;
  final allPros = repos.prosthetics.getAll() as List<JMap>;
  final allDebts = repos.debts.getAll() as List<JMap>;
  // م181 — نطاق الهوية بالحلّال الموروث: دفعات ما قبل م181 بلا هاتفٍ
  // تتبع دينَها فتُكتسح مع صاحبها لا مع «بلا رقم».
  final idx = IdentityIndex(allRecs, allPros, allDebts);
  bool inScope(JMap r) =>
      r['name'] == origName &&
      (cl.isEmpty || '${r['clinic'] ?? ''}'.trim() == cl) &&
      rowMatchesIdentity(r, identity, idx);
  var touched = 0;
  void sweep(List<JMap> rows, void Function(JMap) save,
      {bool withPhone2 = true, bool withPid = true}) {
    for (final r in rows) {
      if (inScope(r)) {
        // م181 — إعادة سكّ معرّف المريض مع كل اكتساح: الهوية المسكوكة
        // تلاحق الاسم/الهاتف الجديدين (هاتف النموذج وإلا هاتف الصف) —
        // فلا يبقى معرّفٌ قديم يشدّ الصف لهوية ما قبل التعديل.
        final effPhone =
            phone.isNotEmpty ? phone : '${r['phone'] ?? ''}';
        final pid = patientKeyFor(name: nm, phone: effPhone);
        final changes = <String, Object?>{
          'name': nm,
          if (phone.isNotEmpty) 'phone': phone,
          if (withPhone2 && phone2.isNotEmpty) 'phone2': phone2,
          if (withPid && pid != null) 'patient_id': pid,
        };
        save({
          ...r,
          ...changes,
          // م65 — قيود سجل التعديلات على كل صف مكتسَح (توأم
          // _patEditChanges في PatientProfile.vue): الاسم/الهاتفان.
          '_audit': appendAudit(r, changes),
        });
        touched++;
      }
    }
  }

  sweep(allRecs, (r) => repos.records.upsertLocal(r));
  sweep(allPros, (r) => repos.prosthetics.upsertLocal(r));
  sweep(allDebts, (r) => repos.debts.upsertLocal(r));
  sweep(repos.appointments.getAll() as List<JMap>,
      (r) => repos.appointments.upsertLocal(r),
      withPhone2: false);

  // ترحيل الخطة العلاجية والبطاقة الطبية مع تغيير الاسم — بمفاتيح النطاق
  // المركب (اسم|عيادة) مع القراءة المتدرجة للإرث القديم بالاسم.
  if (nm != origName) {
    final cfgV = repos.settings.get('app.config');
    var cfg = cfgV is Map
        ? Map<String, Object?>.from(cfgV)
        : <String, Object?>{};
    // هل ما زال الاسم القديم مستعملاً في عيادة أخرى؟ (يقرر مصير الإرث)
    final othersStillUse = cl.isNotEmpty &&
        [
          ...repos.records.getAll() as List<JMap>,
          ...repos.prosthetics.getAll() as List<JMap>,
          ...repos.debts.getAll() as List<JMap>,
        ].any((r) =>
            r['name'] == origName &&
            '${r['clinic'] ?? ''}'.trim() != cl);
    var changed = false;
    for (final key in const ['treatmentPlans', 'patientMedical']) {
      final before = cfg[key];
      final after = clinicScopedRename(before, origName, nm, cl,
          othersStillUseLegacy: othersStillUse);
      if (before is! Map || !_sameKeys(before, after)) {
        cfg[key] = after;
        changed = true;
        // v28 — إعادة التسمية تزيل المفتاح القديم: شاهد صريح حتى لا يعود
        // بالدمج من نسخة الجهاز الآخر، مع رفع أي شاهد عن المفتاح الجديد.
        if (before is Map) {
          for (final k in before.keys) {
            if (!after.containsKey(k)) {
              cfg = markMapKeyDeleted(cfg, key, '$k');
            }
          }
        }
        for (final k in after.keys) {
          cfg = clearMapKeyTomb(cfg, key, k);
        }
      }
    }
    if (changed) {
      repos.settings.set('app.config', cfg);
      touched++;
    }
    // v29 — صفوف مراحل الخطة تُنقل إلى المفتاح الجديد (نفس المعرّفات)
    // وتُختم القديمة بشواهد قبور — فالحذف والنقل حتميان على كل الأجهزة.
    // م97 — بهاتف صف المريض (القديم وإلا الجديد): مفتاح الهوية ومفتاح
    // العيادة كلاهما إلى هوية الاسم الجديد (المريض يحتفظ بهاتفه).
    // م-عزل الهوية — هاتف الهوية المفتوحة أولاً (p:هاتف) ثم الهاتف الجديد
    // المُدخَل ثم صف المرضى — فيُنقل مفتاح خطة السميّ الصحيح لا الآخر.
    final rowPhone = () {
      if (identity.startsWith('p:')) return identity.substring(2);
      if (phone.trim().isNotEmpty) return phone.trim();
      final p =
          '${repos.patients.getById(origName)?['phone'] ?? repos.patients.getById(nm)?['phone'] ?? ''}';
      return p == 'null' ? '' : p;
    }();
    TreatmentPlanStore(repos.settings).moveTo(origName, nm, cl,
        phone: rowPhone);
  }
  return touched;
}

bool _sameKeys(Map a, Map b) =>
    a.length == b.length && a.keys.every(b.containsKey);

// ── م10-ج: ملف المريض ──────────────────────────────────────────────────────

/// patientForClinic — تجميعة مريض معزولة بعيادة (نفس رياضيات الخريطة
/// العالمية على صفوف مرشّحة). عيادة فارغة = عالمي.
/// م-عزل الهوية — [identity] غير الفارغة (p:هاتف / none) تحصر الصفوف
/// المجمَّعة بتلك الهوية عبر [rowMatchesIdentity]، فترويسة الملف (الإجمالي/
/// المدفوع/الديون/الزيارات) تطابق **الصفوف المرشحة بالهوية** نفسها ولا
/// تخلط سميّاً بسميّه (هذا سبب لقطة المالك 0/0/0). فارغةٌ = السلوك القائم.
/// م181 — إصلاحان جذريان:
/// • الترشيح بالحلّال الموروث ([IdentityIndex] على القوائم الكاملة) —
///   فدفعةُ ما قبل م181 بلا هاتفٍ تتبع دينَها لا هويةَ «بلا رقم».
/// • البناء بلا انقسام (splitSameName:false): الصفوف مرشّحة سلفاً،
///   والانقسام الداخلي كان يشظّي الخريطة بمفاتيح `اسم||هوية` فيعود بحثُ
///   الاسم المجرد null ⇒ ترويسة 0/0/0 رغم سجلات ظاهرة (لقطة المالك).
PatientAgg? patientForClinic(
  String name,
  String clinic, {
  required List<JMap> records,
  required List<JMap> prosthetics,
  required List<JMap> debts,
  String identity = '',
}) {
  final nm = name.trim();
  if (nm.isEmpty) return null;
  final idx = IdentityIndex(records, prosthetics, debts);
  bool inClinic(JMap r) => clinic.isEmpty || r['clinic'] == clinic;
  bool mine(JMap r) =>
      '${r['name'] ?? ''}'.trim() == nm &&
      inClinic(r) &&
      rowMatchesIdentity(r, identity, idx);
  // م35 — الصفوف مرشّحة سلفاً: تجميع عالمي بالاسم يعيد تجميعة واحدة
  // صحيحة سواء فُتح الملف بعيادة أم بلا عيادة.
  return buildPatientMap(
    [for (final r in records) if (mine(r)) r],
    [for (final p in prosthetics) if (mine(p)) p],
    [for (final d in debts) if (mine(d)) d],
    groupByClinic: false,
    splitSameName: false,
  )[nm];
}

class TreatmentCardRec {
  const TreatmentCardRec({
    required this.id,
    required this.date,
    required this.amount,
    required this.paid,
    this.debt,
    this.isPros = false,
    this.labValue = 0,
    this.doctorShare = 0,
    this.clinicShare = 0,
  });

  final String id;
  final String date;
  final num amount;
  final num paid;
  final JMap? debt;
  final bool isPros;
  final num labValue;
  final num doctorShare;
  final num clinicShare;
}

class TreatmentCardGroup {
  TreatmentCardGroup(this.service, {required this.isPros});

  final String service;
  final bool isPros;
  final List<TreatmentCardRec> records = [];
  num paidTotal = 0;
  num grossTotal = 0;
  int colorIdx = 0;
}

/// treatmentCards — حرفياً: التركيبات مجموعة «تركيبات» بمدفوع دينها إن
/// وُجد (والدين غير المسدد بلا دين مرتبط = 0 للمدفوع)، والسجلات العادية
/// بخدمتها (أصل الدين بمدفوع دينه)، مرتبة تنازلياً بالمدفوع.
List<TreatmentCardGroup> treatmentCards({
  required PatientAgg patient,
  required String patientName,
  required String clinic,
  required List<JMap> prosthetics,
  required List<JMap> debts,
  // م-عزل الهوية — تحصر التركيبات والديون المرشّحة بهوية المريض المفتوح
  // (p:هاتف / none) فلا تظهر بطاقات معالجات سميّه. فارغة = السلوك القائم.
  // (سجلات المجموعات تأتي من patient.entries المرشّحة سلفاً بالهوية.)
  String identity = '',
  // م181 — حلّال الهوية الموروث من المنادي (الملف يبنيه من قوائمه الخام
  // الثلاث) — فيتبع دينٌ بلا هاتفٍ سجلَّه لا هويةَ «بلا رقم».
  IdentityIndex? idx,
}) {
  bool scoped(JMap r) =>
      r['name'] == patientName &&
      (clinic.isEmpty || r['clinic'] == clinic) &&
      rowMatchesIdentity(r, identity, idx);
  final pros = [for (final p in prosthetics) if (scoped(p)) p];
  final myDebts = [for (final d in debts) if (scoped(d)) d];
  final groups = <String, TreatmentCardGroup>{};

  for (final p in pros) {
    final g = groups['تركيبات'] ??=
        TreatmentCardGroup('تركيبات', isPros: true);
    final total = jsNumOr0(p['total']);
    JMap? debt;
    for (final d in myDebts) {
      if (d['prostheticId'] == p['id']) {
        debt = d;
        break;
      }
    }
    final paid = debt != null
        ? jsNumOr0(debt['paidAmount'])
        : (jsTruthy(p['isDebt']) ? 0 : total);
    g.records.add(TreatmentCardRec(
      id: '${p['id']}',
      date: '${p['date'] ?? ''}',
      amount: total,
      paid: paid,
      debt: debt,
      isPros: true,
      labValue: jsNumOr0(p['labValue']),
      doctorShare: jsNumOr0(p['doctorShare']),
      clinicShare: jsNumOr0(p['clinicShare']),
    ));
    g.paidTotal += paid;
    g.grossTotal += total;
  }

  for (final r in patient.entries) {
    if (r['_s'] == 'p' || r['_t'] == 'p') continue;
    if (jsTruthy(r['isDebtPayment'])) continue;
    final svc = jsTruthy(r['service']) ? '${r['service']}' : 'أخرى';
    if (svc == 'تركيبات') continue;
    final g = groups[svc] ??= TreatmentCardGroup(svc, isPros: false);
    final amount = jsNumOr0(jsOr(r['amount'], r['total']));
    if (jsTruthy(r['isDebt'])) {
      JMap? debt;
      for (final d in myDebts) {
        if (d['recordId'] == r['id']) {
          debt = d;
          break;
        }
      }
      final paid = debt != null ? jsNumOr0(debt['paidAmount']) : amount;
      g.records.add(TreatmentCardRec(
          id: '${r['id']}',
          date: '${r['date'] ?? ''}',
          amount: amount,
          paid: paid,
          debt: debt));
      g.paidTotal += paid;
      g.grossTotal += amount;
    } else {
      g.records.add(TreatmentCardRec(
          id: '${r['id']}',
          date: '${r['date'] ?? ''}',
          amount: amount,
          paid: amount));
      g.paidTotal += amount;
      g.grossTotal += amount;
    }
  }

  final out = [
    for (final g in groups.values)
      if (g.grossTotal > 0) g,
  ]..sort((a, b) => b.paidTotal.compareTo(a.paidTotal));
  for (var i = 0; i < out.length; i++) {
    out[i].colorIdx = i % 6;
  }
  return out;
}
