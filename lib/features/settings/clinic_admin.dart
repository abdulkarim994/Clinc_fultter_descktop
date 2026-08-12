/// م170 — إدارة العيادات المتقدمة (قرارات المالك 2026-08-12):
///
///  • **أرشفة الاسم القديم** (تعديل الاسم — «السجلات الجديدة فقط»): الاسم
///    القديم يخرج من قائمة العيادات النشطة إلى [kArchivedClinicsKey]
///    فيبقى عرضاً تاريخياً في السجلات والمالية (صفوفه لا تُمس) ويختفي من
///    نماذج الإدخال والحجوزات والفلاتر (كلها تقرأ clinicsOf النشطة).
///  • **تجميد اللقطة المالية ثم الحذف الحقيقي**: قبل حذف عيادةٍ يُجمَّد
///    ملخصها المالي الشهري في [kDeletedClinicsFinanceKey] (كتلة config
///    مرنة تعبر المزامنة — لا تغيير مخطط)، ثم تُحذف بيانات مرضاها فعلياً
///    بشواهد القبور (تصل Supabase وكل الأجهزة عبر المزامنة) وصورها عبر
///    طابور حذف R2 القائم — فالسجل المالي القديم يبقى عادياً كما طلب
///    المالك بينما بيانات المرضى تزول نهائياً.
///  • الترخيص بلا مساس: حد العيادات يبقى على الإضافة (cachedMaxClinics)،
///    والمؤرشفة ليست نشطة فلا تُحسب من الحد.
library;

import '../../core/utils/js_compat.dart';
import '../../data/db/local_db.dart';
import '../../data/repositories/repositories.dart';
import '../finance/analyses_filter.dart' show monthAnalysesTotals;
import '../finance/profits_logic.dart' show getMonthlyReport;
import '../finance/treasury_logic.dart'
    show
        TreasurySlice,
        clinicCash,
        clinicXfer,
        prosPaidByMethod;
import '../patients/profile_actions.dart' show deletePatientData;
import '../xrays/storage_meter.dart' show StorageMeter;
import '../xrays/xray_pipeline.dart'
    show enqueuePendingDelete, markXrayDeleted;

typedef JMap = Map<String, Object?>;

/// مفتاح قائمة العيادات المؤرشفة في app.config (أسماءٌ تاريخية للعرض فقط).
const String kArchivedClinicsKey = 'archivedClinics';

/// مفتاح اللقطات المالية المجمدة للعيادات المحذوفة:
/// {اسم العيادة: {'YYYY-MM': {cash, xfer, prosCash, prosXfer, analCash,
///   analXfer, revenue, doctor, clinicShare}}}
const String kDeletedClinicsFinanceKey = 'deletedClinicsFinance';

/// العيادات المؤرشفة (أسماءٌ قديمة بعد «التعديل للجديد فقط») — عرضٌ فقط.
List<String> archivedClinicsOf(JMap cfg) => cfg[kArchivedClinicsKey] is List
    ? [
        for (final c in cfg[kArchivedClinicsKey] as List)
          if ('$c'.trim().isNotEmpty) '$c'.trim(),
      ]
    : const [];

/// اللقطات المالية المجمدة للعيادات المحذوفة.
JMap frozenClinicsFinanceOf(JMap cfg) =>
    cfg[kDeletedClinicsFinanceKey] is Map
        ? Map<String, Object?>.from(cfg[kDeletedClinicsFinanceKey] as Map)
        : const {};

/// صف لقطةٍ مجمدة لشهرٍ: (اسم العيادة المحذوفة، حقول الشهر).
typedef FrozenRow = ({String clinic, JMap fields});

/// صفوف الشهر المجمدة للعيادات المحذوفة (للخزينة والأرباح) — قد تكون فارغة.
List<FrozenRow> frozenRowsForMonth(JMap cfg, String month) {
  final out = <FrozenRow>[];
  frozenClinicsFinanceOf(cfg).forEach((clinic, months) {
    if (months is! Map) return;
    final m = months[month];
    if (m is Map) {
      out.add((clinic: clinic, fields: Map<String, Object?>.from(m)));
    }
  });
  return out;
}

/// مجاميع الشهر المجمدة (تُضاف لصفوف جدول الإجمالي كي يبقى الشهر التاريخي
/// بأرقامه الصحيحة حرفياً بعد الحذف).
({
  num cash,
  num xfer,
  num prosCash,
  num prosXfer,
  num analCash,
  num analXfer,
}) frozenTotalsForMonth(JMap cfg, String month) {
  num cash = 0, xfer = 0, prosCash = 0, prosXfer = 0, analCash = 0, analXfer = 0;
  for (final row in frozenRowsForMonth(cfg, month)) {
    cash += jsNumOr0(row.fields['cash']);
    xfer += jsNumOr0(row.fields['xfer']);
    prosCash += jsNumOr0(row.fields['prosCash']);
    prosXfer += jsNumOr0(row.fields['prosXfer']);
    analCash += jsNumOr0(row.fields['analCash']);
    analXfer += jsNumOr0(row.fields['analXfer']);
  }
  return (
    cash: cash,
    xfer: xfer,
    prosCash: prosCash,
    prosXfer: prosXfer,
    analCash: analCash,
    analXfer: analXfer,
  );
}

/// نسخ نسب الطبيب لعيادةٍ (من مدخل الاسم القديم إلى الجديد) — تُستدعى في
/// خياري التعديل معاً كي لا يفقد الاسم الجديد نِسَبه المضبوطة.
JMap copyClinicRates(JMap cfg, String oldName, String newName) {
  final ratesV = cfg['clinicRates'];
  if (ratesV is! Map) return cfg;
  final rates = Map<String, Object?>.from(ratesV);
  final clinicsV = rates['clinics'];
  if (clinicsV is! Map) return cfg;
  final clinics = Map<String, Object?>.from(clinicsV);
  final old = clinics[oldName];
  if (old is! Map) return cfg;
  clinics[newName] = jsonDeepCopy(old);
  rates['clinics'] = clinics;
  return {...cfg, 'clinicRates': rates};
}

/// م170 — تعديل الاسم «للسجلات الجديدة فقط»: الاسم القديم يؤرشف (عرضٌ
/// تاريخي) والجديد يحل محله في القائمة النشطة، والصفوف التاريخية لا تُمس.
/// يعيد true عند النجاح.
bool renameClinicNewOnly(
    Repositories repos, String oldName, String newName) {
  final o = oldName.trim(), n = newName.trim();
  if (o.isEmpty || n.isEmpty || o == n) return false;
  final v = repos.settings.get('app.config');
  var cfg = v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
  final clinics = [
    for (final c in (cfg['clinics'] as List? ?? const [])) '$c',
  ];
  final idx = clinics.indexOf(o);
  if (idx == -1 || clinics.contains(n)) return false;
  clinics[idx] = n;
  final archived = [...archivedClinicsOf(cfg)];
  if (!archived.contains(o)) archived.add(o);
  cfg = {...cfg, 'clinics': clinics, kArchivedClinicsKey: archived};
  cfg = copyClinicRates(cfg, o, n);
  repos.settings.set('app.config', cfg);
  return true;
}

/// جرد ما سيُحذف مع العيادة — أرقامٌ فعلية لحوار التأكيد الخطير.
({
  int records,
  int analyses,
  int pros,
  int debts,
  int appts,
  int xrays,
  int patients,
}) clinicDeleteInventory(Repositories repos, JMap cfg, String clinic) {
  final cl = clinic.trim();
  bool inClinic(JMap r) => '${r['clinic'] ?? ''}'.trim() == cl;
  final recs = repos.records.getAll().where(inClinic).toList();
  final analyses = recs.where((r) => jsTruthy(r['isAnalysis'])).length;
  final pros = repos.prosthetics.getAll().where(inClinic).length;
  final debts = repos.debts.getAll().where(inClinic).length;
  final appts = repos.appointments.getAll().where(inClinic).length;
  final names = <String>{
    for (final r in recs) '${r['name'] ?? ''}'.trim(),
    for (final p in repos.prosthetics.getAll().where(inClinic))
      '${p['name'] ?? ''}'.trim(),
    for (final d in repos.debts.getAll().where(inClinic))
      '${d['name'] ?? ''}'.trim(),
  }..remove('');
  // صور الأشعة: صفوف المستودع الموسومة بالعيادة + مفاتيح معارض config
  // الموسومة بها (اتحادٌ بلا تكرار — المصدران قد يتقاطعان).
  final keys = <String>{};
  for (final x in repos.xrays.getAll()) {
    final xc = '${x['clinic_id'] ?? ''}'.trim();
    if (xc == cl) {
      final k = '${x['file_key'] ?? ''}'.trim();
      if (k.isNotEmpty) keys.add(k);
    }
  }
  final metaV = cfg['xrayMeta'];
  if (metaV is Map) {
    metaV.forEach((k, m) {
      if (m is Map && '${m['clinic'] ?? ''}'.trim() == cl) keys.add('$k');
    });
  }
  return (
    records: recs.length - analyses,
    analyses: analyses,
    pros: pros,
    debts: debts,
    appts: appts,
    xrays: keys.length,
    patients: names.length,
  );
}

/// تجميد اللقطة المالية الشهرية للعيادة قبل حذفها: لكل شهرٍ فيه نشاط —
/// كاش/تحويل الإيراد، التركيبات المدفوعة كاش/تحويل، التحاليل كاش/تحويل،
/// وأرباح الشهر (الإيراد/حصة الطبيب/حصة العيادة) بلقطات الصفوف نفسها.
Map<String, JMap> freezeClinicFinance(Repositories repos, JMap cfg,
    String clinic) {
  final cl = clinic.trim();
  final records = repos.records.getAll().cast<JMap>();
  final prosthetics = repos.prosthetics.getAll().cast<JMap>();
  final debts = repos.debts.getAll().cast<JMap>();
  bool inClinic(JMap r) => '${r['clinic'] ?? ''}'.trim() == cl;

  // أشهر النشاط من تواريخ صفوف العيادة (سجلات + تركيبات).
  final months = <String>{};
  for (final r in [...records.where(inClinic), ...prosthetics.where(inClinic)]) {
    final d = '${r['date'] ?? ''}';
    if (d.length >= 7) months.add(d.substring(0, 7));
  }

  final out = <String, JMap>{};
  final doctorPct = jsNumOr0(jsOr(cfg['doctorPct'], 50));
  for (final month in months) {
    final s = TreasurySlice(month,
        records: records, prosthetics: prosthetics, debts: debts);
    final cash = clinicCash(s, cl);
    final xfer = clinicXfer(s, cl);
    final prosPay = prosPaidByMethod(
      [...s.pros.where((p) => p['clinic'] == cl)],
      [...s.pdPays.where((r) => r['clinic'] == cl)],
    );
    // التحاليل الثلاثية للعيادة في الشهر (معزولة مالياً — قسم مستقل).
    final anal = monthAnalysesTotals(
        [...records.where((r) => inClinic(r))],
        month: month);
    // أرباح الشهر بنطاق العيادة (لقطات الصفوف أولاً — الحساب القائم).
    final rep = getMonthlyReport(
      [
        for (final r in records)
          if (inClinic(r) && '${r['date'] ?? ''}'.startsWith(month)) r,
      ],
      [
        for (final p in prosthetics)
          if (inClinic(p) && '${p['date'] ?? ''}'.startsWith(month)) p,
      ],
      debts,
      month,
      doctorPct,
    );
    final fields = <String, Object?>{
      'cash': cash,
      'xfer': xfer,
      'prosCash': prosPay.cash,
      'prosXfer': prosPay.xfer,
      'analCash': anal.cash,
      'analXfer': anal.transfer,
      'revenue': rep.grandTotal,
      'doctor': rep.doctorTotal,
      'clinicShare': rep.clinicTotal,
    };
    final any = fields.values.any((v) => jsNumOr0(v) != 0);
    if (any) out[month] = fields;
  }
  return out;
}

/// م170 — الحذف الحقيقي الشامل للعيادة (تجميدٌ ثم كنس):
///  1. تجميد اللقطة المالية في config (يبقى السجل المالي القديم عادياً).
///  2. حذف بيانات كل مريضٍ عبر [deletePatientData] القائم (صفوف + أشعة +
///     طابور R2 + الحصة + كتل config الموسومة) بنطاق هذه العيادة.
///  3. كنس البقايا (استراحات/مواعيد بلا مريض/صفوف شاردة/صفوف أشعة موسومة).
///  4. تنظيف config: إزالة العيادة من القائمة النشطة والمؤرشفة ونسبها.
/// يعيد عدد الصفوف الملموسة. **لا رجعة فيه** — التأكيد على المنادي.
int deleteClinicCascade(
  Repositories repos, {
  required String clinic,
  required LocalDb db,
  required StorageMeter meter,
}) {
  final cl = clinic.trim();
  if (cl.isEmpty) return 0;
  var touched = 0;

  JMap cfgNow() {
    final v = repos.settings.get('app.config');
    return v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
  }

  // 1) التجميد أولاً — قبل مسّ أي صف (قرار المالك: المالية القديمة تبقى).
  final frozen = freezeClinicFinance(repos, cfgNow(), cl);
  if (frozen.isNotEmpty) {
    final cfg = cfgNow();
    final all = frozenClinicsFinanceOf(cfg);
    repos.settings.set('app.config', {
      ...cfg,
      kDeletedClinicsFinanceKey: {...all, cl: frozen},
    });
  }

  bool inClinic(JMap r) => '${r['clinic'] ?? ''}'.trim() == cl;

  // 2) حذف بيانات كل مريضٍ في العيادة عبر المسار السلطوي القائم.
  final names = <String>{
    for (final r in repos.records.getAll().where(inClinic))
      '${r['name'] ?? ''}'.trim(),
    for (final p in repos.prosthetics.getAll().where(inClinic))
      '${p['name'] ?? ''}'.trim(),
    for (final d in repos.debts.getAll().where(inClinic))
      '${d['name'] ?? ''}'.trim(),
  }..remove('');
  for (final name in names) {
    touched += deletePatientData(
      repos,
      cfgNow(),
      name: name,
      clinic: cl,
      db: db,
      meter: meter,
    );
  }

  // 3) كنس البقايا — مواعيد العيادة (استراحات/مواعيد بلا صفوف مرضى).
  for (final a in repos.appointments.getAll().where(inClinic)) {
    repos.appointments.delete('${a['id']}');
    touched++;
  }
  // صفوف شاردة دفاعياً (لا يفترض بقاؤها بعد كنس المرضى).
  for (final r in repos.records.getAll().where(inClinic)) {
    repos.records.delete('${r['id']}');
    touched++;
  }
  for (final p in repos.prosthetics.getAll().where(inClinic)) {
    repos.prosthetics.delete('${p['id']}');
    touched++;
  }
  for (final d in repos.debts.getAll().where(inClinic)) {
    repos.debts.delete('${d['id']}');
    touched++;
  }
  // صفوف أشعةٍ موسومة بالعيادة لم يلتقطها كنس المرضى (اسمٌ غاب عن الجداول).
  for (final x in repos.xrays.getAll()) {
    if ('${x['clinic_id'] ?? ''}'.trim() != cl) continue;
    final key = '${x['file_key'] ?? ''}'.trim();
    repos.xrays.delete('${x['id']}');
    if (key.isNotEmpty) {
      markXrayDeleted(db, key);
      enqueuePendingDelete(db, key);
      meter.removeKey(key);
    }
    touched++;
  }

  // 4) تنظيف config: القائمة النشطة + المؤرشفة + نسب العيادة.
  final cfg = cfgNow();
  final clinics = [
    for (final c in (cfg['clinics'] as List? ?? const []))
      if ('$c' != cl) '$c',
  ];
  final archived = [
    for (final c in archivedClinicsOf(cfg))
      if (c != cl) c,
  ];
  var next = <String, Object?>{
    ...cfg,
    'clinics': clinics,
    kArchivedClinicsKey: archived,
  };
  final ratesV = next['clinicRates'];
  if (ratesV is Map) {
    final rates = Map<String, Object?>.from(ratesV);
    final rc = rates['clinics'];
    if (rc is Map && rc.containsKey(cl)) {
      final m = Map<String, Object?>.from(rc)..remove(cl);
      rates['clinics'] = m;
      next = {...next, 'clinicRates': rates};
    }
  }
  repos.settings.set('app.config', next);
  return touched;
}

/// نسخة عميقة لخرائط/قوائم config (قيمٌ JSON بسيطة).
Object? jsonDeepCopy(Object? v) {
  if (v is Map) {
    return {for (final e in v.entries) '${e.key}': jsonDeepCopy(e.value)};
  }
  if (v is List) return [for (final x in v) jsonDeepCopy(x)];
  return v;
}
