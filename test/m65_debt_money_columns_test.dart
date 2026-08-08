/// اختبارات م65 — أعمدة المال في الديون لا تتجمّد بعد أول دفعة.
///
/// العلة: مسارات المال تكتب `paidAmount` و`totalAmount`/`total` — وهي أسماء
/// ليست أعمدة — فتذهب إلى كتلة `data` بينما يبقى العمودان الحقيقيان
/// `paid_amount` و`total_amount` على قيمتهما الأولى. النتيجة أن العمود يقول
/// شيئاً والكتلة تقول شيئاً آخر، و**الحمولة المدفوعة تحمل القيمتين معاً**
/// فتسافران متناقضتين إلى كل الأجهزة.
///
/// الإصلاح: إسقاط المرادفات على أعمدتها في BaseRepository.upsert — أي في
/// موضع واحد يغطي كل المسارات (تطبيق Flutter وصفوف Vue القديمة معاً).
library;

import 'dart:io';

import 'package:dental_clinic_flutter/app/providers.dart';
import 'package:dental_clinic_flutter/core/utils/js_compat.dart';
import 'package:dental_clinic_flutter/features/finance/debt_actions.dart'
    show payDebtInstallment, editDebt;
import 'package:dental_clinic_flutter/features/records/record_saver.dart'
    hide JMap;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('m65d_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, Object?> config() => {
        'centerName': 'مركز',
        'doctorPct': 50,
        'clinics': ['الصفوة'],
        'services': ['حشو'],
        'payments': ['كاش'],
      };

  /// قراءة العمود الحقيقي من SQL — لا الرؤية المدموجة التي تغطّي العلة.
  ({num total, num paid}) columns(ProviderContainer c, String id) {
    final r = c.read(localDbProvider).query(
        'SELECT total_amount, paid_amount FROM debts WHERE id = ?', [id]).single;
    return (
      total: jsNumOr0(r['total_amount']),
      paid: jsNumOr0(r['paid_amount'])
    );
  }

  test('الدفعة تحدّث عمود paid_amount لا كتلة البيانات وحدها', () {
    final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    addTearDown(c.dispose);
    final repos = c.read(reposProvider);

    saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'سالم', date: getCurrentDate(), amount: 1000,
          clinic: 'الصفوة', service: 'حشو', payment: 'كاش',
          isDebt: true, firstPay: 200,
        ));
    final id = repos.debts.getAll().single['id'] as String;
    expect(columns(c, id).paid, 200, reason: 'الدفعة الأولى تصل العمود');

    payDebtInstallment(repos, config(), repos.debts.getById(id)!,
        amount: 300, date: getCurrentDate(), payment: 'كاش');

    final col = columns(c, id);
    final view = repos.debts.getById(id)!;
    expect(col.paid, 500,
        reason: 'م65: العمود يتبع الدفعات ولا يتجمّد عند 200');
    expect(jsNumOr0(view['paidAmount']), 500);
    expect(col.paid, jsNumOr0(view['paidAmount']),
        reason: 'العمود والرؤية المدموجة متطابقان — لا قيمتان متناقضتان');
  });

  test('تعديل الإجمالي يحدّث عمود total_amount', () {
    final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    addTearDown(c.dispose);
    final repos = c.read(reposProvider);

    saveNewRecord(
        repos,
        config(),
        SaveRecordInput(
          name: 'هند', date: getCurrentDate(), amount: 1000,
          clinic: 'الصفوة', service: 'حشو', payment: 'كاش',
          isDebt: true, firstPay: 0,
        ));
    final id = repos.debts.getAll().single['id'] as String;
    expect(columns(c, id).total, 1000);

    editDebt(repos, config(), id,
        name: 'هند', phone: '', notes: '', total: 2000);

    expect(columns(c, id).total, 2000,
        reason: 'م65: العمود يتبع التعديل ولا يبقى على 1000');
    expect(jsNumOr0(repos.debts.getById(id)!['totalAmount']), 2000);
  });

  test('المرادف يفوز — فهو القيمة الطازجة التي يعدّلها منطق الأعمال', () {
    final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    addTearDown(c.dispose);
    final repos = c.read(reposProvider);
    // الرؤية المدموجة تحمل الاثنين دائماً؛ camelCase هي التي يزيدها الدفع
    repos.debts.upsert({
      'id': 'd1', 'patient_name': 'ن',
      'paid_amount': 11, 'paidAmount': 77,
    });
    expect(columns(c, 'd1').paid, 77);
  });

  test('صف يكتب العمود وحده (صف خادم) لا يتأثر بالإسقاط', () {
    final c = ProviderContainer(
        overrides: [dbDirProvider.overrideWithValue(tmp.path)]);
    addTearDown(c.dispose);
    final repos = c.read(reposProvider);
    repos.debts.upsert({'id': 'd2', 'patient_name': 'ن', 'paid_amount': 42});
    expect(columns(c, 'd2').paid, 42);
  });
}
