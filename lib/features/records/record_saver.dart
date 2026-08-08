/// ============================================================================
///  حفظ السجل — نقل حرفي لمنطق saveRec في AddRecord.vue (مسار الإنشاء)
/// ============================================================================
///
///  نفس البنية المالية بايتاً ببايت: سجل عادي أو تركيبة (isProsthetic بنفس
///  التعبير النمطي)، لقطة نسب مجمّدة عند الإنشاء، دينٌ مرتبط عند «دين» بنوع
///  regular/prosthetic مع الدفعة الأولى (قسط + سجل isDebtPayment بخدمة
///  «دفعة أولى (دين)» أو «تركيبات (دفعة أولى)») وحسابات labPaid/doctorEarned
///  للتركيبات — والكتابة عبر upsertLocal فتُختم dirty+HLC وتدخل طابور
///  المزامنة. مسار التعديل (editId) يُنقل لاحقاً؛ هذا مسار الإنشاء الكامل.
library;

import '../../core/money.dart' show quantize;
import '../../core/utils/js_compat.dart';
import '../../core/utils/uid.dart';
import '../../data/rates/rate_snapshot.dart';
import '../../data/repositories/repositories.dart';
import '../../data/sync/feature_flags.dart';
import '../patients/archive_store.dart' show PatientArchiveStore;
import '../staff/staff_session.dart' show staffCreatedBy;


typedef JMap = Map<String, Object?>;

/// نقل utils/format.isProsthetic حرفياً.
final _prosRe =
    RegExp('(تركيب|بروتيز|جسر|طقم|crown|prosth)', caseSensitive: false);
bool isProsthetic(String? service) =>
    (service != null && _prosRe.hasMatch(service)) || service == 'تركيبات';

/// مدخل تحليلٍ مخبري مرافق للزيارة — نظام «التحاليل» (دخل مخبري خاص
/// بالعيادة، معزول مالياً عن كل شيء). عند تفعيله على النموذج يُكتب صفُّ
/// تحليلٍ موسومٌ [isAnalysis]=1 في جدول السجلات نفسه — لا جدول جديد.
class AnalysisInput {
  const AnalysisInput({
    required this.name,
    required this.price,
    required this.payment,
  });

  /// اسم التحليل (من قائمة التحاليل المفعّلة في الإعدادات).
  final String name;

  /// قيمة التحليل (حرة على النموذج).
  final num price;

  /// طريقة الدفع (كاش/تحويل) — معزولة عن دفع الزيارة نفسها.
  final String payment;
}

class SaveRecordInput {
  const SaveRecordInput({
    required this.name,
    required this.date,
    required this.amount,
    required this.clinic,
    required this.service,
    required this.payment,
    this.isDebt = false,
    this.firstPay = 0,
    this.phone = '',
    this.phone2 = '',
    this.notes = '',
    this.labValue = 0,
    this.prosType = '',
    this.prosUnits = 1,
    this.prosUnitPrice = 0,
    this.labStatus = '',
    this.labName = '',
    this.report,
    this.incomeDate = '',
    this.analysis,
  });

  final String name;
  final String date;
  final num amount;
  final String clinic;
  final String service;
  final String payment;
  final bool isDebt;
  final num firstPay;
  final String phone;
  final String phone2;
  final String notes;
  final num labValue;
  final String prosType;
  final num prosUnits;
  final num prosUnitPrice;
  final String labStatus;
  final String labName;
  final JMap? report;

  /// م101 — يوم احتساب الإيراد حين يختلف عن تاريخ السجل (فارغ = التاريخ
  /// نفسه): يقرؤه جدول دخل اليوم فلا يُحسب المبلغ في يومين.
  final String incomeDate;

  /// نظام «التحاليل» — تحليلٌ مخبري مرافق للزيارة (null = لا تحليل).
  /// يُكتب صفَّه المعزول في نفس معاملة الحفظ. **وضع التعديل يمرّره null**
  /// (لا يُعاد إنشاء التحليل عند استبدال السجل).
  final AnalysisInput? analysis;
}

class SaveRecordResult {
  const SaveRecordResult({
    required this.entryId,
    this.debtId,
    required this.isPros,
    required this.message,
  });

  final String entryId;
  final String? debtId;
  final bool isPros;
  final String message;
}

/// رسائل التحقق العربية نفسها (كانت toasts).
String? validateRecordInput(SaveRecordInput f) {
  if (f.name.trim().isEmpty) return 'يرجى إدخال اسم المريض';
  if (f.date.isEmpty) return 'يرجى اختيار التاريخ';
  if (f.amount.isNaN || f.amount <= 0) {
    return 'يرجى إدخال قيمة صحيحة أكبر من صفر';
  }
  if (f.clinic.isEmpty) return 'يرجى اختيار العيادة';
  if (f.service.isEmpty) return 'يرجى اختيار الخدمة';
  return null;
}

SaveRecordResult saveNewRecord(
  Repositories repos,
  JMap config,
  SaveRecordInput f,
) {
  final err = validateRecordInput(f);
  if (err != null) throw ArgumentError(err);

  final name = f.name.trim();
  final nowMod = jsNow();
  // م101 — يوم الاحتساب يُخزَّن فقط حين يخالف تاريخ السجل.
  final String? incomeDay =
      (f.incomeDate.isNotEmpty && f.incomeDate != f.date)
          ? f.incomeDate
          : null;
  final ip = isProsthetic(f.service);
  final pid = isPhoneIdentityEnabled()
      ? patientKeyFor(name: name, phone: f.phone)
      : null;

  // م85 — تُضبَط المبالغ على القرش عند الكتابة فلا يُخزَّن غبارٌ دون القرش.
  final lab = ip ? quantize(f.labValue) : 0.0;
  final amount = quantize(f.amount);
  final net = (amount - lab) > 0 ? quantize(amount - lab) : 0.0;

  late String entryId;
  String? debtId;

  // دفعة صفر/ج — العملية ذرّية: التركيبة/السجل + الدين + سجل الدفعة الأولى
  // + ربط المريض إما تُكتب كلها أو لا شيء. انهيار في المنتصف كان يترك ديناً
  // بلا سجل دفعته أو دخلاً مختلاً بلا مسار إصلاح. الركلة تُطلق مرة واحدة
  // بعد الالتزام.
  repos.db.transaction(() {
  if (ip) {
    // ── تركيبة ──
    entryId = genId();
    final prosSnap = buildRateSnapshot(config,
        clinic: f.clinic, service: f.service, isPros: true);
    final pct = jsNumOr0(prosSnap['doctorPct']);
    // الحصّتان بالقروش الصحيحة، والعيادة بالطرح ⇒ مجموعهما = net بالضبط.
    final docShare = quantize(net * (pct / 100));
    final clinShare = net - docShare;
    repos.prosthetics.upsertLocal({
      'id': entryId,
      'createdBy': ?staffCreatedBy(), // م120 — هوية المُدخِل
      'date': f.date,
      'name': name,
      'patient_name': name,
      'total': amount,
      'labValue': lab,
      'patient_id': ?pid,
      '_rateSnapshot': prosSnap,
      'doctorShare': docShare,
      'clinicShare': clinShare,
      'phone': f.phone.isEmpty ? null : f.phone,
      'phone2': f.phone2.isEmpty ? null : f.phone2,
      'payment': f.isDebt ? 'دين' : f.payment,
      'incomeDate': ?incomeDay,
      'clinic': f.clinic,
      'clinic_id': f.clinic,
      // م76 — رقمٌ لا منطقي. كان هنا `f.isDebt` خاماً، و`isDebt` **ليس
      // عموداً مرقّى في `prosthetics`** (بينما هو مرقّى في `records` —
      // انظر السطر النظير في مسار السجل العادي أدناه)، فكان
      // `prepareForStorage` يسلكه إلى كتلة `data` عبر jsonEncode فتُخزَّن
      // `"isDebt": false` منطقيةً وتُدفع كما هي إلى الخادم. المُقيّد
      // `_bindable` ينقذ مسار الأعمدة صامتاً ولا منقذ لمسار الكتلة:
      // حقلٌ واحد، مسارا تخزين، وناجٍ واحد.
      'isDebt': f.isDebt ? 1 : 0,
      '_t': 'p',
      '_activityAt': nowMod,
      if (f.labStatus.isNotEmpty) 'labStatus': f.labStatus,
      if (f.labName.isNotEmpty) 'labName': f.labName,
      if (f.prosType.isNotEmpty) 'prosType': f.prosType,
      'prosUnits': f.prosUnits,
      'prosUnitPrice': f.prosUnitPrice,
      if (f.report != null) 'report': f.report,
    });

    if (f.isDebt) {
      final firstPay =
          quantize(jsNumOr0(f.firstPay).clamp(0, amount.toDouble()));
      debtId = genId();
      final toLab = firstPay < lab ? firstPay : lab;
      final toProfit = firstPay - toLab;
      final initRem =
          (amount - firstPay) > 0 ? quantize(amount - firstPay) : 0.0;
      final isFull = initRem <= 0.01;
      final installments = <JMap>[];
      String? firstPayRecId;
      if (firstPay > 0) {
        firstPayRecId = genId();
        installments.add({
          'id': genId(),
          'createdBy': ?staffCreatedBy(), // م120
          'amount': firstPay,
          'date': f.date,
          'incomeDate': ?incomeDay,
          'payment': f.payment,
          'recordId': firstPayRecId,
          'createdAt': nowMod,
        });
      }
      repos.debts.upsertLocal({
        'id': debtId,
        'createdBy': ?staffCreatedBy(), // م120
        'date': f.date,
        'name': name,
        'patient_name': name,
        'phone': f.phone,
        'notes': f.notes,
        'patient_id': ?pid,
        'type': 'prosthetic',
        'status': isFull ? 'paid' : (firstPay > 0 ? 'partial' : 'unpaid'),
        'total': amount,
        'totalAmount': amount,
        'total_amount': amount,
        'labValue': lab,
        'labPaid': toLab,
        'paidAmount': firstPay,
        'paid_amount': firstPay,
        'remaining': initRem,
        'doctorEarned': toProfit > 0 ? quantize(toProfit * (pct / 100)) : 0,
        'payment': f.payment,
        'clinic': f.clinic,
        'clinic_id': f.clinic,
        'service': f.service,
        'prostheticId': entryId,
        'installments': installments,
        // م103 — نسخة تقرير الأسنان على الدين (تكافؤ Vue): ملف المريض يخفي
        // صف أصل الدين (isDebt/التركيبة الدَّينية) ويقرأ أسنان البطاقة
        // الظاهرة من الدين أولاً (_resolveTeeth) — بلا هذه النسخة كانت
        // أسنان المعالجات الدَّينية تُحفظ على الصف المخفي وحده فتبدو
        // «مختفية» من الملف (بلاغ ما بعد 102، مثبت من صفوف الخادم الحي).
        if (f.report != null) 'report': f.report,
        '_t': 'd',
      });
      if (firstPay > 0) {
        repos.records.upsertLocal({
          'id': firstPayRecId,
          'createdBy': ?staffCreatedBy(), // م120
          'date': f.date,
          'name': name,
          'patient_name': name,
          'amount': firstPay,
          '_fullAmount': firstPay,
          '_labAmount': toLab,
          '_docAmount': toProfit > 0 ? quantize(toProfit * (pct / 100)) : 0,
          '_rateSnapshot': prosSnap,
          'clinic': f.clinic,
          'clinic_id': f.clinic,
          'service': 'تركيبات (دفعة أولى)',
          'payment': f.payment,
          'incomeDate': ?incomeDay,
          'isDebt': 0,
          'isPros': 0,
          'isDebtPayment': 1,
          'debtId': debtId,
          'debtPaymentType': isFull ? 'full' : 'partial',
          '_t': 'r',
          '_activityAt': nowMod,
        });
      }
    }
  } else {
    // ── سجل عادي ──
    entryId = genId();
    repos.records.upsertLocal({
      'id': entryId,
      'createdBy': ?staffCreatedBy(), // م120
      'date': f.date,
      'name': name,
      'patient_name': name,
      'amount': amount,
      'patient_id': ?pid,
      '_rateSnapshot': buildRateSnapshot(config,
          clinic: f.clinic, service: f.service, isPros: false),
      'clinic': f.clinic,
      'clinic_id': f.clinic,
      'service': f.service,
      'payment': f.isDebt ? 'دين' : f.payment,
      'incomeDate': ?incomeDay,
      'isDebt': f.isDebt ? 1 : 0,
      'isPros': 0,
      'phone': f.phone.isEmpty ? null : f.phone,
      'phone2': f.phone2.isEmpty ? null : f.phone2,
      'notes': f.notes.isEmpty ? null : f.notes,
      '_t': 'r',
      '_activityAt': nowMod,
      if (f.report != null) 'report': f.report,
    });

    if (f.isDebt) {
      final firstPay =
          quantize(jsNumOr0(f.firstPay).clamp(0, amount.toDouble()));
      debtId = genId();
      final initRem =
          (amount - firstPay) > 0 ? quantize(amount - firstPay) : 0.0;
      final isFull = initRem <= 0.01;
      final installments = <JMap>[];
      String? firstPayRecId;
      if (firstPay > 0) {
        firstPayRecId = genId();
        installments.add({
          'id': genId(),
          'createdBy': ?staffCreatedBy(), // م120
          'amount': firstPay,
          'date': f.date,
          'incomeDate': ?incomeDay,
          'payment': f.payment,
          'recordId': firstPayRecId,
          'createdAt': nowMod,
        });
      }
      repos.debts.upsertLocal({
        'id': debtId,
        'createdBy': ?staffCreatedBy(), // م120
        'date': f.date,
        'name': name,
        'patient_name': name,
        'phone': f.phone,
        'notes': f.notes,
        'patient_id': ?pid,
        'type': 'regular',
        'status': isFull ? 'paid' : (firstPay > 0 ? 'partial' : 'unpaid'),
        'totalAmount': amount,
        'total': amount,
        'total_amount': amount,
        'paidAmount': firstPay,
        'paid_amount': firstPay,
        'remaining': initRem,
        'payment': f.payment,
        'clinic': f.clinic,
        'clinic_id': f.clinic,
        'service': f.service,
        'recordId': entryId,
        'installments': installments,
        // م103 — نسخة تقرير الأسنان على الدين (انظر توأمها في فرع
        // التركيبات أعلاه): الصف الظاهر بالملف يقرأ من الدين أولاً.
        if (f.report != null) 'report': f.report,
        '_t': 'd',
      });
      if (firstPay > 0) {
        repos.records.upsertLocal({
          'id': firstPayRecId,
          'createdBy': ?staffCreatedBy(), // م120
          'date': f.date,
          'name': name,
          'patient_name': name,
          'amount': firstPay,
          '_fullAmount': firstPay,
          '_rateSnapshot': buildRateSnapshot(config,
              clinic: f.clinic, service: f.service, isPros: false),
          'clinic': f.clinic,
          'clinic_id': f.clinic,
          'service': 'دفعة أولى (دين)',
          'payment': f.payment,
          'incomeDate': ?incomeDay,
          'isDebt': 0,
          'isPros': 0,
          'isDebtPayment': 1,
          'debtId': debtId,
          'debtPaymentType': isFull ? 'full' : 'partial',
          '_t': 'r',
          '_activityAt': nowMod,
        });
      }
    }
  }

  // ── نظام «التحاليل» — صفُّ التحليل المعزول ──
  // يُكتب داخل نفس المعاملة الذرّية بعد تحديد entryId وقبل ربط المريض،
  // فينجو أو يفشل مع الزيارة معاً. الصف موسومٌ isAnalysis:1 (عددٌ لا
  // منطقيّ — تُقرؤه الحرّاس المالية بـ jsTruthy) مع حرّاس isDebt/isPros/
  // isDebtPayment صفراً (فلا يسلكه أي مسار دين/تركيبة/دفعة) وservice
  // 'تحاليل'. analysisOf يربطه بسجل الزيارة (entryId) — والعمود name/
  // patient_id يجمعانه للمريض عرضاً بلا أي أثرٍ مالي (كل الحرّاس التسعة
  // تستبعده من الأرباح والخزينة والأرشيف وعدّادات المريض).
  final an = f.analysis;
  if (an != null) {
    final aPrice = quantize(an.price);
    if (aPrice > 0) {
      final aPay = (an.payment == 'كاش' || an.payment == 'تحويل')
          ? an.payment
          : 'كاش';
      repos.records.upsertLocal({
        'id': genId(),
        'createdBy': ?staffCreatedBy(), // م120 — هوية المُدخِل
        'date': f.date,
        'name': name,
        'patient_name': name,
        'amount': aPrice,
        'patient_id': ?pid,
        'clinic': f.clinic,
        'clinic_id': f.clinic,
        'service': 'تحاليل',
        'payment': aPay,
        'incomeDate': ?incomeDay,
        // حرّاس العزل — عددٌ لا منطقيّ (توأم isDebt/isPros في السجل العادي).
        'isAnalysis': 1,
        'isDebt': 0,
        'isPros': 0,
        'isDebtPayment': 0,
        'analysisName': an.name,
        'analysisOf': entryId,
        '_t': 'r',
        '_activityAt': nowMod,
      });
    }
  }

  // ── ربط المريض (توأم linkRecordToPatient): آخر زيارة = أحدث تاريخ ──
  // م-عزل الهوية — **صفُّ المرضى بمعرّف هوية الهاتف عند وجوده**: سميّان
  // بهاتفين مختلفين صفّان منفصلان في جدول المرضى (`p:هاتف:اسم`) فلا يكتب
  // أحدهما فوق هاتف الآخر ولا آخر زيارته. `name` يبقى عموداً.
  //
  // **حصريّة الهاتف مقصودة**: المميِّز الذي يفصل السميّين هو الهاتف وحده.
  // مريضٌ بلا هاتف (معرّفه `n:اسم` أو TRIM(name) مع PHONE_IDENTITY OFF)
  // لا سميَّ هاتفيّاً له، فيبقى صفُّه بمعرّف الاسم — كي لا ينكسر البحث
  // `patients.getById(name)` المنتشر (تعبئة الهاتف/آخر زيارة). فمع OFF
  // (كل الاختبارات القديمة) لا يتغيّر أي شيء حرفياً.
  final rowPid = resolvePid({
    'name': name,
    'phone': f.phone,
    'patient_id': pid,
  });
  final rowId =
      (rowPid != null && rowPid.startsWith('p:')) ? rowPid : name;
  final existing = repos.patients.getById(rowId);
  final prevVisit = '${existing?['last_visit'] ?? ''}';
  repos.patients.upsertLocal({
    ...?existing,
    'id': rowId,
    'name': name,
    if (f.phone.isNotEmpty) 'phone': f.phone,
    'last_visit':
        (prevVisit.isEmpty || f.date.compareTo(prevVisit) > 0)
            ? f.date
            : prevVisit,
    'patient_id': ?pid,
  });
  }); // repos.db.transaction

  // م75 — العودة التلقائية (قرار المالك): مريض مؤرشف حصل على معالجة/تركيبة
  // جديدة يعود نشطاً بحكم الفعل، فلا يحتاج الطبيب أن يتذكّر من أرشف. بعد
  // الالتزام لا داخله: إلغاء الأرشفة كتابةُ إعدادات مستقلة، وإبقاؤها خارج
  // معاملة السجل يمنع أي تشابك، ولا تفعل شيئاً إن لم يكن مؤرشفاً.
  PatientArchiveStore(repos.settings).autoReactivateOnActivity(name, f.clinic);

  var msg = ip ? 'تم حفظ التركيبة' : 'تم حفظ السجل';
  if (f.isDebt) msg += ' + تم إنشاء دين جديد مرتبط';
  return SaveRecordResult(
      entryId: entryId, debtId: debtId, isPros: ip, message: msg);
}
