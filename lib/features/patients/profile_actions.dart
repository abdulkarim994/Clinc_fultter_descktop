/// أفعال ملف المريض — نقل حرفي من PatientProfile.vue:
///   • **updateRecAmount**: تعديل قيمة سجل/تركيبة — التركيبة يعاد حساب
///     حصتيها من لقطة النسبة **المجمدة** في الصف (أو نسبة تركيبات
///     العيادة الحالية للصفوف القديمة بلا لقطة)، لا النسبة العامة أبداً.
///   • **deleteEntryCascade** (delRec): حذف تركيبة/سجل — الدين المرتبط
///     يُحذف مع كل سجلات دفعاته؛ وحذف «سجل دفعة» يعيد حساب دينه
///     (المدفوع/المتبقي/الحالة، وللتركيبات labPaid وdoctorEarned بنسبة
///     العيادة) ويزيل قسطه من القائمة.
library;

import 'audit_log.dart' show appendAudit;
import 'treatment_plan_store.dart';
import '../../data/sync/merge/config_tombs.dart';
import '../../core/utils/js_compat.dart';
import '../../data/db/local_db.dart' show LocalDb;
import 'clinic_scope.dart' show clinicScopedRemove;
import 'patients_logic.dart' show IdentityIndex, rowMatchesIdentity;
import '../xrays/xray_store.dart' show xrayGalleryKey;
import '../../data/rates/rate_snapshot.dart';
import '../../data/repositories/repositories.dart';
import '../xrays/storage_meter.dart' show StorageMeter;
import '../xrays/xray_pipeline.dart'
    show enqueuePendingDelete, markXrayDeleted;

typedef JMap = Map<String, Object?>;

/// updateRecAmount — يعيد true عند التطبيق.
bool updateRecAmount(
  Repositories repos,
  JMap config, {
  required String id,
  required String type, // 'p' | 'r'
  required num newAmount,
  num? labValue,
  String? date,
  String? payment,
  String? service,
  // م102 — يوم احتساب الإيراد: null = لا تغيير؛ فارغ أو مساوٍ للتاريخ =
  // مسح الحقل (يُحسب بيوم السجل)؛ قيمة أخرى = تعيينها (إيراد اليوم).
  String? incomeDate,
}) {
  if (type == 'p') {
    final old = repos.prosthetics.getById(id);
    if (old == null) return false;
    final lab =
        labValue ?? jsNumOr0(old['labValue']);
    final net = newAmount - lab;
    final snap = old['_rateSnapshot'];
    final snapPct = snap is Map ? num.tryParse('${snap['doctorPct']}') : null;
    final prosPct = snapPct ??
        jsNumOr0(buildRateSnapshot(config,
            clinic: '${old['clinic'] ?? ''}', isPros: true)['doctorPct']);
    final doc = net * (prosPct / 100);
    final changes = <String, Object?>{
      'total': newAmount,
      'labValue': lab,
      if (date != null && date.isNotEmpty) 'date': date,
      if (payment != null && payment.isNotEmpty) 'payment': payment,
    };
    final row = <String, Object?>{
      ...old,
      ...changes,
      'doctorShare': doc,
      'clinicShare': net - doc,
      '_edited': true,
      '_audit': appendAudit(old, changes),
    };
    _applyIncomeDate(row, incomeDate);
    repos.prosthetics.upsertLocal(row);
    return true;
  }
  final old = repos.records.getById(id);
  if (old == null) return false;
  final changes = <String, Object?>{
    'amount': newAmount,
    if (date != null && date.isNotEmpty) 'date': date,
    if (payment != null && payment.isNotEmpty) 'payment': payment,
    if (service != null && service.isNotEmpty) 'service': service,
  };
  final row = <String, Object?>{
    ...old,
    ...changes,
    '_edited': true,
    '_audit': appendAudit(old, changes),
  };
  _applyIncomeDate(row, incomeDate);
  repos.records.upsertLocal(row);
  return true;
}

/// م102 — تطبيق يوم الاحتساب على صفٍّ قبل كتابته (انظر عقد المعامل أعلاه).
void _applyIncomeDate(Map<String, Object?> row, String? incomeDate) {
  if (incomeDate == null) return;
  if (incomeDate.isEmpty || incomeDate == '${row['date'] ?? ''}') {
    row.remove('incomeDate');
  } else {
    row['incomeDate'] = incomeDate;
  }
}

/// deleteEntryCascade — يعيد عدد الصفوف المحذوفة/المعدلة.
int deleteEntryCascade(
  Repositories repos,
  JMap config, {
  required String id,
  required String source, // 'p' | 'r'
}) {
  var touched = 0;
  if (source == 'p') {
    final p = repos.prosthetics.getById(id);
    if (jsTruthy(p?['isDebt'])) {
      JMap? debt;
      for (final d in repos.debts.getAll()) {
        if (d['prostheticId'] == id) {
          debt = d;
          break;
        }
      }
      if (debt != null) {
        for (final r in repos.records.getAll()) {
          if (jsTruthy(r['isDebtPayment']) &&
              r['debtId'] == debt['id']) {
            repos.records.delete('${r['id']}');
            touched++;
          }
        }
        repos.debts.delete('${debt['id']}');
        touched++;
      }
    }
    repos.prosthetics.delete(id);
    return touched + 1;
  }

  final r = repos.records.getById(id);
  if (r == null) return 0;

  // حذف سجل دفعة: عكسها على دينها حرفياً.
  if (jsTruthy(r['isDebtPayment']) && jsTruthy(r['debtId'])) {
    final debt0 = repos.debts.getById('${r['debtId']}');
    if (debt0 != null) {
      final debt = Map<String, Object?>.from(debt0);
      final recAmt = jsNumOr0(r['amount']);
      final ip = debt['type'] == 'prosthetic';
      num fullPayAmt = recAmt;
      final insts = [...?(debt['installments'] as List?)];
      JMap? inst;
      for (final x in insts) {
        if (x is Map && x['recordId'] == id) {
          inst = Map<String, Object?>.from(x);
          break;
        }
      }
      inst ??= () {
        for (final x in insts) {
          if (x is Map && x['date'] == r['date']) {
            return Map<String, Object?>.from(x);
          }
        }
        return null;
      }();
      if (inst != null) fullPayAmt = jsNumOr0(inst['amount']);
      var paid =
          (jsNumOr0(debt['paidAmount']) - fullPayAmt).clamp(0, double.infinity);
      final totalDebt =
          jsNumOr0(jsOr(debt['totalAmount'], debt['total']));
      var remaining =
          (totalDebt - paid).clamp(0, double.infinity);
      String status;
      if (remaining > 0.01) {
        status = paid > 0.01 ? 'partial' : 'unpaid';
      } else {
        status = 'paid';
        remaining = 0;
      }
      debt['paidAmount'] = paid;
      debt['remaining'] = remaining;
      debt['status'] = status;
      if (ip) {
        final labVal = jsNumOr0(debt['labValue']);
        final labPaid = paid < labVal ? paid : labVal;
        debt['labPaid'] = labPaid;
        final profit = (paid - labPaid).clamp(0, double.infinity);
        final dp = jsNumOr0(buildRateSnapshot(config,
            clinic: '${debt['clinic'] ?? ''}', isPros: true)['doctorPct']);
        debt['doctorEarned'] = profit * (dp / 100);
      }
      // إزالة القسط المطابق.
      var idx = -1;
      for (var i = 0; i < insts.length; i++) {
        final x = insts[i];
        if (x is Map && x['recordId'] == id) {
          idx = i;
          break;
        }
      }
      if (idx < 0) {
        for (var i = 0; i < insts.length; i++) {
          final x = insts[i];
          if (x is Map &&
              x['date'] == r['date'] &&
              jsNumOr0(x['amount']) == fullPayAmt) {
            idx = i;
            break;
          }
        }
      }
      if (idx >= 0) insts.removeAt(idx);
      debt['installments'] = insts;
      repos.debts.upsertLocal(debt);
      touched++;
    }
  }

  // حذف أصل دين: دينه المرتبط + كل دفعاته.
  if (jsTruthy(r['isDebt'])) {
    JMap? debt;
    for (final d in repos.debts.getAll()) {
      if (d['recordId'] == id) {
        debt = d;
        break;
      }
    }
    if (debt != null) {
      for (final rec in repos.records.getAll()) {
        if (jsTruthy(rec['isDebtPayment']) &&
            rec['debtId'] == debt['id']) {
          repos.records.delete('${rec['id']}');
          touched++;
        }
      }
      repos.debts.delete('${debt['id']}');
      touched++;
    }
  }

  repos.records.delete(id);
  return touched + 1;
}


/// deletePatientData — الحذف السلطوي الشامل حرفياً: كل سجلات/تركيبات/
/// ديون/مواعيد المريض + صفوف أشعته + صف المرضى + الكتل المسماة في
/// config (المعلومات الطبية، خطط العلاج، مفاتيح الأشعة وبياناتها).
///
/// م142 — تعطّف الحذف على كائنات R2 والحصة: كل مفتاح أشعة يُزال من المعرض
/// يُختَم بحارس المحذوف (`markXrayDeleted`) كي لا يبعثه جهازٌ نظير عبر دمج
/// الإعدادات، ويُصفّ في طابور حذف R2 (`enqueuePendingDelete`)، وتُحرَّر
/// مساحته من الحصة (`meter.removeKey`). المنادي يصرّف الطابور فوراً عند
/// الاتصال (drainNow) ويبلّغ الخادم. [db] و[meter] مطلوبان لهذا التعطّف.
int deletePatientData(
  Repositories repos,
  JMap config, {
  required String name,
  String clinic = '',
  // م-عزل الهوية — [identity] (p:هاتف / none) و[phone] يحصران الحذف
  // بهوية الملف المفتوح: سميُّ المريض (بهاتف مختلف) لا تُمس بياناته.
  // فارغةٌ = حذف كل صفوف الاسم في العيادة (السلوك القائم — م35).
  String identity = '',
  String phone = '',
  required LocalDb db,
  required StorageMeter meter,
}) {
  final nm = name.trim();
  if (nm.isEmpty) return 0;
  final cl = clinic.trim();
  final idPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
  // م181 — نطاق الهوية بالحلّال الموروث: دفعةُ ما قبل م181 بلا هاتفٍ
  // تتبع دينَها فتُحذف مع صاحبها (كانت تفلت من الحذف فتبقى شبحاً يتيماً).
  final idIdx = IdentityIndex(
    repos.records.getAll(),
    repos.prosthetics.getAll(),
    repos.debts.getAll(),
  );
  // م35 (قرار مالك): [clinic] غير الفارغة تحصر الحذف بصفوف تلك العيادة
  // — مريض العيادة الأخرى بنفسه الاسم لا يُمس. الصف **بلا عيادة** (إرث)
  // يظهر في كل الملفات فيُحذف مع أي منها (سياسة الأشعة نفسها).
  // م-عزل الهوية — الهوية غير الفارغة تحصر أكثر: صفوف تلك الهوية وحدها.
  bool inScope(JMap r) {
    if ('${r['name'] ?? ''}'.trim() != nm) return false;
    if (!rowMatchesIdentity(r, identity, idIdx)) return false;
    if (cl.isEmpty) return true;
    final rc = '${r['clinic'] ?? ''}'.trim();
    return rc.isEmpty || rc == cl;
  }
  var touched = 0;
  void wipe(List<JMap> rows, void Function(String) del) {
    for (final r in rows) {
      if (inScope(r)) {
        del('${r['id']}');
        touched++;
      }
    }
  }

  wipe(repos.records.getAll(), repos.records.delete);
  wipe(repos.prosthetics.getAll(), repos.prosthetics.delete);
  wipe(repos.debts.getAll(), repos.debts.delete);
  wipe(repos.appointments.getAll(), repos.appointments.delete);
  // الأشعة: صور العيادة + غير الموسومة (تظهر في هذا الملف فتُحذف معه).
  // م-عزل الهوية — صفوف الأشعة بهوية الملف وحدها (getByClinicPatient
  // بالهاتف يطابق المعرّف الهوياتي مع تراجعٍ اسمي للصفوف عديمة المعرّف).
  final xrayRows = identity.isEmpty && idPhone.isEmpty
      ? repos.xrays.getByPatient(nm)
      : repos.xrays.getByClinicPatient(cl.isEmpty ? null : cl, nm,
          phone: idPhone);
  for (final x in xrayRows) {
    final xc = '${x['clinic_id'] ?? x['clinic'] ?? ''}'.trim();
    if (cl.isEmpty || xc.isEmpty || xc == cl) {
      repos.xrays.delete('${x['id']}');
      touched++;
    }
  }
  // صف المريض (معرفه اسمه — مشترك): يُحذف فقط إن لم يبق له أثر في أي
  // عيادة أخرى بعد اكتساح العيادة الحالية.
  final remains = cl.isNotEmpty &&
      [
        ...repos.records.getAll(),
        ...repos.prosthetics.getAll(),
        ...repos.debts.getAll(),
      ].any((r) => '${r['name'] ?? ''}'.trim() == nm);
  final pat = repos.patients.getById(nm);
  if (pat != null && !remains) {
    repos.patients.delete(nm);
    touched++;
  }

  // v29 — مراحل خطة العلاج صفوف مستقلة: تُختم بشواهد قبور (حذف حتمي).
  // م97 — يشمل مفتاح الهوية (هاتف صف المريض) ومفتاح العيادة والإرث.
  TreatmentPlanStore(repos.settings).removeAllFor(nm, cl,
      phone: '${pat?['phone'] ?? ''}'.replaceAll('null', ''));

  // الكتل المسماة في config — م35: يُزال مدخل (اسم|عيادة)، والإرث
  // بالاسم فقط إن لم يبق للمريض أثر في عيادة أخرى.
  var cfg = Map<String, Object?>.from(config);
  var changed = false;
  for (final key in ['patientMedical', 'treatmentPlans']) {
    final before = cfg[key];
    if (before is! Map) continue;
    final after = clinicScopedRemove(before, nm, cl,
        removeLegacy: cl.isEmpty || !remains);
    if (after.length != before.length) {
      cfg[key] = after;
      changed = true;
      // v28 — شاهد حذف صريح لكل مدخل أُزيل: يميّز الحذف المتعمّد عن
      // «مدخل أضافه الجهاز الآخر» فلا يعود بالدمج ولا يُمحى غيره.
      for (final k in before.keys) {
        if (!after.containsKey(k)) {
          cfg = markMapKeyDeleted(cfg, key, '$k');
        }
      }
    }
  }
  // مفاتيح أشعة المريض xrayKeys/xrayMeta (بنية الأصل: xrays{name:[keys]})
  // + معرض patientXrays — م35: عند حذف عيادة واحدة تُزال مفاتيح صورها
  // (الموسومة بها أو غير الموسومة) فقط، ويبقى معرض العيادة الأخرى.
  bool keyInScope(Object? k) {
    if (cl.isEmpty) return true;
    final metaV = cfg['xrayMeta'];
    final m = metaV is Map ? metaV['$k'] : null;
    final kc = m is Map ? '${m['clinic'] ?? ''}'.trim() : '';
    return kc.isEmpty || kc == cl;
  }

  // م142 — اتحاد مفاتيح الأشعة المُزالة عبر المعرضين (xrays + patientXrays):
  // تُختَم وتُصفّ لحذف R2 وتُحرَّر حصتها بعد اكتمال تجريد config.
  // م-عزل الهوية — يُعالَج سطلا المعرض: سطل الهوية «اسم|هاتف» (صورُ هذه
  // الهوية الجديدة) وسطل الاسم القديم (المشترك — القديمة). حين لا هوية،
  // يبقى سطل الاسم وحده (السلوك القائم).
  final buckets = <String>{
    nm,
    if (idPhone.isNotEmpty) xrayGalleryKey(nm, phone: idPhone),
  };
  final removedXrayKeys = <String>{};
  for (final galleryKey in const ['xrays', 'patientXrays']) {
    if (cfg[galleryKey] is! Map) continue;
    final xr = Map<String, Object?>.from(cfg[galleryKey] as Map);
    var galleryChanged = false;
    for (final bucket in buckets) {
      if (!xr.containsKey(bucket)) continue;
      final keys = [...?(xr[bucket] as List?)];
      final removed = [
        for (final k in keys)
          if (keyInScope(k)) k,
      ];
      final kept = [
        for (final k in keys)
          if (!keyInScope(k)) k,
      ];
      if (kept.isEmpty) {
        xr.remove(bucket);
      } else {
        xr[bucket] = kept;
      }
      if (cfg['xrayMeta'] is Map && removed.isNotEmpty) {
        final meta = Map<String, Object?>.from(cfg['xrayMeta'] as Map);
        for (final k in removed) {
          meta.remove('$k');
        }
        cfg['xrayMeta'] = meta;
      }
      for (final k in removed) {
        if (k is String && k.isNotEmpty) removedXrayKeys.add(k);
      }
      galleryChanged = true;
    }
    if (galleryChanged) {
      cfg[galleryKey] = xr;
      changed = true;
    }
  }
  if (changed) repos.settings.set('app.config', cfg);
  // م142 — تعطّف R2 + الحصة + حارس المحذوف على كل مفتاح أشعة أُزيل. حرجٌ:
  // markXrayDeleted لكل مفتاح كي لا يبعثه جهازٌ نظير عبر دمج الإعدادات.
  for (final key in removedXrayKeys) {
    markXrayDeleted(db, key);
    enqueuePendingDelete(db, key);
    meter.removeKey(key);
  }
  return touched;
}
