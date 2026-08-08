/// إجراءات الديون — نقل حرفي لمنطق DebtsTab.vue المالي:
///
///  • **confirmInst** (سداد قسط بتاريخ وطريقة دفع): للتركيبات يقسم القسط
///    مخبراً أولاً (toLab = min(القسط، متبقي المخبر)) ثم ربحاً، بنسبة
///    التركيبات **للعيادة** من اللقطة (لا العامة) — يحدّث labPaid
///    وdoctorEarned، **وينشئ سجل الدفعة المرتبط** بخدمة «دفعة تركيبات — X»
///    وحقوله _fullAmount/_labAmount/_docAmount ولقطة النسب — وهو السجل الذي
///    تتغذى عليه الخزينة والأرشيف (فجوة أصلحتها هذه الجولة: السداد السابق
///    لم يكن ينشئه). العادي: سجل «دفعة دين — X» بلقطته. paid/partial بحد
///    0.01 ورسائل التحقق العربية نفسها.
///  • **previewInst**: معاينة تقسيم القسط (مخبر/ربح/طبيب/عيادة).
///  • **confirmEditDebt**: تعديل اسم/هاتف/ملاحظات/إجمالي مع إعادة اشتقاق
///    المتبقي والحالة، وانعكاس الإجمالي الجديد على التركيبة (بحصص لقطتها)
///    أو على السجل الأصلي.
///  • **delDebt**: حذف تعاقبي — شواهد لسجلات الدفعات والسجل الأصلي
///    والتركيبة ثم الدين نفسه.
///  • **forgiveDebt (مسامحة)**: الإجمالي = المدفوع فعلياً والمتبقي 0
///    والحالة مسدد، مع انعكاس الإجمالي الجديد على التركيبة (حصص من نسبة
///    لقطتها المجمّدة، مقصوصة عند الصفر) وعلى مبلغ السجل الأصلي.
///  • **cancelDebtInstallment (إلغاء دفعة)**: عكس المبالغ والحالة
///    وإعادة اشتقاق labPaid/doctorEarned بنسبة تركيبات العيادة، شاهدة
///    حذف ناعمة للقسط (تحافظ على ترقيم «دفعة N»)، وحذف سجل الدفعة
///    المرتبط (بمعرّفه وإلا بتاريخه).
library;

import '../../core/money.dart' show quantize;
import '../../core/utils/js_compat.dart';
import '../../core/utils/uid.dart';
import '../../data/rates/rate_snapshot.dart';
import '../../data/repositories/repositories.dart';
import '../../data/sync/merge/recompute.dart' show recomputeDebts;
import 'treasury_logic.dart' show activeInstallments;
import '../staff/staff_session.dart' show staffCreatedBy;

typedef JMap = Map<String, Object?>;

class InstallmentPreview {
  const InstallmentPreview({
    required this.toLab,
    required this.toProfit,
    required this.docShare,
    required this.clinShare,
  });

  final num toLab;
  final num toProfit;
  final num docShare;
  final num clinShare;
}

num _labRemaining(JMap debt) => debt['type'] == 'prosthetic'
    ? (jsNumOr0(debt['labValue']) - jsNumOr0(debt['labPaid']))
        .clamp(0, double.infinity)
    : 0;

/// previewInst — بنسبة تركيبات العيادة من اللقطة (إصلاح #3 الأصلي).
InstallmentPreview previewInstallment(JMap config, JMap debt, num amount) {
  final ip = debt['type'] == 'prosthetic';
  final labRem = ip ? _labRemaining(debt) : 0;
  final toLab = ip ? (amount < labRem ? amount : labRem) : 0;
  final toProfit = amount - toLab;
  final dp = ip
      ? jsNumOr0(buildRateSnapshot(config,
          clinic: '${debt['clinic'] ?? ''}', isPros: true)['doctorPct'])
      : jsNumOr0(jsOr(config['doctorPct'], 50));
  final docShare = quantize(toProfit * (dp / 100));
  return InstallmentPreview(
    toLab: quantize(toLab),
    toProfit: quantize(toProfit),
    docShare: docShare,
    // العيادة بالطرح ⇒ docShare + clinShare = toProfit بالضبط بلا غبار.
    clinShare: quantize(toProfit) - docShare,
  );
}

class PayInstallmentResult {
  const PayInstallmentResult({required this.isFull, required this.payRecordId});

  final bool isFull;
  final String payRecordId;
}

/// confirmInst حرفياً — يحدّث الدين **وينشئ سجل الدفعة المرتبط**.
PayInstallmentResult payDebtInstallment(
  Repositories repos,
  JMap config,
  JMap debtRow, {
  required num amount,
  required String date,
  required String payment,
  String incomeDate = '',
}) {
  // ignore: parameter_assignments — تُضبَط على القرش مرّة واحدة (م85).
  // دفعة صفر/أ — منع تدمير دفعة مسجّلة (عيب اللقطة القديمة):
  //
  // الدالة كانت تعمل على `debtRow` التي التقطتها البطاقة وقت البناء، ثم
  // تكتبها بـ upsertLocal بلا `base:`. فإن وصلت دفعة من جهاز آخر أثناء فتح
  // النافذة (ثوانٍ تتخللها دورة مزامنة) كانت تُدهَس نهائياً ويولّد المحرك
  // لها شاهدة حذف تنشر الفقدان لكل الأجهزة — أُثبت باختبار: دفعة 400
  // تختفي والمريض يُطالَب بها ثانيةً.
  //
  // الإصلاح: (1) نعيد قراءة الصف الطازج فنرى أي دفعة بعيدة وصلت،
  // (2) نُلحق الدفعة الجديدة بالقائمة الطازجة لا القديمة، (3) نشتق
  // المبالغ من القائمة الكاملة عبر recomputeDebts النقي، (4) نمرّر
  // `base:` فيدمج المحرك القوائم بالمعرّف — فتنجو الدفعتان معاً حتى لو
  // وصلت ثالثة في النافذة الضيقة بين القراءة والكتابة.
  final debtId = '${debtRow['id'] ?? ''}';
  final stored = debtId.isEmpty ? null : repos.debts.getById(debtId);
  final base = Map<String, Object?>.from(stored ?? debtRow);
  // م85 — الدفعة مضبوطة على القرش عند الكتابة.
  amount = quantize(amount);
  final debt = Map<String, Object?>.from(stored ?? debtRow);
  if (amount.isNaN || amount <= 0) {
    throw ArgumentError('يرجى إدخال قيمة دفعة صحيحة');
  }
  if (date.isEmpty) {
    throw ArgumentError('يرجى اختيار تاريخ الدفعة');
  }
  if (amount > jsNumOr0(debt['remaining']) + 0.01) {
    throw ArgumentError('الدفعة أكبر من المتبقي (${jsNumOr0(debt['remaining'])})');
  }

  final ip = debt['type'] == 'prosthetic';
  final labRem = ip ? _labRemaining(debt) : 0;
  final toLab = ip ? (amount < labRem ? amount : labRem) : 0;
  final toProfit = amount - toLab;
  final dp = ip
      ? jsNumOr0(buildRateSnapshot(config,
          clinic: '${debt['clinic'] ?? ''}', isPros: true)['doctorPct'])
      : jsNumOr0(jsOr(config['doctorPct'], 50));

  // دفعة صفر/ج — سجل الدفعة والدين يُكتبان ذرّياً: لا سجلَّ دفعةٍ يتيماً
  // ولا ديناً مدفوعاً بلا أثر خزينة عند انهيار بينهما.
  // م101 — يوم الاحتساب يُخزَّن فقط حين يخالف تاريخ الدفعة.
  final String? incomeDay =
      (incomeDate.isNotEmpty && incomeDate != date) ? incomeDate : null;
  return repos.db.transaction(() {
  final installments = [...?(debt['installments'] as List?)];
  final instId = genId();
  final nowTs = jsNow();
  // متبقٍ متوقَّع لعنوان سجل الدفعة (كامل/جزئي) فقط — أما المبالغ المخزَّنة
  // فتشتقّها recomputeDebts من قائمة الأقساط الكاملة في النهاية.
  final predictedRemaining =
      (jsNumOr0(debt['remaining']) - amount).clamp(0, double.infinity);
  final isFull = predictedRemaining <= 0.01;

  final payRecId = genId();
  final service = '${debt['service'] ?? ''}';
  if (ip) {
    // labPaid تشتقّه recomputeDebts (min(labValue, paid)) من القائمة —
    // فلا نزيده يدوياً هنا كي لا يُحسب مرتين. doctorEarned مسارٌ تراكمي
    // لا تشتقّه recompute، فيبقى تراكمياً على القيمة الطازجة.
    final dProfit = toProfit > 0 ? quantize(toProfit * (dp / 100)) : 0;
    if (toProfit > 0) {
      debt['doctorEarned'] = jsNumOr0(debt['doctorEarned']) + dProfit;
    }
    final svcLabel =
        service.isNotEmpty ? 'دفعة تركيبات — $service' : 'تركيبات (دفعة دين)';
    installments.add({
      'id': instId, 'amount': amount, 'date': date, 'payment': payment,
      'createdBy': ?staffCreatedBy(), // م120 — هوية المُدخِل
      'incomeDate': ?incomeDay,
      'recordId': payRecId, 'createdAt': nowTs,
    });
    repos.records.upsertLocal({
      'id': payRecId, 'date': date, 'name': debt['name'],
      'createdBy': ?staffCreatedBy(), // م120
      'amount': amount, '_fullAmount': amount,
      '_labAmount': toLab, '_docAmount': dProfit,
      '_rateSnapshot': buildRateSnapshot(config,
          clinic: '${debt['clinic'] ?? ''}',
          service: service,
          isPros: true),
      'clinic': debt['clinic'], 'service': svcLabel, 'payment': payment,
      'incomeDate': ?incomeDay,
      // م76 — أرقام لا منطقيات. هذه الأعلام أعمدة مرقّاة في `records`
      // فكان `_bindable` ينقذها بالمصادفة لا بالتصميم؛ وإسقاط أيٍّ منها
      // من قائمة الأعمدة يوماً كان سيحوّلها صامتاً إلى منطقيات في كتلة
      // `data` — وهي علّة التركيبات نفسها بحذافيرها.
      'isDebt': 0, 'isPros': 0, 'isDebtPayment': 1,
      'debtId': debt['id'],
      'debtPaymentType': isFull ? 'full' : 'partial',
      '_activityAt': nowTs, '_t': 'r',
    });
  } else {
    final svcLabel = service.isNotEmpty ? 'دفعة دين — $service' : 'دفعة دين';
    installments.add({
      'id': instId, 'amount': amount, 'date': date, 'payment': payment,
      'createdBy': ?staffCreatedBy(), // م120 — هوية المُدخِل
      'incomeDate': ?incomeDay,
      'recordId': payRecId, 'createdAt': nowTs,
    });
    repos.records.upsertLocal({
      'id': payRecId, 'date': date, 'name': debt['name'],
      'createdBy': ?staffCreatedBy(), // م120
      'amount': amount, '_fullAmount': amount,
      '_rateSnapshot': buildRateSnapshot(config,
          clinic: '${debt['clinic'] ?? ''}',
          service: service,
          isPros: false),
      'clinic': debt['clinic'], 'service': svcLabel, 'payment': payment,
      'incomeDate': ?incomeDay,
      'isDebt': 0, 'isPros': 0, 'isDebtPayment': 1, // م76 — أرقام لا منطقيات
      'debtId': debt['id'],
      'debtPaymentType': isFull ? 'full' : 'partial',
      '_activityAt': nowTs, '_t': 'r',
    });
  }

  debt['installments'] = installments;
  // اشتقاق paidAmount/remaining/status (وlabPaid للتركيبات) من قائمة الأقساط
  // الكاملة — لا زيادة على لقطة. تمرير `base:` يجعل المحرك يدمج القوائم
  // بالمعرّف فتنجو أي دفعة بعيدة، ثم recompute يبقي المجاميع متسقة.
  final merged = recomputeDebts(debt);
  repos.debts.upsertLocal(merged, base: base);
  final storedNow = repos.debts.getById(debtId);
  final fullNow = storedNow == null
      ? isFull
      : '${storedNow['status']}' == 'paid';
  return PayInstallmentResult(isFull: fullNow, payRecordId: payRecId);
  }); // repos.db.transaction
}

/// confirmEditDebt حرفياً — التعديل مع الانعكاس على التركيبة/السجل الأصلي.
void editDebt(
  Repositories repos,
  JMap config,
  String debtId, {
  required String name,
  required String phone,
  required String notes,
  num? total,
}) {
  final existing = repos.debts.getById(debtId);
  if (existing == null) return;
  final debt = Map<String, Object?>.from(existing);
  final originalTotal = jsNumOr0(jsOr(debt['totalAmount'], debt['total']));

  if (name.trim().isNotEmpty) debt['name'] = name.trim();
  debt['phone'] = phone.trim();
  debt['notes'] = notes.trim();

  final totalChanged =
      total != null && total > 0 && total != originalTotal;
  if (totalChanged) {
    final paid = jsNumOr0(debt['paidAmount']);
    debt['totalAmount'] = total;
    debt['total'] = total;
    var remaining = (total - paid).clamp(0, double.infinity);
    if (remaining <= 0.01) {
      debt['status'] = 'paid';
      remaining = 0;
    } else if (paid > 0.01) {
      debt['status'] = 'partial';
    } else {
      debt['status'] = 'unpaid';
    }
    debt['remaining'] = remaining;
  }
  // دفعة صفر/ج — الدين وانعكاسه على التركيبة/السجل ذرّياً.
  repos.db.transaction(() {
  repos.debts.upsertLocal(debt);

  if (totalChanged &&
      debt['type'] == 'prosthetic' &&
      jsTruthy(debt['prostheticId'])) {
    final p = repos.prosthetics.getById('${debt['prostheticId']}');
    if (p != null) {
      final lab = jsNumOr0(debt['labValue']);
      final net = total - lab;
      // نسبة تركيبات العيادة من اللقطة المجمّدة، لا العامة (إصلاح #3).
      final snap = p['_rateSnapshot'];
      final snapPct =
          snap is Map ? jsNumber(snap['doctorPct']) : double.nan;
      final dp = snapPct.isFinite
          ? snapPct
          : jsNumOr0(buildRateSnapshot(config,
              clinic: '${p['clinic'] ?? ''}',
              service: '${p['service'] ?? ''}',
              isPros: true)['doctorPct']);
      repos.prosthetics.upsertLocal({
        ...p,
        'total': total,
        'doctorShare': net * (dp / 100),
        'clinicShare': net * ((100 - dp) / 100),
        'name': debt['name'],
      });
    }
  }
  if (totalChanged &&
      debt['type'] == 'regular' &&
      jsTruthy(debt['recordId'])) {
    final r = repos.records.getById('${debt['recordId']}');
    if (r != null) {
      repos.records
          .upsertLocal({...r, 'amount': total, 'name': debt['name']},
              base: r);
    }
  }
  }); // repos.db.transaction
}

/// forgiveDebt حرفياً — مسامحة بالمبلغ المتبقي: الإجمالي يصبح المدفوع
/// فعلياً. يعيد الإجمالي الجديد، أو null إن كان الدين غير موجود/مسدداً.
num? forgiveDebt(Repositories repos, JMap config, String debtId) {
  final existing = repos.debts.getById(debtId);
  if (existing == null || existing['status'] == 'paid') return null;
  final debt = Map<String, Object?>.from(existing);
  final paid = jsNumOr0(debt['paidAmount']);
  final newTotal = paid;
  debt['totalAmount'] = newTotal;
  debt['total'] = newTotal;
  debt['remaining'] = 0;
  debt['status'] = 'paid';
  // دفعة صفر/ج — المسامحة وانعكاسها ذرّياً.
  repos.db.transaction(() {
  repos.debts.upsertLocal(debt);

  if (jsTruthy(debt['prostheticId'])) {
    final old = repos.prosthetics.getById('${debt['prostheticId']}');
    if (old != null) {
      // معمل التركيبة نفسها (حرفية الأصل — لا معمل الدين).
      final lab = jsNumOr0(old['labValue']);
      final net = newTotal - lab;
      // نسبة تركيبات العيادة من اللقطة المجمّدة، لا العامة (إصلاح #3).
      final snap = old['_rateSnapshot'];
      final snapPct = snap is Map ? jsNumber(snap['doctorPct']) : double.nan;
      final dp = snapPct.isFinite
          ? snapPct
          : jsNumOr0(buildRateSnapshot(config,
              clinic: '${old['clinic'] ?? ''}',
              service: '${old['service'] ?? ''}',
              isPros: true)['doctorPct']);
      repos.prosthetics.upsertLocal({
        ...old,
        'total': newTotal,
        'doctorShare': (net * (dp / 100)).clamp(0, double.infinity),
        'clinicShare':
            (net * ((100 - dp) / 100)).clamp(0, double.infinity),
      });
    }
  }
  if (jsTruthy(debt['recordId'])) {
    final r = repos.records.getById('${debt['recordId']}');
    if (r != null) {
      repos.records.upsertLocal({...r, 'amount': newTotal}, base: r);
    }
  }
  }); // repos.db.transaction
  return newTotal;
}

/// doCancelPayPopupInst حرفياً — إلغاء دفعة **بمعرّفها** (لا بموضعها:
/// القائمة معكوسة للعرض والمصفوفة يعاد فرزها بعد المزامنة).
bool cancelDebtInstallment(
    Repositories repos, JMap config, String debtId, String instId) {
  final existing = repos.debts.getById(debtId);
  if (existing == null) return false;
  final debt = Map<String, Object?>.from(existing);
  final matches = activeInstallments(debt)
      .where((el) => '${el['id'] ?? ''}' == instId)
      .toList();
  if (matches.isEmpty) return false;
  final inst = matches.first;
  final instAmt = jsNumOr0(inst['amount']);
  final ip = debt['type'] == 'prosthetic';
  // نسبة تركيبات العيادة (كما اللقطة)، لا العامة 50 (إصلاح #3 الأصلي).
  final dp = ip
      ? jsNumOr0(buildRateSnapshot(config,
          clinic: '${debt['clinic'] ?? ''}', isPros: true)['doctorPct'])
      : jsNumOr0(jsOr(config['doctorPct'], 50));

  debt['paidAmount'] =
      (jsNumOr0(debt['paidAmount']) - instAmt).clamp(0, double.infinity);
  final totalDebtAmt = jsNumOr0(jsOr(debt['totalAmount'], debt['total']));
  debt['remaining'] = (totalDebtAmt - jsNumOr0(debt['paidAmount']))
      .clamp(0, double.infinity);

  if (jsNumOr0(debt['remaining']) <= 0.01) {
    debt['status'] = 'paid';
    debt['remaining'] = 0;
  } else if (jsNumOr0(debt['paidAmount']) > 0.01) {
    debt['status'] = 'partial';
  } else {
    debt['status'] = 'unpaid';
  }

  if (ip) {
    final labVal = jsNumOr0(debt['labValue']);
    final paidNow = jsNumOr0(debt['paidAmount']);
    debt['labPaid'] = paidNow < labVal ? paidNow : labVal;
    final profitPortion =
        (paidNow - jsNumOr0(debt['labPaid'])).clamp(0, double.infinity);
    debt['doctorEarned'] = profitPortion * (dp / 100);
  }

  // شاهدة حذف ناعمة (العنصر يبقى بمعرّفه) — الدمج يحوّلها شاهدة دائمة
  // على كل النسخ فلا «تنبعث» الدفعة من جديد.
  debt['installments'] = [
    for (final el in [...?(debt['installments'] as List?)])
      if (el is Map && '${el['id'] ?? ''}' == instId)
        {...el, '_deleted': 1}
      else
        el,
  ];
  // دفعة صفر/ج — إلغاء الدفعة وحذف سجلها ذرّياً: لا دينَ عُكست دفعته بينما
  // سجل الخزينة باقٍ (أو العكس) عند انهيار بينهما.
  repos.db.transaction(() {
    repos.debts.upsertLocal(debt);

    // سجل الدفعة المرتبط: بمعرّفه إن وُجد وإلا بتاريخه.
    final rid = '${inst['recordId'] ?? ''}';
    for (final r in repos.records.getAll()) {
      if (jsTruthy(r['isDebtPayment']) &&
          '${r['debtId'] ?? ''}' == '${debt['id']}' &&
          (rid.isNotEmpty
              ? '${r['id']}' == rid
              : '${r['date'] ?? ''}' == '${inst['date'] ?? ''}')) {
        repos.records.delete('${r['id']}');
        break;
      }
    }
  });
  return true;
}

/// delDebt حرفياً — حذف الدين وكل سجلات دفعاته والسجل الأصلي/التركيبة
/// (شواهد تتزامن). يعيد عدد الصفوف المحذوفة.
int deleteDebtCascade(Repositories repos, String debtId) {
  final debt = repos.debts.getById(debtId);
  if (debt == null) return 0;
  // دفعة صفر/ج — الحذف التعاقبي ذرّي: لا يبقى سجل دفعة يتيم أو تركيبة معلّقة
  // إن انهار التطبيق وسط السلسلة.
  return repos.db.transaction(() {
    var deleted = 0;
    for (final r in repos.records.getAll()) {
      if (jsTruthy(r['isDebtPayment']) && r['debtId'] == debtId) {
        repos.records.delete('${r['id']}');
        deleted++;
      }
    }
    if (jsTruthy(debt['prostheticId'])) {
      repos.prosthetics.delete('${debt['prostheticId']}');
      deleted++;
    }
    if (jsTruthy(debt['recordId'])) {
      repos.records.delete('${debt['recordId']}');
      deleted++;
    }
    repos.debts.delete(debtId);
    return deleted + 1;
  });
}
